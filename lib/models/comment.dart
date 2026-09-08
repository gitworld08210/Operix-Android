import 'user_profile.dart';

/// An immutable comment (reply) on a [Post].
///
/// Mirrors the shape of the Supabase `comments` table added in migration
/// `0002_authz_and_core_tables.sql` (id, post_id, owner, parent_id nullable,
/// content, like_count, created_at). Threaded replies are supported via the
/// optional [parentId] (null for a top-level comment).
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    this.parentId,
    required this.content,
    this.likeCount = 0,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final UserProfile author;

  /// Id of the parent comment when this is a threaded reply, else null.
  final String? parentId;

  final String content;

  /// Server-owned like counter (denormalized). Display-only on the client.
  final int likeCount;

  final DateTime createdAt;

  /// Whether this comment is a top-level comment (not a threaded reply).
  bool get isTopLevel => parentId == null;

  Comment copyWith({
    String? id,
    String? postId,
    UserProfile? author,
    String? parentId,
    String? content,
    int? likeCount,
    DateTime? createdAt,
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      author: author ?? this.author,
      parentId: parentId ?? this.parentId,
      content: content ?? this.content,
      likeCount: likeCount ?? this.likeCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Comment && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
