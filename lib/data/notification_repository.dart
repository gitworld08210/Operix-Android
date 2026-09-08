import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'load_status.dart';

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
    } catch (e) {
      _error = e;
      _status = LoadStatus.error;
      notifyListeners();
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
  /// show the previous user's notifications.
  void clear() {
    _notifications.clear();
    _status = LoadStatus.idle;
    _error = null;
    notifyListeners();
  }

  // -- Mapping -------------------------------------------------------------

  NotificationItem _notificationFromRow(Map<String, dynamic> row) {
    return NotificationItem(
      id: row['id']?.toString() ?? '',
      type: _typeFromName(row['type'] as String?),
      actor: _actorFromRow(row['actor']),
      preview: row['preview'] as String?,
      createdAt: _parseDate(row['created_at']),
      read: (row['read'] as bool?) ?? false,
    );
  }

  UserProfile _actorFromRow(Object? actor) {
    if (actor is Map) {
      final p = actor.cast<String, dynamic>();
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

  static NotificationType _typeFromName(String? name) {
    switch (name) {
      case 'like':
        return NotificationType.like;
      case 'reply':
        return NotificationType.reply;
      case 'repost':
        return NotificationType.repost;
      case 'follow':
        return NotificationType.follow;
      case 'mention':
        return NotificationType.mention;
      default:
        return NotificationType.like;
    }
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
