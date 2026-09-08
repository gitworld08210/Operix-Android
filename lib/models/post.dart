import 'post_attachment.dart';
import 'user_profile.dart';

/// The kind of media attached to a [Post].
///
/// Retained for the legacy single-media compatibility shim (see [Post.mediaType]
/// / [Post.mediaUrl] / [Post.hasMedia]). New code should read [Post.kind] +
/// [Post.attachments] instead.
enum MediaType { none, image, video }

/// The polymorphic content discriminator for a [Post].
///
/// A post is one of: a [text] post (zero attachments), a single [image], a
/// single [video], or a multi-image [carousel] (more than one attachment).
/// [Post.kind] and [Post.attachments] are kept consistent by [deriveKind]: the
/// constructors/mappers always derive [kind] from the attachment list so the
/// two can never disagree.
enum PostKind { text, image, carousel, video }

/// Derives the [PostKind] from an ordered [attachments] list.
///
/// Contract (the single source of truth so `kind` and `attachments` never
/// drift):
///   * 0 attachments        => [PostKind.text]
///   * exactly 1 image      => [PostKind.image]
///   * exactly 1 video      => [PostKind.video]
///   * more than 1          => [PostKind.carousel]
PostKind deriveKind(List<PostAttachment> attachments) {
  if (attachments.isEmpty) return PostKind.text;
  if (attachments.length > 1) return PostKind.carousel;
  return attachments.first.type == AttachmentType.video
      ? PostKind.video
      : PostKind.image;
}

/// An immutable feed post.
///
/// Content is modeled polymorphically: a [kind] discriminator plus an ordered
/// list of [attachments] (see [PostAttachment]) supports text, single-image,
/// single-video, and multi-image carousel posts. [kind] is ALWAYS derived from
/// [attachments] via [deriveKind] (in the constructor and in `copyWith`) so the
/// two can never disagree.
///
/// COMPATIBILITY SHIM: the legacy [mediaUrl]/[mediaType]/[hasMedia] getters are
/// preserved and computed from `attachments.first`, so existing consumers and
/// tests that read a single media slot keep compiling and behave identically
/// for single-media posts. New code should prefer [kind] + [attachments].
class Post {
  Post({
    required this.id,
    required this.author,
    required this.content,
    String? mediaUrl,
    MediaType mediaType = MediaType.none,
    List<PostAttachment>? attachments,
    required this.createdAt,
    this.replyCount = 0,
    this.repostCount = 0,
    this.likeCount = 0,
    this.viewCount = 0,
    this.liked = false,
    this.reposted = false,
    this.bookmarked = false,
  })  : attachments = attachments ??
            _legacyAttachments(id, mediaUrl, mediaType),
        kind = deriveKind(
          attachments ?? _legacyAttachments(id, mediaUrl, mediaType),
        );

  /// Builds a single-attachment list from the legacy `mediaUrl`/`mediaType`
  /// pair when no explicit [attachments] list is supplied. Returns an empty
  /// list for a text post (no media). This is what lets old call sites that
  /// only pass `mediaUrl`/`mediaType` (e.g. seeds, tests, the legacy row
  /// mapper fallback) map cleanly onto the attachments model.
  static List<PostAttachment> _legacyAttachments(
    String postId,
    String? mediaUrl,
    MediaType mediaType,
  ) {
    if (mediaUrl == null || mediaType == MediaType.none) {
      return const <PostAttachment>[];
    }
    return <PostAttachment>[
      PostAttachment(
        id: '${postId}_a0',
        postId: postId,
        position: 0,
        type: mediaType == MediaType.video
            ? AttachmentType.video
            : AttachmentType.image,
        url: mediaUrl,
      ),
    ];
  }

  final String id;
  final UserProfile author;
  final String content;

  /// The polymorphic content discriminator, always consistent with
  /// [attachments] (derived via [deriveKind]).
  final PostKind kind;

  /// The ordered media attachments (empty for a text post).
  final List<PostAttachment> attachments;

  final DateTime createdAt;
  final int replyCount;
  final int repostCount;
  final int likeCount;
  final int viewCount;
  final bool liked;
  final bool reposted;
  final bool bookmarked;

  // -- Legacy single-media compatibility shim (over attachments.first) -----

  /// Legacy shim: the first attachment's URL, or null for a text post.
  String? get mediaUrl =>
      attachments.isEmpty ? null : attachments.first.url;

  /// Legacy shim: the first attachment's type mapped to [MediaType], or
  /// [MediaType.none] for a text post.
  MediaType get mediaType {
    if (attachments.isEmpty) return MediaType.none;
    return attachments.first.type == AttachmentType.video
        ? MediaType.video
        : MediaType.image;
  }

  /// Legacy shim: whether this post has any media block to render.
  bool get hasMedia => attachments.isNotEmpty;

  Post copyWith({
    String? id,
    UserProfile? author,
    String? content,
    List<PostAttachment>? attachments,
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
      // Passing attachments keeps kind consistent via deriveKind in the ctor.
      attachments: attachments ?? this.attachments,
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
