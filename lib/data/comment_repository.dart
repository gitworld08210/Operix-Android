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
      : _comments = MockData.comments() {
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

  /// Comments for [postId], newest-first (threaded replies keep their relative
  /// order but the list is a flat newest-first view; the UI groups replies by
  /// [Comment.parentId]). Returns an unmodifiable view; an unknown post id
  /// yields an empty list.
  List<Comment> commentsFor(String postId) {
    final list = _comments.where((c) => c.postId == postId).toList()
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
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
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
