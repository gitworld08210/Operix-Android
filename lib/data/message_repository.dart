import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'load_status.dart';
import 'mappers.dart' as mappers;

/// Store for the current user's direct-message threads, backed by the Supabase
/// `conversations`, `conversation_participants`, and `messages` tables.
///
/// A [ChangeNotifier] singleton (`MessageRepository.instance`). There is NO
/// fabricated fallback: the cache starts empty with [status] ==
/// [LoadStatus.idle] and fills from live rows only. Call [load] after sign-in
/// and [clear] on sign-out.
///
/// `Conversation.lastPreview`, `updatedAt`, and each participant's `unread` are
/// server-authoritative (maintained by the `handle_new_message` trigger); the
/// client never writes them except [resetUnread], which sets its own unread to
/// zero. `Message.fromMe` is derived by comparing `messages.sender` to the
/// current auth uid.
class MessageRepository extends ChangeNotifier {
  MessageRepository();

  /// Shared singleton for the app.
  static final MessageRepository instance = MessageRepository();

  final List<Conversation> _conversations = <Conversation>[];
  LoadStatus _status = LoadStatus.idle;
  Object? _error;

  /// Live subscription to `messages` inserts. A single channel covers all of
  /// the user's conversations; inserts for conversations the user does not
  /// participate in are ignored. Created in [load] and torn down in
  /// [clear]/[dispose].
  RealtimeChannel? _channel;

  /// The conversation currently open on screen, if any. Messages arriving for
  /// this conversation are treated as already-seen so they do not inflate the
  /// unread badge. Set via [setActiveConversation].
  String? _activeConversationId;

  /// Marks [conversationId] as the conversation currently on screen (or null
  /// when none is open) so live inbound messages for it are not counted as
  /// unread. Called by ConversationScreen on open/dispose.
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
  }

  /// The current load state of [conversations].
  LoadStatus get status => _status;

  /// The most recent load error, if [status] is [LoadStatus.error].
  Object? get error => _error;

  /// Direct-message threads, most recently updated first.
  List<Conversation> conversations() {
    final list = List<Conversation>.of(_conversations)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<Conversation>.unmodifiable(list);
  }

  /// Total unread messages across all conversations.
  int get unreadMessages =>
      _conversations.fold<int>(0, (sum, c) => sum + c.unread);

  /// Finds a cached conversation by id.
  Conversation? conversationById(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Loads the conversations the current user participates in, each with the
  /// other participant's profile and the user's unread count. Messages are
  /// loaded lazily via [loadMessages]. Sets [status] and notifies in every
  /// outcome. Never throws into the UI.
  Future<void> load() async {
    _status = LoadStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) {
        _conversations.clear();
        _status = LoadStatus.loaded;
        notifyListeners();
        return;
      }

      // My participant rows carry my per-conversation unread counter.
      final myRows = await supabase
          .from('conversation_participants')
          .select('conversation_id, unread, conversations(*)')
          .eq('user_id', myId);
      final mine = (myRows as List).cast<Map<String, dynamic>>();
      if (mine.isEmpty) {
        _conversations.clear();
        _status = LoadStatus.loaded;
        notifyListeners();
        return;
      }

      final convIds = mine
          .map((r) => r['conversation_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      // The other participants of those conversations (everyone but me), with
      // their profiles, so each thread can show a counterpart.
      final otherRows = await supabase
          .from('conversation_participants')
          .select('conversation_id, user_id, profiles(*)')
          .inFilter('conversation_id', convIds)
          .neq('user_id', myId);
      final others = (otherRows as List).cast<Map<String, dynamic>>();
      final participantByConv = <String, UserProfile>{};
      for (final row in others) {
        final convId = row['conversation_id']?.toString() ?? '';
        if (convId.isEmpty || participantByConv.containsKey(convId)) continue;
        participantByConv[convId] = mappers.profileFromRow(row['profiles']);
      }

      final mapped = <Conversation>[];
      for (final row in mine) {
        final convId = row['conversation_id']?.toString() ?? '';
        if (convId.isEmpty) continue;
        final conv = row['conversations'];
        final convMap =
            conv is Map ? conv.cast<String, dynamic>() : <String, dynamic>{};
        mapped.add(
          Conversation(
            id: convId,
            participant: participantByConv[convId] ??
                const UserProfile(id: '', username: 'user', displayName: 'User'),
            messages: const <Message>[],
            lastPreview: (convMap['last_preview'] as String?) ?? '',
            updatedAt: mappers.parseDate(convMap['updated_at']),
            unread: mappers.asInt(row['unread']),
          ),
        );
      }

      _conversations
        ..clear()
        ..addAll(mapped);
      _status = LoadStatus.loaded;
      notifyListeners();
      _subscribe(myId);
    } catch (e) {
      _error = e;
      _status = LoadStatus.error;
      notifyListeners();
    }
  }

  /// Subscribes (once) to realtime inserts on `messages`. Because the payload
  /// only carries the raw row, each insert is matched against the cached
  /// conversations; unknown conversations are ignored (a later [load] will pick
  /// up a brand-new thread). Safe to call repeatedly.
  void _subscribe(String myId) {
    if (_channel != null) return;
    final channel = supabase.channel('messages:$myId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) => _onMessageInsert(payload, myId),
        )
        .subscribe();
    _channel = channel;
  }

  void _onMessageInsert(PostgresChangePayload payload, String myId) {
    try {
      final row = payload.newRecord;
      final convId = row['conversation_id']?.toString() ?? '';
      if (convId.isEmpty) return;
      final i = _indexOf(convId);
      // Not one of my cached conversations: a periodic/next load() reconciles
      // (e.g. someone just opened a brand-new thread with me).
      if (i < 0) return;

      final message = _messageFromRow(row, myId);
      final current = _conversations[i];

      // De-duplicate against the optimistic append from sendMessage.
      final alreadyThere = current.messages.any((m) => m.id == message.id);
      final messages = alreadyThere
          ? current.messages
          : <Message>[...current.messages, message];

      // Only bump unread for inbound messages that are not for the open thread.
      final isInbound = !message.fromMe;
      final countsAsUnread =
          isInbound && convId != _activeConversationId && !alreadyThere;

      _conversations[i] = current.copyWith(
        messages: messages,
        lastPreview: message.text,
        updatedAt: message.sentAt,
        unread: countsAsUnread ? current.unread + 1 : current.unread,
      );
      notifyListeners();
    } catch (_) {
      // Best-effort; a later load() reconciles state.
    }
  }

  /// Loads the messages for [conversationId], newest activity reflected in the
  /// cached [Conversation.messages], and returns them oldest-first. Each
  /// message's `fromMe` is derived from `sender` vs the current auth uid.
  Future<List<Message>> loadMessages(String conversationId) async {
    try {
      final myId = supabase.auth.currentUser?.id;
      final rows = await supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('sent_at', ascending: true);
      final data = (rows as List).cast<Map<String, dynamic>>();
      final messages =
          data.map((r) => _messageFromRow(r, myId)).toList(growable: false);

      final i = _indexOf(conversationId);
      if (i >= 0) {
        _conversations[i] = _conversations[i].copyWith(messages: messages);
        notifyListeners();
      }
      return messages;
    } catch (_) {
      return const <Message>[];
    }
  }

  /// Sends a message into [conversationId] as the current user. The message id
  /// is generated by the DB; preview/updated_at/unread are trigger-maintained.
  /// Appends the sent message to the cached thread optimistically and returns
  /// it, or null on failure.
  Future<Message?> sendMessage(String conversationId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) return null;
      final inserted = await supabase
          .from('messages')
          .insert(<String, dynamic>{
            'conversation_id': conversationId,
            'sender': myId,
            'text': trimmed,
          })
          .select()
          .single();
      final message = _messageFromRow(inserted, myId);

      final i = _indexOf(conversationId);
      if (i >= 0) {
        final current = _conversations[i];
        _conversations[i] = current.copyWith(
          messages: <Message>[...current.messages, message],
          lastPreview: trimmed,
          updatedAt: message.sentAt,
        );
        notifyListeners();
      }
      return message;
    } catch (_) {
      return null;
    }
  }

  /// Finds an existing 1:1 conversation with [otherUserId], or creates one,
  /// and returns its id. Returns null when signed out or on failure.
  ///
  /// Delegates to the `create_direct_conversation` SECURITY DEFINER RPC, which
  /// finds-or-creates the conversation and inserts BOTH participant rows
  /// atomically. This avoids the RLS pitfall of the old client-side batch
  /// insert: the `participants_insert_self_or_member` check
  /// (`auth.uid() = user_id OR is_conversation_participant(conversation_id)`)
  /// rejects the other user's row in a single multi-row INSERT because the
  /// caller's sibling row is not yet visible to `is_conversation_participant`.
  Future<String?> openOrCreateConversationWith(String otherUserId) async {
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null || otherUserId == myId) return null;

      final result = await supabase.rpc(
        'create_direct_conversation',
        params: <String, dynamic>{'other_user': otherUserId},
      );
      final convId = result?.toString() ?? '';
      if (convId.isEmpty) return null;

      await load();
      return convId;
    } catch (_) {
      return null;
    }
  }

  /// Resets the current user's unread counter for [conversationId] to zero,
  /// optimistically in memory and then persisted. Guarded.
  Future<void> resetUnread(String conversationId) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    final i = _indexOf(conversationId);
    if (i >= 0 && _conversations[i].unread != 0) {
      _conversations[i] = _conversations[i].copyWith(unread: 0);
      notifyListeners();
    }
    try {
      await supabase
          .from('conversation_participants')
          .update(<String, dynamic>{'unread': 0})
          .eq('conversation_id', conversationId)
          .eq('user_id', myId);
    } catch (_) {
      // Best-effort; the optimistic reset stands for this session.
    }
  }

  /// Clears cached state (e.g. on sign-out) and tears down the realtime
  /// subscription so a signed-out user receives no further callbacks.
  void clear() {
    _teardownChannel();
    _activeConversationId = null;
    _conversations.clear();
    _status = LoadStatus.idle;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _teardownChannel();
    super.dispose();
  }

  void _teardownChannel() {
    final channel = _channel;
    if (channel == null) return;
    _channel = null;
    // ignore: discarded_futures
    supabase.removeChannel(channel);
  }

  // -- Helpers -------------------------------------------------------------

  int _indexOf(String conversationId) =>
      _conversations.indexWhere((c) => c.id == conversationId);

  Message _messageFromRow(Map<String, dynamic> row, String? myId) =>
      mappers.messageFromRow(row, myId);
}
