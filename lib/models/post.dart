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

/// A typed reaction a viewer can leave on a [Post].
///
/// Generalizes the single like into six affect types. [like] is special: it is
/// the compatibility bridge to the legacy `liked`/`likeCount` surface (see
/// [Post.liked] and the like-implies-liked rule documented there). The server
/// owns the per-type counts via a trigger on `public.reactions` (see migration
/// `0007_relations.sql`); the client never writes them.
enum ReactionType { like, love, laugh, wow, sad, angry }

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
///
/// REACTIONS: a post carries a per-type [reactionCounts] map plus the viewer's
/// own [myReaction] (null when the viewer has not reacted). These GENERALIZE
/// the single like WITHOUT removing [likeCount]: the server still owns the
/// denormalized aggregate like counter (see `sync_post_reaction_like_count` in
/// `0007_relations.sql`), so [likeCount] stays authoritative for the total like
/// count. The legacy [liked] flag is a COMPATIBILITY VIEW over [myReaction]
/// under the LIKE-IMPLIES-LIKED rule: `liked == (myReaction == ReactionType.like)`.
/// Construct a post with `liked: true` and it seeds `myReaction = like`; pass a
/// non-like [myReaction] and [liked] reads false.
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
    bool liked = false,
    ReactionType? myReaction,
    this.reactionCounts = const <ReactionType, int>{},
    this.reposted = false,
    this.bookmarked = false,
    this.location,
    this.lat,
    this.lng,
    this.quotedPostId,
    this.quotedPost,
  })  : attachments = attachments ??
            _legacyAttachments(id, mediaUrl, mediaType),
        kind = deriveKind(
          attachments ?? _legacyAttachments(id, mediaUrl, mediaType),
        ),
        // LIKE-IMPLIES-LIKED: a `liked: true` with no explicit reaction seeds a
        // `like`; an explicit myReaction always wins so callers can set love /
        // laugh / etc. directly.
        myReaction =
            myReaction ?? (liked ? ReactionType.like : null);

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

  /// The server-owned aggregate LIKE count. Owned by a database trigger, not
  /// the client (see [Post] doc + `0007_relations.sql`). Reactions other than
  /// `like` are tallied separately in [reactionCounts].
  final int likeCount;
  final int viewCount;

  /// The viewer's own reaction, or null when they have not reacted.
  final ReactionType? myReaction;

  /// The server-owned per-type reaction counts (empty by default). Keys are
  /// only present for types with a non-zero count. The client never writes
  /// these; a trigger maintains them.
  final Map<ReactionType, int> reactionCounts;

  final bool reposted;
  final bool bookmarked;

  /// Optional free-text location tag for the post (Phase 3 is free text; a real
  /// place-picker/geocoder is a Phase 4/5 seam — see `compose_screen.dart`).
  final String? location;

  /// Optional coordinates for the [location] (populated by a future geocoder).
  final double? lat;
  final double? lng;

  /// QUOTE-POST reference (durable FK): the id of the post this post quotes, or
  /// null for a normal post. Persisted as `posts.quoted_post_id` (a nullable
  /// self-referencing FK, ON DELETE SET NULL — see migration
  /// `0010_quote_posts.sql`). A quote-post is ORTHOGONAL to media kind: you can
  /// quote with a text body or with media, so [kind]/[attachments] are
  /// unaffected by quoting.
  final String? quotedPostId;

  /// QUOTE-POST embed (hydrated convenience): the quoted [Post] itself, for
  /// rendering the embedded card. NULLABLE and NOT part of ==/hashCode (which
  /// stay id-based). This MAY be null even when [quotedPostId] is set — e.g. the
  /// quoted post is not in cache or the viewer cannot view its author (the
  /// existing `posts_select_viewable` RLS policy simply yields a null embed).
  /// Only ever hydrated ONE LEVEL deep: a quoted post's own [quotedPost] is
  /// always null (no unbounded nesting).
  final Post? quotedPost;

  /// Legacy compatibility VIEW: whether the viewer has LIKED this post.
  ///
  /// Under the LIKE-IMPLIES-LIKED rule this is true exactly when the viewer's
  /// [myReaction] is [ReactionType.like]. A non-like reaction (love/laugh/…)
  /// therefore reads `liked == false`, matching the legacy single-like surface
  /// the like button + existing tests rely on.
  bool get liked => myReaction == ReactionType.like;

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
    ReactionType? myReaction,
    bool clearMyReaction = false,
    Map<ReactionType, int>? reactionCounts,
    bool? reposted,
    bool? bookmarked,
    String? location,
    double? lat,
    double? lng,
    String? quotedPostId,
    bool clearQuotedPostId = false,
    Post? quotedPost,
    bool clearQuotedPost = false,
  }) {
    // Resolve the viewer's reaction, in precedence order:
    //   1. `clearMyReaction: true` forces it to null (needed because a null
    //      `myReaction` arg is indistinguishable from "unchanged");
    //   2. an explicit `myReaction` wins — this is how a caller sets a NON-LIKE
    //      reaction (love/laugh/…), which reads `liked == false` on its own, so
    //      no separate `liked: false` is required to "lower" liked;
    //   3. else a `liked` flag maps to like/none under LIKE-IMPLIES-LIKED
    //      (`liked: false` clears any reaction; `liked: true` sets `like`);
    //   4. else carry the current reaction unchanged.
    // NOTE: to switch to a non-like reaction, pass that reaction via
    // `myReaction:` (step 2) — passing `liked: false` alone clears the reaction
    // entirely (step 3). The two are deliberately separate so `clearReaction`
    // (clearMyReaction) and `react` (myReaction) each express intent exactly.
    final ReactionType? resolvedReaction = clearMyReaction
        ? null
        : myReaction ??
            (liked != null
                ? (liked ? ReactionType.like : null)
                : this.myReaction);
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
      myReaction: resolvedReaction,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      reposted: reposted ?? this.reposted,
      bookmarked: bookmarked ?? this.bookmarked,
      location: location ?? this.location,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      // Escape hatches mirror `clearMyReaction`: a null `quotedPostId`/
      // `quotedPost` arg is indistinguishable from "unchanged", so an explicit
      // `clearQuotedPostId`/`clearQuotedPost` is required to null a set value.
      quotedPostId:
          clearQuotedPostId ? null : (quotedPostId ?? this.quotedPostId),
      quotedPost: clearQuotedPost ? null : (quotedPost ?? this.quotedPost),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Post && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
