import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_item.dart';
import '../supabase_config.dart';
import 'load_status.dart';
import 'mappers.dart' as mappers;

/// Store for the current user's activity notifications, backed by the Supabase
/// `notifications` table (joined to the actor's profile).
///
/// A [ChangeNotifier] singleton (`NotificationRepository.instance`) so screens
/// can listen via `AnimatedBuilder(animation: NotificationRepository.instance)`
/// like the other repositories. There is NO fabricated fallback: the cache
/// starts empty with [status] == [LoadStatus.idle] and only fills from live
/// rows. Call [load] after sign-in and [clear] on sign-out.
class NotificationRepository extends ChangeNotifier {
  NotificationRepository();

  /// Shared singleton for the app.
  static final NotificationRepository instance = NotificationRepository();

  final List<NotificationItem> _notifications = <NotificationItem>[];
  LoadStatus _status = LoadStatus.idle;
  Object? _error;

  /// Live subscription to `notifications` inserts for the current recipient.
  /// Created in [load] and torn down in [clear]/[dispose] so a signed-out user
  /// never receives stale callbacks.
  RealtimeChannel? _channel;

  /// The current load state of [notifications].
  LoadStatus get status => _status;

  /// The most recent load error, if [status] is [LoadStatus.error].
  Object? get error => _error;

  /// Activity notifications, newest first.
  List<NotificationItem> notifications() {
    final list = List<NotificationItem>.of(_notifications)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<NotificationItem>.unmodifiable(list);
  }

  /// Number of unread notifications currently cached.
  int get unreadNotifications => _notifications.where((n) => !n.read).length;

  /// Loads the current user's notifications from Supabase. Sets [status] and
  /// notifies in every outcome (loading, loaded, error) so listeners can
  /// render real states. Never throws into the UI.
  Future<void> load() async {
    _status = LoadStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) {
        _notifications.clear();
        _status = LoadStatus.loaded;
        notifyListeners();
        return;
      }
      final rows = await supabase
          .from('notifications')
          .select('*, actor:profiles!notifications_actor_profile_fkey(*)')
          .eq('recipient', myId)
          .order('created_at', ascending: false);
      final data = (rows as List).cast<Map<String, dynamic>>();
      _notifications
        ..clear()
        ..addAll(data.map(_notificationFromRow));
      _status = LoadStatus.loaded;
      notifyListeners();
      _subscribe(myId);
    } catch (e) {
      _error = e;
      _status = LoadStatus.error;
      notifyListeners();
    }
  }

  /// Subscribes (once) to realtime inserts on `notifications` for [recipient].
  /// A new row only carries foreign keys, so the actor profile is fetched
  /// before the item is inserted into the cache and listeners are notified.
  /// Safe to call repeatedly: an existing channel is reused.
  void _subscribe(String recipient) {
    if (_channel != null) return;
    final channel = supabase.channel('notifications:$recipient');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient',
            value: recipient,
          ),
          callback: _onInsert,
        )
        .subscribe();
    _channel = channel;
  }

  Future<void> _onInsert(PostgresChangePayload payload) async {
    try {
      final id = payload.newRecord['id']?.toString();
      if (id == null || id.isEmpty) return;
      // Ignore duplicates (e.g. an item already loaded or self-inserted).
      if (_notifications.any((n) => n.id == id)) return;
      // The realtime payload lacks the embedded actor profile, so hydrate the
      // full joined row for this id.
      final row = await supabase
          .from('notifications')
          .select('*, actor:profiles!notifications_actor_profile_fkey(*)')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return;
      final item = _notificationFromRow(row);
      if (_notifications.any((n) => n.id == item.id)) return;
      _notifications.insert(0, item);
      notifyListeners();
    } catch (_) {
      // Realtime hydration is best-effort; a later load() reconciles state.
    }
  }

  /// Marks all of the current user's notifications read, optimistically in
  /// memory and then persisted. Reverts and surfaces an error on failure.
  Future<void> markNotificationsRead() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;
    if (_notifications.every((n) => n.read)) return;

    final previous = List<NotificationItem>.of(_notifications);
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].read) {
        _notifications[i] = _notifications[i].copyWith(read: true);
      }
    }
    notifyListeners();

    try {
      await supabase
          .from('notifications')
          .update(<String, dynamic>{'read': true})
          .eq('recipient', myId)
          .eq('read', false);
    } catch (e) {
      _notifications
        ..clear()
        ..addAll(previous);
      _error = e;
      notifyListeners();
    }
  }

  /// Creates a notification for [recipient] as a side effect of a
  /// like/reply/repost/follow action. No-op when the actor is the recipient
  /// (the RLS `actor <> recipient` check would reject it anyway) or when
  /// signed out. Fully guarded: notification creation must never break the
  /// primary action, so failures are swallowed.
  Future<void> createNotification({
    required String recipient,
    required NotificationType type,
    String? postId,
    String? preview,
  }) async {
    try {
      final actor = supabase.auth.currentUser?.id;
      if (actor == null || actor == recipient) return;

      // De-dupe repeat notifications: toggling a like/repost off and on again,
      // or re-following, should not spam a fresh row each time. Only insert
      // when no matching (actor, recipient, type, post) notification exists.
      // The whole method is guarded by the outer try/catch, so this probe
      // never breaks the primary action.
      var existing = supabase
          .from('notifications')
          .select('id')
          .eq('recipient', recipient)
          .eq('actor', actor)
          .eq('type', type.name);
      existing = postId != null
          ? existing.eq('post_id', postId)
          : existing.isFilter('post_id', null);
      final priorRows = await existing.limit(1);
      if ((priorRows as List).isNotEmpty) return;

      await supabase.from('notifications').insert(<String, dynamic>{
        'recipient': recipient,
        'actor': actor,
        'type': type.name,
        if (postId != null) 'post_id': postId,
        if (preview != null) 'preview': preview,
      });
    } catch (_) {
      // Notifications are best-effort; never surface a failure to the caller.
    }
  }

  /// Clears all cached state (e.g. on sign-out) so a subsequent login does not
  /// show the previous user's notifications. Also tears down the realtime
  /// subscription so a signed-out user receives no further callbacks.
  void clear() {
    _teardownChannel();
    _notifications.clear();
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
    // Remove the channel from the client; unawaited on purpose (fire-and-forget
    // teardown), guarded so a failure never surfaces.
    // ignore: discarded_futures
    supabase.removeChannel(channel);
  }

  // -- Mapping (delegates to the pure helpers in mappers.dart) -------------

  NotificationItem _notificationFromRow(Map<String, dynamic> row) =>
      mappers.notificationFromRow(row);
}
