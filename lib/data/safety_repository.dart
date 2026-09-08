import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../supabase_config.dart';
import 'mock_data.dart';

/// Thrown by [SafetyRepository.report] when the client-side reason validation
/// fails (empty or over the length limit). The server `reports` check
/// constraint (`char_length(reason) between 1 and 500`) is the true source of
/// truth; this mirrors it early so the UI can give immediate feedback without a
/// round-trip. Mirrors [CommentValidationError] in `comment_repository.dart`.
class ReportValidationError implements Exception {
  const ReportValidationError(this.message);
  final String message;

  @override
  String toString() => 'ReportValidationError: $message';
}

/// Removes posts whose author is blocked or muted, preserving input order.
///
/// PURE + independently unit-tested: it takes the (already-ranked) [posts] and
/// the current [blocked]/[muted] id sets and returns a filtered list in the
/// same relative order. It is IDENTITY when both sets are empty — a critical
/// invariant so an empty [SafetyRepository] never shifts the existing feed
/// contents/ordering the repository tests assert. Exposed at top-level so
/// [PostRepository] and the tests can share the exact same logic.
List<Post> filterHidden(
  List<Post> posts, {
  required Set<String> blocked,
  required Set<String> muted,
}) {
  if (blocked.isEmpty && muted.isEmpty) return posts;
  return posts
      .where((p) => !blocked.contains(p.author.id) && !muted.contains(p.author.id))
      .toList();
}

/// Owns the viewer's SAFETY state: the set of accounts they have blocked, the
/// set they have muted, and abuse reports they submit.
///
/// Follows the same contract as the other repositories (see [PostRepository]/
/// [CommentRepository]/[ProfileRepository]):
///
///  * a synchronous public surface ([blockedIds], [mutedIds], [isBlocked],
///    [isMuted], and the [block]/[unblock]/[mute]/[unmute] mutators) over
///    in-memory sets seeded from [MockData] so the UI and unit tests (which
///    never boot Supabase) always have state immediately;
///  * mutations that update the set optimistically, fire EXACTLY ONE
///    [notifyListeners] only on a real change (idempotent — no notify when the
///    account is already in the desired state), and persist BLOCKS via a
///    separate guarded helper that never throws into the UI; and
///  * a fire-and-forget, fully guarded [load] that hydrates the block set from
///    the Supabase `public.blocks` table for the signed-in user and only
///    notifies when live rows replace the seed.
///
/// BLOCKS are server-backed: they persist to the FEAT-002 `public.blocks` join
/// table keyed by `(blocker = auth.uid(), blocked = userId)`, mirroring
/// `PostRepository._persistLike`'s insert/delete on the `likes` table. The
/// server owns the TRUE enforcement: the SECURITY DEFINER `can_view_profile`
/// helper (0002) makes a blocked author's profile/posts invisible on the next
/// [PostRepository.load]. Until then the client applies an OPTIMISTIC local
/// filter (see [filterHidden]) so blocked authors disappear from the feed
/// immediately; the server reconciles on the next load.
///
/// MUTE is CLIENT-AUTHORITATIVE this phase: there is deliberately no server
/// mute table (a product differentiator — a lightweight, private "hide from my
/// feed" that never leaves the device). It is in-memory only, hides an author's
/// posts locally via the same [filterHidden] path, and is NOT persisted.
class SafetyRepository extends ChangeNotifier {
  SafetyRepository()
      : _blocked = Set<String>.of(MockData.blockedUserIds()),
        _muted = Set<String>.of(MockData.mutedUserIds()) {
    // Hydrate the block set from Supabase in the background. Guarded so it is a
    // no-op when Supabase is unavailable (tests / offline), leaving the mock
    // seed intact.
    // ignore: discarded_futures
    load();
  }

  /// Shared singleton for the app.
  static final SafetyRepository instance = SafetyRepository();

  /// Maximum report reason length, matching the server check constraint
  /// (`char_length(reason) between 1 and 500`).
  static const int maxReasonLength = 500;

  final Set<String> _blocked;
  final Set<String> _muted;

  /// The ids of accounts the viewer has blocked (unmodifiable view).
  Set<String> get blockedIds => Set<String>.unmodifiable(_blocked);

  /// The ids of accounts the viewer has muted (unmodifiable view).
  Set<String> get mutedIds => Set<String>.unmodifiable(_muted);

  /// Whether [userId] is blocked by the viewer.
  bool isBlocked(String userId) => _blocked.contains(userId);

  /// Whether [userId] is muted by the viewer.
  bool isMuted(String userId) => _muted.contains(userId);

  /// Hydrates [_blocked] from the Supabase `public.blocks` table for the
  /// signed-in user. Fire-and-forget; fully guarded so it never throws (e.g.
  /// when Supabase is uninitialized under tests) and only notifies when it
  /// actually replaces the seed with live rows.
  Future<void> load() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return; // keep the mock seed as a graceful fallback
      final rows = await supabase
          .from('blocks')
          .select('blocked')
          .eq('blocker', userId);
      final data = (rows as List).cast<Map<String, dynamic>>();
      final ids = data
          .map((r) => r['blocked']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (setEquals(ids, _blocked)) return; // nothing changed, no notify
      _blocked
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  // -- Block / unblock -----------------------------------------------------

  /// Blocks [userId] optimistically. Idempotent: no [notifyListeners] and no
  /// write when the account is already blocked. Persists to `public.blocks`
  /// via a guarded fire-and-forget helper.
  void block(String userId) {
    if (_blocked.contains(userId)) return; // idempotent: no-op
    _blocked.add(userId);
    notifyListeners();
    // ignore: discarded_futures
    _persistBlock(userId, blocked: true);
  }

  /// Unblocks [userId] optimistically. Idempotent: no [notifyListeners] and no
  /// write when the account is not currently blocked.
  void unblock(String userId) {
    if (!_blocked.remove(userId)) return; // idempotent: nothing to remove
    notifyListeners();
    // ignore: discarded_futures
    _persistBlock(userId, blocked: false);
  }

  // -- Mute / unmute (client-authoritative, in-memory only) ----------------

  /// Mutes [userId] optimistically. Idempotent (see [block]). Mute is
  /// in-memory only this phase (no server table); nothing is persisted.
  void mute(String userId) {
    if (_muted.contains(userId)) return; // idempotent: no-op
    _muted.add(userId);
    notifyListeners();
  }

  /// Unmutes [userId] optimistically. Idempotent (see [unblock]).
  void unmute(String userId) {
    if (!_muted.remove(userId)) return; // idempotent: nothing to remove
    notifyListeners();
  }

  // -- Report --------------------------------------------------------------

  /// Submits an abuse [reason] against a target (a post/profile/comment).
  ///
  /// Validates [reason] client-side (non-empty after trimming, no longer than
  /// [maxReasonLength]); the server check constraint remains the authoritative
  /// gate. Throws [ReportValidationError] on invalid input so callers can
  /// surface the reason. On valid input it guarded-inserts into
  /// `public.reports` (fire-and-forget semantics: the insert never throws into
  /// the UI, so an offline submit still resolves and the UI shows an optimistic
  /// confirmation). No local cache is kept — reports are write-only from the
  /// client, read-restricted to their author server-side.
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const ReportValidationError('Reason cannot be empty.');
    }
    if (trimmed.length > maxReasonLength) {
      throw const ReportValidationError(
        'Reason cannot exceed $maxReasonLength characters.',
      );
    }
    await _persistReport(
      targetType: targetType,
      targetId: targetId,
      reason: trimmed,
    );
  }

  // -- Supabase persistence (fire-and-forget, fully guarded) ---------------

  /// Reflects a block/unblock into the `public.blocks` join table only, keyed
  /// by `(blocker = auth.uid(), blocked = userId)`. Mirrors
  /// `PostRepository._persistLike`'s insert/delete pattern on the `likes`
  /// table. The server owns the visibility enforcement (`can_view_profile`);
  /// the client only records the block row and lets the server reconcile the
  /// feed on the next load. No-op/guarded when Supabase is unavailable.
  Future<void> _persistBlock(String userId, {required bool blocked}) async {
    try {
      final blocker = supabase.auth.currentUser?.id;
      if (blocker == null) return;
      if (blocked) {
        await supabase.from('blocks').insert(<String, dynamic>{
          'blocker': blocker,
          'blocked': userId,
        });
      } else {
        await supabase
            .from('blocks')
            .delete()
            .eq('blocker', blocker)
            .eq('blocked', userId);
      }
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Inserts a report into the `public.reports` table. The `reporter` is the
  /// signed-in user (enforced again by the `reports_insert_own` RLS policy).
  /// Guarded so it never throws into the UI when Supabase is unavailable; an
  /// offline submit therefore resolves without error and the UI confirms
  /// optimistically (documented on [report]).
  Future<void> _persistReport({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    try {
      final reporter = supabase.auth.currentUser?.id;
      if (reporter == null) return;
      await supabase.from('reports').insert(<String, dynamic>{
        'reporter': reporter,
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
      });
    } catch (_) {
      // Ignore persistence failures; the UI has already confirmed optimistically.
    }
  }
}
