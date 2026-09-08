import 'user_profile.dart';

/// The kind of media a [Story] carries.
///
/// PHASE 4 SEAM: real device capture/upload is a later phase. This phase the
/// media is carried BY URL/reference only (a `media_url` pointing at an already
/// hosted image/clip, e.g. a Supabase Storage object or a placeholder). The
/// enum is deliberately narrow (image | video) to mirror the `media_type` check
/// constraint on the `public.stories` table (migration 0006).
enum StoryMediaType { image, video }

/// An immutable, 24h-ephemeral story.
///
/// Mirrors the shape of the Supabase `public.stories` table added in migration
/// `0006_stories.sql` (id, owner, media_url, media_type, created_at,
/// expires_at). A story carries its media BY URL/reference ([mediaUrl]); real
/// on-device capture/upload is a Phase 4 concern (see [StoryMediaType]).
///
/// EPHEMERALITY (24h TTL contract): a story is only "active" while
/// [isActive] is true, i.e. while now is before [expiresAt]. On the client this
/// filter is applied by [StoryRepository]; the SERVER must independently enforce
/// expiry (an RLS `expires_at > now()` predicate plus a scheduled sweep of
/// expired rows). Until that server enforcement is verified against a live
/// Supabase project it is a documented ENVIRONMENT RISK — the client filter is
/// a UX mirror, not the true gate.
///
/// [seen] is the viewer-local "have I watched this" flag; it is
/// client-authoritative this phase and (later) reconciled against the
/// `public.story_views` table.
class Story {
  const Story({
    required this.id,
    required this.author,
    required this.mediaUrl,
    this.type = StoryMediaType.image,
    required this.createdAt,
    required this.expiresAt,
    this.seen = false,
  });

  /// Builds an ephemeral story whose [expiresAt] is [createdAt] + [ttl].
  ///
  /// The default [ttl] is the 24h contract. Use this to construct stories
  /// without hand-computing the expiry so the invariant
  /// `expiresAt == createdAt + ttl` always holds.
  factory Story.ephemeral({
    required String id,
    required UserProfile author,
    required String mediaUrl,
    StoryMediaType type = StoryMediaType.image,
    required DateTime createdAt,
    bool seen = false,
    Duration ttl = const Duration(hours: 24),
  }) {
    return Story(
      id: id,
      author: author,
      mediaUrl: mediaUrl,
      type: type,
      createdAt: createdAt,
      expiresAt: createdAt.add(ttl),
      seen: seen,
    );
  }

  /// Stable unique id.
  final String id;

  /// Author of the story.
  final UserProfile author;

  /// URL/reference to the story media (image or clip). PHASE 4 SEAM: real
  /// capture/upload is later; this phase the URL is provided/hosted already.
  final String mediaUrl;

  /// Kind of media (image | video).
  final StoryMediaType type;

  /// When the story was posted.
  final DateTime createdAt;

  /// When the story stops being visible (the 24h TTL boundary).
  final DateTime expiresAt;

  /// Viewer-local seen flag (client-authoritative this phase).
  final bool seen;

  /// Whether the story is still active (not yet expired) at [now].
  ///
  /// A story is active while [now] is strictly before [expiresAt]. This is the
  /// client-side ephemerality filter; the server must enforce the same
  /// predicate for the true gate (see the class doc's ENV RISK note).
  bool isActive(DateTime now) => now.isBefore(expiresAt);

  Story copyWith({
    String? id,
    UserProfile? author,
    String? mediaUrl,
    StoryMediaType? type,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? seen,
  }) {
    return Story(
      id: id ?? this.id,
      author: author ?? this.author,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      seen: seen ?? this.seen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Story && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
