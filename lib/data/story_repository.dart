import 'package:flutter/foundation.dart';

import '../models/story.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'mock_data.dart';
import 'profile_repository.dart';

/// A group of one author's ACTIVE stories, held chronologically (oldest-first),
/// as consumed by the story ring and the full-screen viewer.
///
/// Immutable value grouping produced by [StoryRepository.activeStoryGroups].
/// [hasUnseen] drives the ring's gradient-vs-gray affordance: a group renders
/// the gradient ring when any of its stories is unseen, else the muted ring.
class StoryGroup {
  const StoryGroup({required this.author, required this.stories});

  final UserProfile author;

  /// This author's active stories in chronological order (oldest-first) so the
  /// viewer advances forward in time.
  final List<Story> stories;

  /// Whether any story in the group is still unseen.
  bool get hasUnseen => stories.any((s) => !s.seen);

  /// The most recent activity in the group (used for newest-first ordering).
  DateTime get latestAt => stories
      .map((s) => s.createdAt)
      .fold(stories.first.createdAt, (a, b) => a.isAfter(b) ? a : b);
}

/// Owns the viewer-visible STORIES state: the pool of ephemeral stories and the
/// per-story seen flags.
///
/// Follows the same contract as the other repositories (see [PostRepository]/
/// [SafetyRepository]/[RelationshipRepository]):
///
///  * a synchronous public surface ([activeStoryGroups], [activeStoriesFor])
///    over an in-memory cache seeded from [MockData] so the UI and unit tests
///    (which never boot Supabase) always have state immediately;
///  * a [markSeen] mutation that flips a story to seen optimistically and fires
///    EXACTLY ONE [notifyListeners] only on a real change (idempotent — no
///    notify when the story is already seen or unknown), mirroring
///    [SafetyRepository.mute]'s idempotency, and persists the view via a
///    guarded fire-and-forget helper; and
///  * a fire-and-forget, fully guarded [load] that hydrates ACTIVE stories
///    (`stories` where `expires_at > now()` ordered by `created_at`) from
///    Supabase, only notifying when live rows replace the seed (a
///    [listEquals]-guarded no-op offline, mirroring
///    [SafetyRepository.load]'s setEquals guard).
///
/// EPHEMERALITY is CLIENT-FILTERED here: [activeStoryGroups]/[activeStoriesFor]
/// only return stories whose [Story.isActive] is true at `now`. The SERVER must
/// independently enforce expiry — an RLS `expires_at > now()` SELECT predicate
/// plus a scheduled sweep that deletes expired rows (see migration 0006). Until
/// that server enforcement is verified against a live Supabase project it is a
/// documented ENVIRONMENT RISK; the client filter is a UX mirror, not the true
/// gate.
class StoryRepository extends ChangeNotifier {
  StoryRepository() : _stories = List<Story>.of(MockData.stories()) {
    // Hydrate from Supabase in the background. Guarded so it is a no-op when
    // Supabase is unavailable (tests / offline), leaving the mock seed intact.
    // ignore: discarded_futures
    load();
  }

  /// Shared singleton for the app.
  static final StoryRepository instance = StoryRepository();

  /// The in-memory story pool (both active and expired; expiry is filtered on
  /// read by [Story.isActive]).
  final List<Story> _stories;

  /// The id of the current user, used to float their own group to the front of
  /// [activeStoryGroups].
  String get _currentUserId => ProfileRepository.instance.currentUser.id;

  /// The active story groups, one per author, ordered newest-activity-first
  /// with the CURRENT USER'S own group floated to the front when present.
  ///
  /// Excludes expired stories (via [Story.isActive] at [now], defaulting to
  /// `DateTime.now()`). Each group's stories are chronological (oldest-first).
  /// An author with only expired stories produces no group.
  List<StoryGroup> activeStoryGroups({DateTime? now}) {
    final reference = now ?? DateTime.now();
    final byAuthor = <String, List<Story>>{};
    final authors = <String, UserProfile>{};
    for (final s in _stories) {
      if (!s.isActive(reference)) continue; // client-side ephemerality filter
      (byAuthor[s.author.id] ??= <Story>[]).add(s);
      authors[s.author.id] = s.author;
    }

    final groups = byAuthor.entries.map((e) {
      final stories = List<Story>.of(e.value)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return StoryGroup(author: authors[e.key]!, stories: stories);
    }).toList();

    final me = _currentUserId;
    groups.sort((a, b) {
      // Own group first, regardless of recency.
      final aMine = a.author.id == me;
      final bMine = b.author.id == me;
      if (aMine != bMine) return aMine ? -1 : 1;
      // Then newest activity first.
      return b.latestAt.compareTo(a.latestAt);
    });

    return List<StoryGroup>.unmodifiable(groups);
  }

  /// The active stories for [authorId] in chronological order (oldest-first),
  /// excluding expired ones. Empty when the author has no active stories.
  List<Story> activeStoriesFor(String authorId, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final list = _stories
        .where((s) => s.author.id == authorId && s.isActive(reference))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List<Story>.unmodifiable(list);
  }

  /// Hydrates [_stories] from the Supabase `public.stories` table (ACTIVE rows
  /// only: `expires_at > now()`), joined to the author profile. Fire-and-forget;
  /// fully guarded so it never throws (e.g. when Supabase is uninitialized under
  /// tests) and only notifies when it actually replaces the seed with live
  /// rows (a [listEquals]-guarded no-op offline, mirroring
  /// [SafetyRepository.load]).
  Future<void> load() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return; // keep the mock seed as a graceful fallback

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final rows = await supabase
          .from('stories')
          .select(
            'id, owner, media_url, media_type, created_at, expires_at, '
            'profiles:profiles!stories_owner_fkey(*)',
          )
          .gt('expires_at', nowIso)
          .order('created_at');
      final data = (rows as List).cast<Map<String, dynamic>>();

      // Which stories has the viewer already seen (server-authoritative later).
      final views = await supabase
          .from('story_views')
          .select('story_id')
          .eq('viewer', userId);
      final seenIds = (views as List)
          .cast<Map<String, dynamic>>()
          .map((r) => r['story_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final hydrated = <Story>[];
      for (final row in data) {
        final story = _storyFromRow(row, seenIds);
        if (story != null) hydrated.add(story);
      }

      if (listEquals(hydrated, _stories)) return; // nothing changed, no notify
      _stories
        ..clear()
        ..addAll(hydrated);
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  // -- Mark seen -----------------------------------------------------------

  /// Marks the story [storyId] as seen optimistically. Idempotent: no
  /// [notifyListeners] and no write when the story is unknown or already seen
  /// (mirrors [SafetyRepository.mute]). Persists the view via a guarded
  /// fire-and-forget helper.
  void markSeen(String storyId) {
    final index = _stories.indexWhere((s) => s.id == storyId);
    if (index < 0) return; // unknown story: no-op
    if (_stories[index].seen) return; // idempotent: already seen, no notify
    _stories[index] = _stories[index].copyWith(seen: true);
    notifyListeners();
    // ignore: discarded_futures
    _persistSeen(storyId);
  }

  // -- Add a story ---------------------------------------------------------

  /// Adds a new [story] to the pool optimistically and fires one
  /// [notifyListeners]. Persists it via a guarded fire-and-forget helper.
  ///
  /// PHASE 4 SEAM: the [story]'s [Story.mediaUrl] is expected to already point
  /// at hosted media; real on-device capture/upload lands in Phase 4.
  void addStory(Story story) {
    _stories.add(story);
    notifyListeners();
    // ignore: discarded_futures
    _persistNewStory(story);
  }

  // -- Supabase persistence (fire-and-forget, fully guarded) ---------------

  /// Records a view into `public.story_views` keyed by
  /// `(story_id, viewer = auth.uid())`. Upsert so a repeat view is a safe
  /// no-op server-side. No-op/guarded when Supabase is unavailable.
  Future<void> _persistSeen(String storyId) async {
    try {
      final viewer = supabase.auth.currentUser?.id;
      if (viewer == null) return;
      await supabase.from('story_views').upsert(<String, dynamic>{
        'story_id': storyId,
        'viewer': viewer,
      });
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Inserts a new story into `public.stories`. The `owner` is the signed-in
  /// user (enforced again by the `stories_insert_own` RLS policy). No-op/guarded
  /// when Supabase is unavailable.
  Future<void> _persistNewStory(Story story) async {
    try {
      final owner = supabase.auth.currentUser?.id;
      if (owner == null) return;
      await supabase.from('stories').insert(<String, dynamic>{
        'id': story.id,
        'owner': owner,
        'media_url': story.mediaUrl,
        'media_type': story.type.name,
        'expires_at': story.expiresAt.toUtc().toIso8601String(),
      });
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  // -- Mapping -------------------------------------------------------------

  Story? _storyFromRow(Map<String, dynamic> row, Set<String> seenIds) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final author = _authorFromRow(row['profiles'], row['owner']);
    if (author.id.isEmpty) return null;
    return Story(
      id: id,
      author: author,
      mediaUrl: (row['media_url'] as String?) ?? '',
      type: (row['media_type']?.toString() == 'video')
          ? StoryMediaType.video
          : StoryMediaType.image,
      createdAt: _parseDate(row['created_at']),
      expiresAt: _parseDate(row['expires_at']),
      seen: seenIds.contains(id),
    );
  }

  UserProfile _authorFromRow(Object? profiles, Object? fallbackId) {
    if (profiles is Map) {
      final p = profiles.cast<String, dynamic>();
      final username = (p['username'] as String?) ?? 'user';
      return UserProfile(
        id: p['id']?.toString() ?? fallbackId?.toString() ?? '',
        username: username,
        displayName: (p['display_name'] as String?) ?? username,
        bio: (p['bio'] as String?) ?? '',
        avatarUrl: p['avatar_url'] as String?,
        bannerUrl: p['banner_url'] as String?,
        verified: (p['verified'] as bool?) ?? false,
        verificationKind: (p['verification_kind'] as String?) ?? 'verified',
        isPrivate: (p['is_private'] as bool?) ?? false,
      );
    }
    return UserProfile(
      id: fallbackId?.toString() ?? '',
      username: 'user',
      displayName: 'User',
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }
}
