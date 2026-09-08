import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'load_status.dart';

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
        participantByConv[convId] = _profileFromRow(row['profiles']);
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
            updatedAt: _parseDate(convMap['updated_at']),
            unread: _asInt(row['unread']),
          ),
        );
      }

      _conversations
        ..clear()
        ..addAll(mapped);
      _status = LoadStatus.loaded;
      notifyListeners();
    } catch (e) {
      _error = e;
      _status = LoadStatus.error;
      notifyListeners();
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

  /// Finds an existing 1:1 conversation with [otherUserId], or creates one
  /// (a `conversations` row plus two `conversation_participants` rows) and
  /// returns its id. Returns null when signed out or on failure.
  Future<String?> openOrCreateConversationWith(String otherUserId) async {
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null || otherUserId == myId) return null;

      // Look for an existing thread that both users participate in.
      final myRows = await supabase
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', myId);
      final myConvIds = (myRows as List)
          .cast<Map<String, dynamic>>()
          .map((r) => r['conversation_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (myConvIds.isNotEmpty) {
        final shared = await supabase
            .from('conversation_participants')
            .select('conversation_id')
            .eq('user_id', otherUserId)
            .inFilter('conversation_id', myConvIds);
        final sharedList = (shared as List).cast<Map<String, dynamic>>();
        if (sharedList.isNotEmpty) {
          final existingId =
              sharedList.first['conversation_id']?.toString() ?? '';
          if (existingId.isNotEmpty) {
            await load();
            return existingId;
          }
        }
      }

      // None exists: create the shell and add both participants.
      final conv = await supabase
          .from('conversations')
          .insert(<String, dynamic>{})
          .select('id')
          .single();
      final convId = conv['id']?.toString() ?? '';
      if (convId.isEmpty) return null;

      await supabase.from('conversation_participants').insert(<Map<String, dynamic>>[
        <String, dynamic>{'conversation_id': convId, 'user_id': myId},
        <String, dynamic>{'conversation_id': convId, 'user_id': otherUserId},
      ]);

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

  /// Clears cached state (e.g. on sign-out).
  void clear() {
    _conversations.clear();
    _status = LoadStatus.idle;
    _error = null;
    notifyListeners();
  }

  // -- Helpers -------------------------------------------------------------

  int _indexOf(String conversationId) =>
      _conversations.indexWhere((c) => c.id == conversationId);

  Message _messageFromRow(Map<String, dynamic> row, String? myId) {
    return Message(
      id: row['id']?.toString() ?? '',
      fromMe: myId != null && row['sender']?.toString() == myId,
      text: (row['text'] as String?) ?? '',
      sentAt: _parseDate(row['sent_at']),
    );
  }

  UserProfile _profileFromRow(Object? profile) {
    if (profile is Map) {
      final p = profile.cast<String, dynamic>();
      final username = (p['username'] as String?) ?? 'user';
      return UserProfile(
        id: p['id']?.toString() ?? '',
        username: username,
        displayName: (p['display_name'] as String?) ?? username,
        bio: (p['bio'] as String?) ?? '',
        avatarUrl: p['avatar_url'] as String?,
        bannerUrl: p['banner_url'] as String?,
        verified: (p['verified'] as bool?) ?? false,
        verificationKind: (p['verification_kind'] as String?) ?? 'verified',
        followers: _asInt(p['followers']),
        following: _asInt(p['following']),
      );
    }
    return const UserProfile(id: '', username: 'user', displayName: 'User');
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }
}
