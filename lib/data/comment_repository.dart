import 'package:flutter/foundation.dart';

import '../models/comment.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import '../utils/ids.dart';
import 'mock_data.dart';
import 'profile_repository.dart';

/// Thrown by [CommentRepository.addComment] when the client-side content
/// validation fails (empty or over the length limit). The server `comments`
/// check constraint (`char_length(content) between 1 and 2000`) is the true
/// source of truth; this mirrors it early so the UI can give immediate
/// feedback without a round-trip.
class CommentValidationError implements Exception {
  const CommentValidationError(this.message);
  final String message;

  @override
  String toString() => 'CommentValidationError: $message';
}

/// Store for post comments, backed by Supabase with a graceful [MockData]
/// fallback.
///
/// Follows the same contract as [PostRepository]/[ProfileRepository]:
///
///  * a synchronous public surface ([commentsFor], [addComment]) over an
///    in-memory `_comments` cache seeded from [MockData.comments] so the UI
///    and unit tests (which never boot Supabase) always have data immediately;
///  * a fire-and-forget, fully guarded [load] that hydrates the cache from the
///    Supabase `comments` table and only notifies when live rows replace the
///    seed; and
///  * mutations that update the cache optimistically, fire exactly one
///    [notifyListeners], and persist via a separate guarded helper that never
///    throws into the UI.
class CommentRepository extends ChangeNotifier {
  CommentRepository()
      : _comments = MockData.comments(),
        _likedCommentIds = Set<String>.of(MockData.likedCommentIds()) {
    // Hydrate from Supabase in the background. Guarded so it is a no-op when
    // Supabase is unavailable (tests / offline), leaving the mock seed intact.
    // ignore: discarded_futures
    load();
  }

  /// Shared singleton for the app.
  static final CommentRepository instance = CommentRepository();

  /// Maximum content length, matching the server check constraint
  /// (`char_length(content) between 1 and 2000`).
  static const int maxContentLength = 2000;

  final List<Comment> _comments;

  /// The viewer's own liked comment ids. Seeded from
  /// [MockData.likedCommentIds] (EMPTY by default so the seeded like counts are
  /// untouched) and hydrated from `public.comment_likes` by [load]. This is the
  /// per-viewer toggle state; the aggregate `comments.like_count` is server
  /// owned (see [toggleCommentLike] / [_persistCommentLike]).
  final Set<String> _likedCommentIds;

  /// Whether the viewer has liked the comment [commentId].
  bool isCommentLiked(String commentId) => _likedCommentIds.contains(commentId);

  /// Comments for [postId], newest-first (threaded replies keep their relative
  /// order but the list is a flat newest-first view; the UI groups replies by
  /// [Comment.parentId]). Returns an unmodifiable view; an unknown post id
  /// yields an empty list.
  List<Comment> commentsFor(String postId) {
    final list = _comments.where((c) => c.postId == postId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<Comment>.unmodifiable(list);
  }

  /// All comments authored by [authorId], newest-first. Used by the data-export
  /// scaffolding to collect the current user's own comments. Returns an
  /// unmodifiable view; an unknown author yields an empty list.
  List<Comment> allByAuthor(String authorId) {
    final list = _comments.where((c) => c.author.id == authorId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<Comment>.unmodifiable(list);
  }

  /// Hydrates [_comments] from the Supabase `comments` table (with the joined
  /// author profile). Fire-and-forget; fully guarded so it never throws (e.g.
  /// when Supabase is uninitialized under tests) and only notifies on live
  /// rows.
  Future<void> load() async {
    try {
      final rows = await supabase
          .from('comments')
          .select('*, profiles(*)')
          .order('created_at', ascending: false);
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return; // keep the mock seed as a graceful fallback
      final mapped = data.map(_commentFromRow).toList();
      _comments
        ..clear()
        ..addAll(mapped);
      // Hydrate the viewer's own comment likes so tapped hearts render as
      // liked after a load. Guarded with a setEquals change-check so it only
      // notifies when the viewer's like set actually changes.
      await _hydrateViewerCommentLikes();
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  /// Reads the signed-in viewer's own `comment_likes` rows into
  /// [_likedCommentIds]. The per-viewer liked flag is NOT denormalized onto
  /// `comments` (it derives from the join table), so without this a comment the
  /// viewer already liked would render un-liked after a [load]. Fully guarded
  /// and a no-op (no throw, no notify) when Supabase is unavailable or the
  /// viewer is unauthenticated. The caller ([load]) fires the single notify;
  /// this method only mutates the set when it actually differs (setEquals
  /// change-guard) so an offline load stays a zero-notification no-op.
  Future<void> _hydrateViewerCommentLikes() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await supabase
        .from('comment_likes')
        .select('comment_id')
        .eq('user_id', userId);
    final liked = (rows as List)
        .map((r) => (r as Map)['comment_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (setEquals(_likedCommentIds, liked)) return;
    _likedCommentIds
      ..clear()
      ..addAll(liked);
  }

  /// Adds a comment to [postId] optimistically and persists it.
  ///
  /// Validates the content client-side (non-empty after trimming, and no
  /// longer than [maxContentLength]); the server check constraint remains the
  /// authoritative gate. Throws [CommentValidationError] on invalid input so
  /// callers can surface the reason. On success the new comment is inserted at
  /// the front of the cache and a single [notifyListeners] fires.
  Comment addComment(String postId, String content, {String? parentId}) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw const CommentValidationError('Comment cannot be empty.');
    }
    if (trimmed.length > maxContentLength) {
      throw const CommentValidationError(
        'Comment cannot exceed $maxContentLength characters.',
      );
    }

    final comment = Comment(
      // A client-generated UUID so the in-memory id equals the persisted DB
      // row id (the comments.id uuid column accepts it). See utils/ids.dart.
      id: newUuidV4(),
      postId: postId,
      author: ProfileRepository.instance.currentUser,
      parentId: parentId,
      content: trimmed,
      createdAt: DateTime.now(),
    );

    _comments.insert(0, comment);
    notifyListeners();
    // ignore: discarded_futures
    _persistComment(comment);
    return comment;
  }

  /// Toggles the viewer's like on [commentId] optimistically. Returns the
  /// updated [Comment], or null for an unknown id.
  ///
  /// Mirrors [PostRepository.toggleLike]: it flips the per-viewer liked flag
  /// and moves the DISPLAY [Comment.likeCount] by +/-1, firing exactly one
  /// [notifyListeners]. The `comments.like_count` aggregate is SERVER OWNED
  /// (recomputed from `public.comment_likes` by the `sync_comment_like_count`
  /// trigger in migration 0008); the client NEVER writes it. The optimistic
  /// +/-1 here is therefore a display-only estimate that the next [load]
  /// reconciles against the authoritative count. Persistence is a separate
  /// guarded fire-and-forget insert/delete on `public.comment_likes` that
  /// never throws into the UI.
  Comment? toggleCommentLike(String commentId) {
    final i = _comments.indexWhere((c) => c.id == commentId);
    if (i < 0) return null;
    final current = _comments[i];
    final nowLiked = !_likedCommentIds.contains(commentId);
    if (nowLiked) {
      _likedCommentIds.add(commentId);
    } else {
      _likedCommentIds.remove(commentId);
    }
    final updated = current.copyWith(
      likeCount: current.likeCount + (nowLiked ? 1 : -1),
    );
    _comments[i] = updated;
    notifyListeners();
    // ignore: discarded_futures
    _persistCommentLike(commentId, liked: nowLiked);
    return updated;
  }

  // -- Supabase persistence (fire-and-forget, fully guarded) ---------------

  /// Inserts a new comment into the Supabase `comments` table.
  ///
  /// The `id` is sent explicitly (not left to the DB default) so the persisted
  /// row's primary key equals the in-memory [Comment.id]. The server owns
  /// `posts.reply_count` (recomputed by the `sync_post_reply_count` trigger)
  /// and `comments.like_count`, so the client never writes those. Guarded so
  /// it never throws into the UI when Supabase is unavailable.
  Future<void> _persistComment(Comment comment) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await supabase.from('comments').insert(<String, dynamic>{
        'id': comment.id,
        'post_id': comment.postId,
        'owner': userId,
        'parent_id': comment.parentId,
        'content': comment.content,
      });
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory comment stands.
    }
  }

  /// Reflects a comment-like toggle into the `public.comment_likes` join table
  /// only, keyed by `(user_id = auth.uid(), comment_id)`.
  ///
  /// The aggregate `comments.like_count` is owned by the database: the
  /// `sync_comment_like_count` trigger (migration 0008) recomputes it from
  /// `count(*)` over `comment_likes` on every insert/delete. The client
  /// deliberately does NOT write that count here (which would race with
  /// concurrent clients); it only records the viewer's like/un-like and lets
  /// the server reconcile. The optimistic +/-1 applied in [toggleCommentLike]
  /// is a display-only estimate until the next [load]. Mirrors
  /// `PostRepository._persistLike`/`_persistReaction`; guarded/no-op when
  /// Supabase is unavailable.
  Future<void> _persistCommentLike(String commentId, {required bool liked}) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      if (liked) {
        await supabase.from('comment_likes').insert(<String, dynamic>{
          'user_id': userId,
          'comment_id': commentId,
        });
      } else {
        await supabase
            .from('comment_likes')
            .delete()
            .eq('user_id', userId)
            .eq('comment_id', commentId);
      }
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  // -- Mapping -------------------------------------------------------------

  /// Maps a `comments` row (with a joined `profiles(*)` object) to a [Comment].
  Comment _commentFromRow(Map<String, dynamic> row) {
    return Comment(
      id: row['id']?.toString() ?? '',
      postId: row['post_id']?.toString() ?? '',
      author: _authorFromRow(row['profiles']),
      parentId: row['parent_id']?.toString(),
      content: (row['content'] as String?) ?? '',
      likeCount: _asInt(row['like_count']),
      createdAt: _parseDate(row['created_at']),
    );
  }

  /// Builds a [UserProfile] from the joined `profiles` object. Falls back to a
  /// minimal placeholder when the join is absent.
  UserProfile _authorFromRow(Object? profiles) {
    if (profiles is Map) {
      final p = profiles.cast<String, dynamic>();
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
