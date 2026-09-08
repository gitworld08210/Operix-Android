import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'load_status.dart';
import 'mappers.dart' as mappers;
import 'notification_repository.dart';

/// Store for the current user and the profiles known to the app, fully backed
/// by the Supabase `profiles` table (no mock fallback).
///
/// A [ChangeNotifier] singleton (`ProfileRepository.instance`). [currentUser]
/// is null until [load] resolves it after sign-in; [status] exposes the real
/// loading/loaded/error state. Notifications and direct messages now live in
/// their own repositories ([NotificationRepository], [MessageRepository]).
///
/// Follows are real: [toggleFollow] inserts/deletes rows in the `follows`
/// table and never writes the DB-owned `followers` / `following` counters.
class ProfileRepository extends ChangeNotifier {
  ProfileRepository();

  /// Shared singleton for the app.
  static final ProfileRepository instance = ProfileRepository();

  UserProfile? _currentUser;
  final List<UserProfile> _profiles = <UserProfile>[];
  final Set<String> _followingIds = <String>{};
  LoadStatus _status = LoadStatus.idle;
  Object? _error;

  /// The signed-in user, or null before [load] resolves it / after sign-out.
  UserProfile? get currentUser => _currentUser;

  /// The current load state of [profiles] / [currentUser].
  LoadStatus get status => _status;

  /// The most recent load error, if [status] is [LoadStatus.error].
  Object? get error => _error;

  /// All profiles known to the app (for search / suggestions).
  List<UserProfile> get profiles => List<UserProfile>.unmodifiable(_profiles);

  /// The set of user ids the current user follows.
  Set<String> get followingIds => Set<String>.unmodifiable(_followingIds);

  /// Loads all profiles, resolves [currentUser] from the signed-in id, and
  /// hydrates the follow set. Sets [status] and notifies in every outcome.
  /// Never throws into the UI.
  Future<void> load() async {
    _status = LoadStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final rows = await supabase.from('profiles').select();
      final data = (rows as List).cast<Map<String, dynamic>>();
      _profiles
        ..clear()
        ..addAll(data.map(_profileFromRow));

      final myId = supabase.auth.currentUser?.id;
      _currentUser = null;
      if (myId != null) {
        for (final p in _profiles) {
          if (p.id == myId) {
            _currentUser = p;
            break;
          }
        }
      }

      await loadFollowing();

      _status = LoadStatus.loaded;
      notifyListeners();
    } catch (e) {
      _error = e;
      _status = LoadStatus.error;
      notifyListeners();
    }
  }

  /// Loads (into [followingIds]) the set of user ids the current user follows.
  Future<void> loadFollowing() async {
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) {
        _followingIds.clear();
        return;
      }
      final rows = await supabase
          .from('follows')
          .select('followee')
          .eq('follower', myId);
      final data = (rows as List).cast<Map<String, dynamic>>();
      _followingIds
        ..clear()
        ..addAll(
          data
              .map((r) => r['followee']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
    } catch (_) {
      // Keep the current set.
    }
  }

  /// Whether the current user follows [id].
  bool isFollowing(String id) => _followingIds.contains(id);

  /// Follows or unfollows [targetUserId] by inserting/deleting a `follows`
  /// row (never writing the DB-owned follower/following counters). Optimistic;
  /// reverts on failure. Creates a follow notification for the target on a new
  /// follow.
  Future<void> toggleFollow(String targetUserId) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null || targetUserId == myId) return;

    final wasFollowing = _followingIds.contains(targetUserId);
    if (wasFollowing) {
      _followingIds.remove(targetUserId);
    } else {
      _followingIds.add(targetUserId);
    }
    notifyListeners();

    try {
      if (wasFollowing) {
        await supabase
            .from('follows')
            .delete()
            .eq('follower', myId)
            .eq('followee', targetUserId);
      } else {
        await supabase.from('follows').insert(<String, dynamic>{
          'follower': myId,
          'followee': targetUserId,
        });
        await NotificationRepository.instance.createNotification(
          recipient: targetUserId,
          type: NotificationType.follow,
        );
      }
    } catch (_) {
      // Revert the optimistic change on failure.
      if (wasFollowing) {
        _followingIds.add(targetUserId);
      } else {
        _followingIds.remove(targetUserId);
      }
      notifyListeners();
    }
  }

  /// Fetches a single profile by id (from cache if present, otherwise the DB).
  Future<UserProfile?> profileById(String id) async {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    try {
      final row = await supabase
          .from('profiles')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return _profileFromRow(row);
    } catch (_) {
      return null;
    }
  }

  /// Searches profiles by username / display name via the `search_profiles`
  /// RPC (case-insensitive trigram). Returns an empty list on failure or for a
  /// blank query.
  Future<List<UserProfile>> searchProfiles(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const <UserProfile>[];
    try {
      final rows = await supabase.rpc(
        'search_profiles',
        params: <String, dynamic>{'q': q},
      );
      final data = (rows as List).cast<Map<String, dynamic>>();
      return data.map(_profileFromRow).toList(growable: false);
    } catch (_) {
      return const <UserProfile>[];
    }
  }

  /// Suggested people to follow for the idle search state: profiles other than
  /// the current user, not already followed. Returns an empty list on failure.
  Future<List<UserProfile>> suggestedProfiles({int limit = 20}) async {
    try {
      final myId = supabase.auth.currentUser?.id;
      final rows = await supabase.from('profiles').select().limit(limit);
      final data = (rows as List).cast<Map<String, dynamic>>();
      return data
          .map(_profileFromRow)
          .where((p) => p.id != myId && !_followingIds.contains(p.id))
          .toList(growable: false);
    } catch (_) {
      return const <UserProfile>[];
    }
  }

  /// Fetches a single profile by username.
  Future<UserProfile?> profileByUsername(String username) async {
    try {
      final row = await supabase
          .from('profiles')
          .select()
          .eq('username', username)
          .maybeSingle();
      if (row == null) return null;
      return _profileFromRow(row);
    } catch (_) {
      return null;
    }
  }

  /// Updates the current user's editable fields, optimistically in memory and
  /// then persisted. Reverts on failure. No-op when signed out.
  Future<void> updateProfile({String? displayName, String? bio}) async {
    final current = _currentUser;
    if (current == null) return;
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    final changes = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
    };
    if (changes.isEmpty) return;

    _currentUser = current.copyWith(displayName: displayName, bio: bio);
    notifyListeners();

    try {
      await supabase.from('profiles').update(changes).eq('id', myId);
    } catch (_) {
      _currentUser = current;
      notifyListeners();
    }
  }

  /// Clears cached state (e.g. on sign-out).
  void clear() {
    _currentUser = null;
    _profiles.clear();
    _followingIds.clear();
    _status = LoadStatus.idle;
    _error = null;
    notifyListeners();
  }

  // -- Mapping (delegates to the pure helpers in mappers.dart) -------------

  UserProfile _profileFromRow(Map<String, dynamic> row) =>
      mappers.profileFromRow(row);
}
