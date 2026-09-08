import 'user_profile.dart';

/// The kind of media attached to a [Post].
enum MediaType { none, image, video }

/// An immutable feed post.
class Post {
  const Post({
    required this.id,
    required this.author,
    required this.content,
    this.mediaUrl,
    this.mediaType = MediaType.none,
    required this.createdAt,
    this.replyCount = 0,
    this.repostCount = 0,
    this.likeCount = 0,
    this.viewCount = 0,
    this.liked = false,
    this.reposted = false,
    this.bookmarked = false,
  });

  final String id;
  final UserProfile author;
  final String content;
  final String? mediaUrl;
  final MediaType mediaType;
  final DateTime createdAt;
  final int replyCount;
  final int repostCount;
  final int likeCount;
  final int viewCount;
  final bool liked;
  final bool reposted;
  final bool bookmarked;

  bool get hasMedia => mediaType != MediaType.none && mediaUrl != null;

  Post copyWith({
    String? id,
    UserProfile? author,
    String? content,
    String? mediaUrl,
    MediaType? mediaType,
    DateTime? createdAt,
    int? replyCount,
    int? repostCount,
    int? likeCount,
    int? viewCount,
    bool? liked,
    bool? reposted,
    bool? bookmarked,
  }) {
    return Post(
      id: id ?? this.id,
      author: author ?? this.author,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      createdAt: createdAt ?? this.createdAt,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      likeCount: likeCount ?? this.likeCount,
      viewCount: viewCount ?? this.viewCount,
      liked: liked ?? this.liked,
      reposted: reposted ?? this.reposted,
      bookmarked: bookmarked ?? this.bookmarked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Post && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
