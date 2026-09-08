import 'package:flutter/foundation.dart';

import '../supabase_config.dart';
import 'mock_data.dart';

/// Owns the viewer's SAVES/bookmarks: the set of post ids the signed-in user
/// has saved.
///
/// Server-backed and modeled on [SafetyRepository]'s block-set contract:
///
///  * a synchronous public surface ([savedIds], [isSaved], [toggleSave]) over
///    an in-memory set seeded from [MockData.savedPostIds] (EMPTY by default so
///    the existing bookmark/feed assertions never shift), so the UI + unit
///    tests (which never boot Supabase) always have state immediately;
///  * [toggleSave] updates the set optimistically, fires EXACTLY ONE
///    [notifyListeners] per real change (idempotent-safe: toggling always
///    flips, so it always notifies), and persists to `public.saves` via a
///    guarded fire-and-forget helper that never throws into the UI; and
///  * a fire-and-forget, fully guarded [load] that hydrates the save set from
///    `public.saves` for the signed-in user with a `setEquals` change-guard so
///    it only notifies when live rows replace the seed (and is a NO-OP,
///    notifying zero times, when Supabase is unavailable/unauthenticated).
///
/// SAVES persist keyed by `(user_id = auth.uid(), post_id)`, mirroring
/// `PostRepository._persistLike`'s insert/delete on the `likes` table. The
/// server owns nothing denormalized here — a save is a private, per-user row.
class SaveRepository extends ChangeNotifier {
  SaveRepository() : _saved = Set<String>.of(MockData.savedPostIds()) {
    // Hydrate from Supabase in the background. Guarded so it is a no-op when
    // Supabase is unavailable (tests / offline), leaving the mock seed intact.
    // ignore: discarded_futures
    load();
  }

  /// Shared singleton for the app.
  static final SaveRepository instance = SaveRepository();

  final Set<String> _saved;

  /// The ids of posts the viewer has saved (unmodifiable view).
  Set<String> get savedIds => Set<String>.unmodifiable(_saved);

  /// Whether [postId] is currently saved by the viewer.
  bool isSaved(String postId) => _saved.contains(postId);

  /// Toggles the saved state for [postId] optimistically.
  ///
  /// Always flips the state, so it always fires exactly one [notifyListeners];
  /// it is idempotent-SAFE in that a save that is already present is simply
  /// removed (and vice versa) with no error. Persists the insert/delete to
  /// `public.saves` via a guarded fire-and-forget helper.
  void toggleSave(String postId) {
    final nowSaved = !_saved.contains(postId);
    if (nowSaved) {
      _saved.add(postId);
    } else {
      _saved.remove(postId);
    }
    notifyListeners();
    // ignore: discarded_futures
    _persistSave(postId, saved: nowSaved);
  }

  /// Hydrates [_saved] from the Supabase `public.saves` table for the signed-in
  /// user. Fire-and-forget; fully guarded so it never throws (e.g. when
  /// Supabase is uninitialized under tests) and only notifies when it actually
  /// replaces the seed with live rows.
  Future<void> load() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return; // keep the mock seed as a graceful fallback
      final rows = await supabase
          .from('saves')
          .select('post_id')
          .eq('user_id', userId);
      final data = (rows as List).cast<Map<String, dynamic>>();
      final ids = data
          .map((r) => r['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (setEquals(ids, _saved)) return; // nothing changed, no notify
      _saved
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  /// Reflects a save/unsave into the `public.saves` table, keyed by
  /// `(user_id = auth.uid(), post_id)`. Mirrors `PostRepository._persistLike`'s
  /// insert/delete pattern. No-op/guarded when Supabase is unavailable.
  Future<void> _persistSave(String postId, {required bool saved}) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      if (saved) {
        await supabase.from('saves').insert(<String, dynamic>{
          'user_id': userId,
          'post_id': postId,
        });
      } else {
        await supabase
            .from('saves')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);
      }
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }
}
