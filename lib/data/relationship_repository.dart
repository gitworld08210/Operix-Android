import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'mock_data.dart';

/// The viewer's follow state toward another account.
///
/// Mirrors the client side of the FEAT-002 `follows.status` contract:
///
///  * [none] — no follow row exists.
///  * [requested] — a `status = 'pending'` row exists (created when the viewer
///    follows a PRIVATE account; it awaits the followee's acceptance).
///  * [following] — a `status = 'accepted'` row exists (created directly when
///    the viewer follows a PUBLIC account, or after a private account accepts).
enum FollowState { none, requested, following }

/// Decides the follow status to create for [target].
///
/// PURE + independently unit-tested. A follow of a PRIVATE account is created
/// as [FollowState.requested] (server row `status = 'pending'`); a follow of a
/// PUBLIC account is created as [FollowState.following] (server row
/// `status = 'accepted'`). This is the client half of the migration-0002
/// contract; the server (`can_view_profile`) remains the true gate.
FollowState followStateForNewFollow(UserProfile target) =>
    target.isPrivate ? FollowState.requested : FollowState.following;

/// An immutable incoming follow request (an account asking to follow the
/// viewer), paired with when it arrived so the list can be newest-first.
class FollowRequest {
  const FollowRequest({required this.actor, required this.createdAt});

  final UserProfile actor;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FollowRequest && other.actor.id == actor.id);

  @override
  int get hashCode => actor.id.hashCode;
}

/// Owns the viewer's RELATIONSHIP state: the outgoing follow edges they have
/// created (keyed by followee id with a 'pending'|'accepted' status) and the
/// incoming pending follow-requests awaiting their acceptance.
///
/// Follows the same contract as the other repositories (see [PostRepository]/
/// [SafetyRepository]):
///
///  * a synchronous public surface ([followStateFor], [pendingRequests], and
///    the [follow]/[unfollow]/[acceptFollowRequest]/[denyFollowRequest]
///    mutators) over in-memory state seeded from [MockData] so the UI and unit
///    tests (which never boot Supabase) always have state immediately;
///  * mutations that update state optimistically, fire EXACTLY ONE
///    [notifyListeners] only on a real change (idempotent — no notify when the
///    state is already as requested), and persist to `public.follows` via a
///    separate guarded helper that never throws into the UI; and
///  * a fire-and-forget, fully guarded [load] that hydrates the outgoing edges
///    (`follows` where `follower = auth.uid()`) and incoming pending requests
///    (`follows` where `followee = auth.uid()` and `status = 'pending'`),
///    only notifying when live rows replace the seed.
///
/// FOLLOWS CONTRACT (migration 0002): the `public.follows` table is keyed by
/// `(follower, followee)` with a `status` column constrained to
/// `('pending', 'accepted')`. A follow of a PUBLIC account is created directly
/// as `'accepted'`; a follow of a PRIVATE account is created as `'pending'` and
/// later flipped to `'accepted'` by the followee (accepting the request). A
/// private account's profile/posts only become visible once the follow row is
/// `'accepted'` — the SECURITY DEFINER `can_view_profile` helper is the TRUE
/// gate; the client-side 'private account' UI gate is a UX mirror of it.
class RelationshipRepository extends ChangeNotifier {
  RelationshipRepository()
      : _edges = Map<String, FollowState>.fromEntries(
          MockData.followEdges().entries.map(
            (e) => MapEntry(e.key, _stateFromStatus(e.value)),
          ),
        ),
        _requests = MockData.pendingFollowRequests()
            .asMap()
            .entries
            .map(
              // Preserve seed order as newest-first by assigning descending
              // synthetic timestamps; live rows carry real created_at values.
              (e) => FollowRequest(
                actor: e.value,
                createdAt: DateTime.now().subtract(Duration(minutes: e.key)),
              ),
            )
            .toList() {
    // Hydrate from Supabase in the background. Guarded so it is a no-op when
    // Supabase is unavailable (tests / offline), leaving the mock seed intact.
    // ignore: discarded_futures
    load();
  }

  /// Shared singleton for the app.
  static final RelationshipRepository instance = RelationshipRepository();

  /// Outgoing follow edges keyed by followee id. Only [FollowState.requested]
  /// and [FollowState.following] are stored; a missing key is [FollowState.none].
  final Map<String, FollowState> _edges;

  /// Incoming pending follow requests, held newest-first.
  final List<FollowRequest> _requests;

  /// The viewer's follow state toward [userId] ([FollowState.none] when there
  /// is no edge).
  FollowState followStateFor(String userId) =>
      _edges[userId] ?? FollowState.none;

  /// The incoming pending follow requests, newest-first (unmodifiable view).
  List<UserProfile> pendingRequests() {
    final sorted = List<FollowRequest>.of(_requests)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<UserProfile>.unmodifiable(
      sorted.map((r) => r.actor).toList(),
    );
  }

  /// Hydrates [_edges] and [_requests] from Supabase for the signed-in user.
  /// Fire-and-forget; fully guarded so it never throws (e.g. when Supabase is
  /// uninitialized under tests) and only notifies when it actually replaces the
  /// seed with live rows.
  Future<void> load() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return; // keep the mock seed as a graceful fallback

      final outgoing = await supabase
          .from('follows')
          .select('followee, status')
          .eq('follower', userId);
      final outgoingData = (outgoing as List).cast<Map<String, dynamic>>();

      final incoming = await supabase
          .from('follows')
          .select('follower, status, created_at, profiles:profiles!follows_follower_fkey(*)')
          .eq('followee', userId)
          .eq('status', 'pending');
      final incomingData = (incoming as List).cast<Map<String, dynamic>>();

      final newEdges = <String, FollowState>{};
      for (final row in outgoingData) {
        final followee = row['followee']?.toString() ?? '';
        if (followee.isEmpty) continue;
        newEdges[followee] = _stateFromStatus(row['status'] as String?);
      }

      final newRequests = <FollowRequest>[];
      for (final row in incomingData) {
        final actor = _actorFromRow(row['profiles'], row['follower']);
        if (actor.id.isEmpty) continue;
        newRequests.add(
          FollowRequest(actor: actor, createdAt: _parseDate(row['created_at'])),
        );
      }

      // Notify-only-on-real-change: mirror SafetyRepository.load()'s setEquals
      // guard. Bail out before clearing/refilling/notifying when the hydrated
      // live rows are identical to what is already cached, so a hydrate that
      // matches the seed does not trigger a redundant rebuild.
      final edgesUnchanged = mapEquals(newEdges, _edges);
      final requestsUnchanged = _requestsEqual(newRequests, _requests);
      if (edgesUnchanged && requestsUnchanged) return;

      _edges
        ..clear()
        ..addAll(newEdges);
      _requests
        ..clear()
        ..addAll(newRequests);
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  // -- Follow / unfollow ---------------------------------------------------

  /// Follows [target] optimistically. The resulting state is decided by
  /// [followStateForNewFollow]: a private account => [FollowState.requested]
  /// (server `status = 'pending'`), a public account => [FollowState.following]
  /// (server `status = 'accepted'`). Idempotent: no [notifyListeners] and no
  /// write when the edge is already in that state. Persists to `public.follows`
  /// via a guarded fire-and-forget helper.
  void follow(UserProfile target) {
    final desired = followStateForNewFollow(target);
    if (_edges[target.id] == desired) return; // idempotent: no-op
    _edges[target.id] = desired;
    notifyListeners();
    // ignore: discarded_futures
    _persistFollow(
      target.id,
      status: desired == FollowState.requested ? 'pending' : 'accepted',
    );
  }

  /// Unfollows [userId] (or cancels a pending request) optimistically.
  /// Idempotent: no [notifyListeners] and no write when there is no edge.
  /// Deletes the row from `public.follows` via a guarded helper.
  void unfollow(String userId) {
    if (_edges.remove(userId) == null) return; // idempotent: nothing to remove
    notifyListeners();
    // ignore: discarded_futures
    _persistUnfollow(userId);
  }

  // -- Accept / deny incoming follow requests ------------------------------

  /// Accepts the incoming follow request from [actorId]: removes it from the
  /// pending list and flips the server row to `status = 'accepted'`. Idempotent:
  /// no [notifyListeners] and no write when there is no such pending request.
  void acceptFollowRequest(String actorId) {
    if (!_removeRequest(actorId)) return; // idempotent: nothing pending
    notifyListeners();
    // ignore: discarded_futures
    _persistAccept(actorId);
  }

  /// Denies the incoming follow request from [actorId]: removes it from the
  /// pending list and deletes the server row. Idempotent (see
  /// [acceptFollowRequest]).
  void denyFollowRequest(String actorId) {
    if (!_removeRequest(actorId)) return; // idempotent: nothing pending
    notifyListeners();
    // ignore: discarded_futures
    _persistDeny(actorId);
  }

  /// Whether two follow-request lists represent the same pending set. Compared
  /// order-insensitively and keyed by actor id with the timestamp included, so
  /// a re-order alone is not treated as a change but a new/removed/moved
  /// request (or a shifted `createdAt`) is. Used by [load]'s notify-on-change
  /// guard alongside [mapEquals] on the edges.
  static bool _requestsEqual(List<FollowRequest> a, List<FollowRequest> b) {
    if (a.length != b.length) return false;
    final byActor = <String, DateTime>{
      for (final r in b) r.actor.id: r.createdAt,
    };
    for (final r in a) {
      final existing = byActor[r.actor.id];
      if (existing == null || existing != r.createdAt) return false;
    }
    return true;
  }

  bool _removeRequest(String actorId) {
    final before = _requests.length;
    _requests.removeWhere((r) => r.actor.id == actorId);
    return _requests.length != before;
  }

  // -- Supabase persistence (fire-and-forget, fully guarded) ---------------

  /// Reflects a follow into the `public.follows` table keyed by
  /// `(follower = auth.uid(), followee = userId)` with the given [status]
  /// ('pending' for a private target, 'accepted' for a public one). Mirrors
  /// `PostRepository._persistLike`'s insert pattern. Uses upsert so a repeated
  /// follow is a safe no-op server-side. No-op/guarded when Supabase is
  /// unavailable.
  Future<void> _persistFollow(String userId, {required String status}) async {
    try {
      final follower = supabase.auth.currentUser?.id;
      if (follower == null) return;
      await supabase.from('follows').upsert(<String, dynamic>{
        'follower': follower,
        'followee': userId,
        'status': status,
      });
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Deletes the follow edge `(follower = auth.uid(), followee = userId)` from
  /// `public.follows`. No-op/guarded when Supabase is unavailable.
  Future<void> _persistUnfollow(String userId) async {
    try {
      final follower = supabase.auth.currentUser?.id;
      if (follower == null) return;
      await supabase
          .from('follows')
          .delete()
          .eq('follower', follower)
          .eq('followee', userId);
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Flips the incoming follow row `(follower = actorId, followee = auth.uid())`
  /// to `status = 'accepted'`. No-op/guarded when Supabase is unavailable.
  Future<void> _persistAccept(String actorId) async {
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return;
      await supabase
          .from('follows')
          .update(<String, dynamic>{'status': 'accepted'})
          .eq('follower', actorId)
          .eq('followee', me);
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Deletes the incoming pending follow row
  /// `(follower = actorId, followee = auth.uid())`. No-op/guarded when Supabase
  /// is unavailable.
  Future<void> _persistDeny(String actorId) async {
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return;
      await supabase
          .from('follows')
          .delete()
          .eq('follower', actorId)
          .eq('followee', me);
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  // -- Mapping -------------------------------------------------------------

  static FollowState _stateFromStatus(String? status) {
    switch (status) {
      case 'pending':
        return FollowState.requested;
      case 'accepted':
      default:
        return FollowState.following;
    }
  }

  UserProfile _actorFromRow(Object? profiles, Object? fallbackId) {
    if (profiles is Map) {
      final p = profiles.cast<String, dynamic>();
      final username = (p['username'] as String?) ?? 'user';
      return UserProfile(
        id: p['id']?.toString() ?? fallbackId?.toString() ?? '',
        username: username,
        displayName: (p['display_name'] as String?) ?? username,
        bio: (p['bio'] as String?) ?? '',
        avatarUrl: p['avatar_url'] as String?,
        bannerUrl: p['banner_url'] as String?,
        verified: (p['verified'] as bool?) ?? false,
        verificationKind: (p['verification_kind'] as String?) ?? 'verified',
        isPrivate: (p['is_private'] as bool?) ?? false,
      );
    }
    return UserProfile(
      id: fallbackId?.toString() ?? '',
      username: 'user',
      displayName: 'User',
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }
}
