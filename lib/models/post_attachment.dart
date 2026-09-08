/// The media type of a single [PostAttachment].
enum AttachmentType { image, video }

/// An immutable, ordered media attachment on a [Post].
///
/// A post's media is modeled as an ORDERED list of [PostAttachment]s (see
/// `post.dart`), which generalizes the old single `mediaUrl`/`mediaType` slot
/// into single-image, single-video, and multi-image CAROUSEL posts, and leaves
/// room for new media kinds without reworking every consumer.
///
/// PHASE 4 SEAM: attachments are carried BY URL/reference only. There is NO
/// real device capture/upload of bytes yet; [url]/[thumbUrl] point at already
/// hosted media (the mock seed uses picsum placeholders and the compose flow
/// appends demo picsum URLs). Real gallery/camera capture + upload to the
/// storage bucket is Phase 4 and will populate these fields from device bytes.
///
/// [width]/[height]/[altText] are OPTIONAL metadata: they let the UI reserve
/// aspect-ratio space and provide accessibility text when known, but are not
/// required to render. Mirrors the immutable-model convention used across the
/// app (see `comment.dart`): `copyWith` + id-based `==`/`hashCode`.
class PostAttachment {
  const PostAttachment({
    required this.id,
    required this.postId,
    required this.position,
    required this.type,
    required this.url,
    this.thumbUrl,
    this.width,
    this.height,
    this.altText,
  });

  final String id;
  final String postId;

  /// Zero-based ordering within the post's attachment list (0 = first).
  final int position;

  final AttachmentType type;

  /// The hosted media URL. Carried by reference (see the PHASE 4 SEAM above).
  final String url;

  /// Optional lower-resolution/poster URL (e.g. a video poster frame).
  final String? thumbUrl;

  /// Optional intrinsic pixel dimensions, when known.
  final int? width;
  final int? height;

  /// Optional accessibility alt text.
  final String? altText;

  PostAttachment copyWith({
    String? id,
    String? postId,
    int? position,
    AttachmentType? type,
    String? url,
    String? thumbUrl,
    int? width,
    int? height,
    String? altText,
  }) {
    return PostAttachment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      position: position ?? this.position,
      type: type ?? this.type,
      url: url ?? this.url,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      width: width ?? this.width,
      height: height ?? this.height,
      altText: altText ?? this.altText,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PostAttachment && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
