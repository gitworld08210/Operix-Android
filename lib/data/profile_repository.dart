import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../models/notification_item.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'mock_data.dart';

/// Store for the current user, the known profiles, notifications, and
/// conversations.
///
/// `currentUser` and `profiles` are backed by Supabase (the `profiles` table)
/// with a graceful [MockData] fallback: they are seeded from mock data at
/// construction and hydrated asynchronously via [load] (fire-and-forget from
/// the constructor). [load] is fully guarded so it is a no-op when Supabase is
/// unavailable (e.g. under `flutter test` or offline) and only notifies when it
/// actually replaces the seed with live rows.
///
/// `notifications()` is backed by the Supabase `notifications` table (added in
/// migration 0002) with the same graceful [MockData] fallback: the cache is
/// seeded from mock data and hydrated asynchronously via [load]. `read` state
/// is persisted back to the table by [markNotificationsRead] (guarded).
///
/// COHESION NOTE: notifications stay on [ProfileRepository] rather than a new
/// `NotificationRepository`. They are read-only-plus-mark-read (clients never
/// insert notifications; they are produced by SECURITY DEFINER triggers), they
/// key off actor [UserProfile] data this repository already owns, and the
/// existing `profile_repository_test.dart` asserts this surface. A dedicated
/// repository would add a singleton for a small, tightly-coupled surface with
/// no independent lifecycle, so folding it in here is the cohesive choice.
///
/// `conversations()` remains **mock-only** for now (there is no messages table
/// in the schema yet); this is documented in the README's live-vs-mock section.
class ProfileRepository extends ChangeNotifier {
  ProfileRepository()
      : _currentUser = MockData.currentUser,
        _profiles = List<UserProfile>.of(MockData.profiles),
        _notifications = MockData.notifications(),
        _conversations = MockData.conversations() {
    // Hydrate current user + profiles from Supabase in the background.
    // Guarded so it is a no-op (and does not notify) when Supabase is
    // unavailable, leaving the mock seed intact for tests and offline UI.
    // ignore: discarded_futures
    load();
    // Hydrate notifications from the Supabase `notifications` table in the
    // background (guarded, mock fallback preserved).
    // ignore: discarded_futures
    loadNotifications();
  }

  /// Shared singleton for the app.
  static final ProfileRepository instance = ProfileRepository();

  UserProfile _currentUser;
  List<UserProfile> _profiles;
  List<NotificationItem> _notifications;
  final List<Conversation> _conversations;

  /// The signed-in user.
  UserProfile get currentUser => _currentUser;

  /// All profiles known to the app (for search / suggestions).
  List<UserProfile> get profiles => List<UserProfile>.unmodifiable(_profiles);

  /// Hydrates [_currentUser] and [_profiles] from the Supabase `profiles`
  /// table. Fire-and-forget; fully guarded so it never throws (e.g. when
  /// Supabase is uninitialized under tests) and only notifies on live rows.
  Future<void> load() async {
    try {
      final rows = await supabase.from('profiles').select();
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return; // keep the mock seed as a graceful fallback
      final mapped = data.map(_profileFromRow).toList();
      final myId = supabase.auth.currentUser?.id;
      _profiles = mapped;
      if (myId != null) {
        for (final p in mapped) {
          if (p.id == myId) {
            _currentUser = p;
            break;
          }
        }
      }
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  /// Hydrates [_notifications] from the Supabase `notifications` table for the
  /// signed-in recipient (newest-first). Joins the actor's `profiles` row so
  /// the UI can render the actor. Fire-and-forget; fully guarded so it never
  /// throws (e.g. when Supabase is uninitialized under tests) and only notifies
  /// when it actually replaces the seed with live rows.
  Future<void> loadNotifications() async {
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) return; // keep the mock seed as a graceful fallback
      final rows = await supabase
          .from('notifications')
          .select('*, actor:profiles!notifications_actor_fkey(*)')
          .eq('recipient', myId)
          .order('created_at', ascending: false);
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return; // keep the mock seed as a graceful fallback
      _notifications = data.map(_notificationFromRow).toList();
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  /// Activity notifications, newest first. Backed by the `notifications` table
  /// with a mock fallback (see [loadNotifications]).
  List<NotificationItem> notifications() {
    final list = List<NotificationItem>.of(_notifications);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<NotificationItem>.unmodifiable(list);
  }

  /// Number of unread notifications.
  int get unreadNotifications => _notifications.where((n) => !n.read).length;

  /// Direct-message threads, most recently updated first. (Still mock-backed.)
  List<Conversation> conversations() {
    final list = List<Conversation>.of(_conversations);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<Conversation>.unmodifiable(list);
  }

  /// Total unread messages across all conversations.
  int get unreadMessages =>
      _conversations.fold<int>(0, (sum, c) => sum + c.unread);

  /// Finds a conversation by id.
  Conversation? conversationById(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Marks all notifications as read, optimistically in memory and then
  /// persisted to the `notifications` table (fire-and-forget, guarded).
  void markNotificationsRead() {
    var changed = false;
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].read) {
        _notifications[i] = _notifications[i].copyWith(read: true);
        changed = true;
      }
    }
    if (!changed) return; // idempotent: nothing to update, no notify, no write
    notifyListeners();
    // ignore: discarded_futures
    _persistNotificationsRead();
  }

  /// Persists `read = true` for the signed-in recipient's notifications.
  /// Guarded so it never throws into the UI when Supabase is unavailable; the
  /// optimistic in-memory read state stands regardless.
  Future<void> _persistNotificationsRead() async {
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) return;
      await supabase
          .from('notifications')
          .update(<String, dynamic>{'read': true})
          .eq('recipient', myId)
          .eq('read', false);
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Updates the current user's editable fields, optimistically in memory and
  /// then persisted to Supabase (fire-and-forget, guarded).
  void updateProfile({String? displayName, String? bio}) {
    _currentUser = _currentUser.copyWith(displayName: displayName, bio: bio);
    notifyListeners();
    // ignore: discarded_futures
    _persistProfile(displayName: displayName, bio: bio);
  }

  /// Persists editable profile fields to the Supabase `profiles` table.
  Future<void> _persistProfile({String? displayName, String? bio}) async {
    try {
      final id = supabase.auth.currentUser?.id;
      if (id == null) return;
      final changes = <String, dynamic>{
        if (displayName != null) 'display_name': displayName,
        if (bio != null) 'bio': bio,
      };
      if (changes.isEmpty) return;
      await supabase.from('profiles').update(changes).eq('id', id);
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory copy stands.
    }
  }

  // -- Mapping -------------------------------------------------------------

  /// Maps a `notifications` row (with a joined actor `profiles` object) to a
  /// [NotificationItem]. Unknown/absent types fall back to
  /// [NotificationType.system].
  NotificationItem _notificationFromRow(Map<String, dynamic> row) {
    return NotificationItem(
      id: row['id']?.toString() ?? '',
      type: _notificationTypeFromName(row['type'] as String?),
      actor: _actorFromRow(row['actor']),
      preview: row['preview'] as String?,
      createdAt: _parseDate(row['created_at']),
      read: (row['read'] as bool?) ?? false,
    );
  }

  /// Maps the `notifications.type` string to a [NotificationType]. Handles the
  /// snake_case `follow_request` and unknown values (defaulting to `system`).
  static NotificationType _notificationTypeFromName(String? name) {
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
      case 'follow_request':
        return NotificationType.followRequest;
      case 'system':
      default:
        return NotificationType.system;
    }
  }

  /// Builds the actor [UserProfile] from a joined `profiles` object. Falls back
  /// to a minimal placeholder when the join is absent (e.g. a `system`
  /// notification with no actor).
  UserProfile _actorFromRow(Object? profiles) {
    if (profiles is Map) {
      return _profileFromRow(profiles.cast<String, dynamic>());
    }
    return const UserProfile(id: '', username: 'system', displayName: 'System');
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }

  /// Maps a `profiles` row to a [UserProfile].
  UserProfile _profileFromRow(Map<String, dynamic> row) {
    final username = (row['username'] as String?) ?? 'user';
    return UserProfile(
      id: row['id']?.toString() ?? '',
      username: username,
      displayName: (row['display_name'] as String?) ?? username,
      bio: (row['bio'] as String?) ?? '',
      avatarUrl: row['avatar_url'] as String?,
      bannerUrl: row['banner_url'] as String?,
      verified: (row['verified'] as bool?) ?? false,
      verificationKind: (row['verification_kind'] as String?) ?? 'verified',
      followers: _asInt(row['followers']),
      following: _asInt(row['following']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
