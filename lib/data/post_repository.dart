import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../models/post_attachment.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'feed_page.dart';
import 'feed_ranking.dart';
import 'mock_data.dart';
import 'profile_repository.dart';
import 'safety_repository.dart';
import 'save_repository.dart';

/// The post store for the app, backed by Supabase.
///
/// Uses [ChangeNotifier] so screens can listen for updates without pulling in
/// a state-management package. The public surface is deliberately synchronous
/// (`forYou`, `following`, the `toggle*` mutators, `addPost`) and reads from an
/// in-memory `_posts` cache. That cache is:
///
///  * seeded from [MockData.posts] at construction so the UI (and the unit
///    tests, which never boot Supabase) always have data immediately, and
///  * hydrated asynchronously from Supabase via [load], called fire-and-forget
///    from the constructor. `load` is fully guarded: if Supabase is not
///    initialized (e.g. under `flutter test`) or the query fails, it silently
///    keeps the mock seed and does NOT notify, so it can never interfere with
///    the synchronous, single-notify behavior the tests assert.
///
/// Mutations (`toggleLike`, `toggleRepost`, `addPost`) update the cache
/// optimistically and fire exactly one [notifyListeners]; the Supabase write is
/// a separate fire-and-forget helper that never throws into the UI.
class PostRepository extends ChangeNotifier {
  PostRepository({FeedRankingStrategy? ranking})
      : _ranking = ranking ?? const ChronologicalRanking(),
        _posts = MockData.posts() {
    // Hydrate from Supabase in the background. Guarded so it is a no-op when
    // Supabase is unavailable (tests / offline), leaving the mock seed intact.
    // ignore: discarded_futures
    load();
  }

  /// Shared singleton for the app.
  static final PostRepository instance = PostRepository();

  /// The strategy that orders feeds. Defaults to [ChronologicalRanking]
  /// (newest-first), preserving the app's current behavior; swap it for a
  /// scored/personalized strategy without touching this class.
  final FeedRankingStrategy _ranking;

  final List<Post> _posts;

  /// The "For you" timeline (all posts, ranked by [_ranking]).
  ///
  /// Blocked/muted authors AND posts matching a muted keyword are hidden via
  /// the pure [filterHidden] helper, applied AFTER ranking so ordering is
  /// unchanged for visible posts. The filter is IDENTITY when the safety sets
  /// and the mute-word set are all empty (the default), so this preserves the
  /// exact feed contents/ordering the repository tests assert.
  List<Post> forYou() {
    return List<Post>.unmodifiable(_visible(_ranking.rank(_posts)));
  }

  /// The "Following" timeline (a subset by author, ranked by [_ranking]).
  List<Post> following() {
    final followedIds = MockData.followingPosts().map((p) => p.author.id).toSet();
    final subset = _posts.where((p) => followedIds.contains(p.author.id)).toList();
    return List<Post>.unmodifiable(_visible(_ranking.rank(subset)));
  }

  /// Applies the optimistic block/mute filter over the current
  /// [SafetyRepository] sets. Delegates to the pure [filterHidden] helper,
  /// which is identity (pass-through) when both sets are empty.
  List<Post> _visible(List<Post> ranked) {
    final safety = SafetyRepository.instance;
    return filterHidden(
      ranked,
      blocked: safety.blockedIds,
      muted: safety.mutedIds,
      muteWords: safety.muteWordSet,
      // The viewer's own posts are always visible in their own feed/export,
      // never hidden by a (self-directed) block/mute/muted-word. See
      // [filterHidden] and review issues 1 & 4.
      viewerId: ProfileRepository.instance.currentUser.id,
    );
  }

  /// Hydrates [_posts] from Supabase with a BOUNDED, keyset-ordered query.
  ///
  /// The query is capped at [kFeedPageSize] rows and ordered by
  /// `(created_at desc, id desc)` so it (a) never issues an unbounded select
  /// and (b) lines up with the `(created_at desc, id)` index for
  /// keyset-paginated [loadMore]. Fire-and-forget; fully guarded so it never
  /// throws (e.g. when Supabase is uninitialized under tests) and only notifies
  /// when it actually replaces the cache with live rows.
  Future<void> load() async {
    try {
      final rows = await supabase
          .from('posts')
          .select('*, profiles(*), post_attachments(*), reactions(type)')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(kFeedPageSize);
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return; // keep the mock seed as a graceful fallback
      final viewer = await _viewerEngagement();
      final mapped =
          data.map((row) => _postFromRow(row, viewer: viewer)).toList();
      _posts
        ..clear()
        ..addAll(mapped);
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
    }
  }

  /// Fetches the next bounded page after [cursor] using a keyset predicate.
  ///
  /// Uses `(created_at, id) < (cursor.createdAt, cursor.id)` expressed as an
  /// `or` composite over the `(created_at desc, id)` index. This is seek-based,
  /// never `offset`-based (which degrades at scale), and is bounded to
  /// [kFeedPageSize]. Newly fetched rows are appended to the cache (de-duped by
  /// id) and a single [notifyListeners] fires only when real rows arrive.
  /// Returns a [FeedPage] describing the fetched rows; returns [FeedPage.empty]
  /// when Supabase is unavailable or there is nothing more to load.
  Future<FeedPage> loadMore(FeedCursor cursor) async {
    try {
      final iso = cursor.createdAt.toUtc().toIso8601String();
      final rows = await supabase
          .from('posts')
          .select('*, profiles(*), post_attachments(*), reactions(type)')
          .or(
            'created_at.lt.$iso,'
            'and(created_at.eq.$iso,id.lt.${cursor.id})',
          )
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(kFeedPageSize);
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return FeedPage.empty;
      final viewer = await _viewerEngagement();
      final mapped =
          data.map((row) => _postFromRow(row, viewer: viewer)).toList();
      final existingIds = _posts.map((p) => p.id).toSet();
      final fresh = mapped.where((p) => !existingIds.contains(p.id)).toList();
      if (fresh.isNotEmpty) {
        _posts.addAll(fresh);
        notifyListeners();
      }
      return FeedPage(
        posts: mapped,
        nextCursor: FeedCursor.fromPost(mapped.last),
        hasMore: mapped.length == kFeedPageSize,
      );
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: no more rows.
      return FeedPage.empty;
    }
  }

  int _indexOf(String id) => _posts.indexWhere((p) => p.id == id);

  /// Toggles the like state and count. Returns the updated post, or null.
  ///
  /// A thin COMPATIBILITY WRAPPER over the general reaction path: liking maps to
  /// `react(id, ReactionType.like)` and un-liking (when the viewer's current
  /// reaction is `like`) maps to [clearReaction]. This preserves the exact
  /// legacy contract the like button + tests assert — `liked` flips and
  /// `likeCount` moves +/-1 with a single notify — while routing through the
  /// same persistence as every other reaction. If the viewer's current reaction
  /// is a NON-like type, tapping like switches it to `like` (react handles the
  /// count bookkeeping).
  Post? toggleLike(String id) {
    final i = _indexOf(id);
    if (i < 0) return null;
    return _posts[i].liked ? clearReaction(id) : react(id, ReactionType.like);
  }

  /// Sets the viewer's reaction on [id] to [type] optimistically and persists
  /// it to `public.reactions`. Returns the updated post, or null for an
  /// unknown id.
  ///
  /// Reactions are one-per-user-per-post: switching from an existing reaction
  /// decrements the old bucket and increments the new one. The special `like`
  /// type keeps the legacy [Post.likeCount] aggregate in sync locally (+1 when
  /// like is newly applied, -1 when replaced by another type), matching the
  /// server trigger `sync_post_reaction_like_count`. Fires exactly one notify.
  Post? react(String id, ReactionType type) {
    final i = _indexOf(id);
    if (i < 0) return null;
    final current = _posts[i];
    final previous = current.myReaction;
    if (previous == type) return current; // no change

    final counts = Map<ReactionType, int>.of(current.reactionCounts);
    if (previous != null) {
      counts[previous] = (counts[previous] ?? 1) - 1;
      if ((counts[previous] ?? 0) <= 0) counts.remove(previous);
    }
    counts[type] = (counts[type] ?? 0) + 1;

    // Keep the legacy aggregate like_count consistent with the like bucket.
    var likeCount = current.likeCount;
    if (type == ReactionType.like && previous != ReactionType.like) {
      likeCount += 1;
    } else if (previous == ReactionType.like && type != ReactionType.like) {
      likeCount -= 1;
    }

    final updated = current.copyWith(
      myReaction: type,
      reactionCounts: counts,
      likeCount: likeCount,
    );
    _posts[i] = updated;
    notifyListeners();
    // ignore: discarded_futures
    _persistReaction(updated, type: type, cleared: false);
    return updated;
  }

  /// Clears the viewer's reaction on [id] optimistically and deletes it from
  /// `public.reactions`. Returns the updated post, or null for an unknown id.
  /// A no-op (still returns the post, no notify) when there is no reaction.
  Post? clearReaction(String id) {
    final i = _indexOf(id);
    if (i < 0) return null;
    final current = _posts[i];
    final previous = current.myReaction;
    if (previous == null) return current; // nothing to clear

    final counts = Map<ReactionType, int>.of(current.reactionCounts);
    counts[previous] = (counts[previous] ?? 1) - 1;
    if ((counts[previous] ?? 0) <= 0) counts.remove(previous);

    final likeCount = previous == ReactionType.like
        ? current.likeCount - 1
        : current.likeCount;

    final updated = current.copyWith(
      clearMyReaction: true,
      reactionCounts: counts,
      likeCount: likeCount,
    );
    _posts[i] = updated;
    notifyListeners();
    // ignore: discarded_futures
    _persistReaction(updated, type: previous, cleared: true);
    return updated;
  }

  /// Toggles the repost state and count. Returns the updated post, or null.
  Post? toggleRepost(String id) {
    final i = _indexOf(id);
    if (i < 0) return null;
    final current = _posts[i];
    final nowReposted = !current.reposted;
    final updated = current.copyWith(
      reposted: nowReposted,
      repostCount: current.repostCount + (nowReposted ? 1 : -1),
    );
    _posts[i] = updated;
    notifyListeners();
    // ignore: discarded_futures
    _persistRepost(updated);
    return updated;
  }

  /// Toggles the bookmark/save state for [id]. Returns the updated post, or
  /// null for an unknown id.
  ///
  /// Bookmarks are now SERVER-BACKED via [SaveRepository]: this drives
  /// `SaveRepository.toggleSave` (which persists to `public.saves`) and mirrors
  /// the resulting saved state onto the in-memory [Post.bookmarked] flag so the
  /// card reflects it immediately. Both repositories fire their own single
  /// notify, preserving the optimistic contract; the returned post carries the
  /// new `bookmarked` value so existing tests that assert the flip still pass.
  Post? toggleBookmark(String id) {
    final i = _indexOf(id);
    if (i < 0) return null;
    SaveRepository.instance.toggleSave(id);
    final current = _posts[i];
    final updated =
        current.copyWith(bookmarked: SaveRepository.instance.isSaved(id));
    _posts[i] = updated;
    notifyListeners();
    return updated;
  }

  /// Adds a new post to the top of the timeline (compose flow) and persists it.
  ///
  /// [hashtags]/[mentions] are the normalized entities extracted from the post
  /// content by the compose flow (see `utils/text_entities.dart`); they are
  /// forwarded to the guarded persist so the `post_hashtags`/`post_mentions`
  /// discovery relations are populated after the post row is inserted. They
  /// default to empty (a plain text post writes no relations).
  void addPost(
    Post post, {
    Set<String> hashtags = const <String>{},
    Set<String> mentions = const <String>{},
  }) {
    _posts.insert(0, post);
    notifyListeners();
    // ignore: discarded_futures
    _persistNewPost(post, hashtags: hashtags, mentions: mentions);
  }

  // -- Supabase persistence (fire-and-forget, fully guarded) ---------------

  /// Reflects a reaction change into the `public.reactions` join table only,
  /// keyed by `(user_id = auth.uid(), post_id)` (one reaction per user/post).
  ///
  /// The per-type reaction counts AND the legacy `posts.like_count` aggregate
  /// are owned by the database: a trigger on `public.reactions`
  /// (`sync_post_reaction_like_count`, see `0007_relations.sql`) recomputes
  /// `posts.like_count` from `count(*)` over reactions where `type = 'like'`.
  /// The client deliberately does NOT write any count here (which would race
  /// with concurrent clients); it only records the user's reaction and lets the
  /// server reconcile. When [cleared] the reaction row is DELETED; otherwise it
  /// is UPSERTED to [type] (switching an existing reaction in place). Mirrors
  /// the old `_persistLike` insert/delete; guarded/no-op when Supabase is
  /// unavailable.
  Future<void> _persistReaction(
    Post post, {
    required ReactionType type,
    required bool cleared,
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      if (cleared) {
        await supabase
            .from('reactions')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', post.id);
      } else {
        await supabase.from('reactions').upsert(<String, dynamic>{
          'user_id': userId,
          'post_id': post.id,
          'type': type.name,
        }, onConflict: 'user_id,post_id');
      }
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Reflects a repost toggle into the `reposts` join table only.
  ///
  /// As of migration `0002_authz_and_core_tables.sql`, `posts.repost_count` is
  /// owned by the database: an `after insert or delete` trigger on `reposts`
  /// (`sync_post_repost_count`) recomputes it from `count(*)`, exactly like
  /// `sync_post_like_count` does for likes. This retires the old
  /// client-authoritative `repost_count` write, which raced with concurrent
  /// clients and drifted from the true repost set. The client now only records
  /// the user's repost/un-repost keyed by `(user_id, post_id)` and lets the
  /// server reconcile the count; the local optimistic count is a display-only
  /// estimate until the next [load]. No-op/guarded when Supabase is unavailable.
  Future<void> _persistRepost(Post post) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      if (post.reposted) {
        await supabase.from('reposts').insert(<String, dynamic>{
          'user_id': userId,
          'post_id': post.id,
        });
      } else {
        await supabase
            .from('reposts')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', post.id);
      }
    } catch (_) {
      // Ignore persistence failures; the optimistic in-memory state stands.
    }
  }

  /// Inserts a newly composed post into the `posts` table.
  ///
  /// The `id` is sent explicitly (not left to the DB default) so the persisted
  /// row's primary key equals the in-memory [Post.id]. Callers generate that
  /// id with `newUuidV4()` (see `utils/ids.dart`, used in
  /// `compose_screen.dart`), which the `uuid primary key` column accepts as a
  /// valid UUID. This keeps local and
  /// server ids identical, so a subsequent per-id write (e.g. a like on the
  /// just-composed post) targets the correct row instead of a nonexistent one.
  Future<void> _persistNewPost(
    Post post, {
    Set<String> hashtags = const <String>{},
    Set<String> mentions = const <String>{},
  }) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await supabase.from('posts').insert(<String, dynamic>{
        'id': post.id,
        'owner': userId,
        'content': post.content,
        // Legacy single-media columns are kept in sync via the compatibility
        // shim (attachments.first) so pre-0005 readers still work; `kind` is
        // the new polymorphic discriminator added by migration 0005.
        'media_url': post.mediaUrl,
        'media_type': post.mediaType.name,
        'kind': post.kind.name,
        // Optional free-text location tag (Phase 3). A real place-picker /
        // geocoder that also fills lat/lng is a Phase 4/5 seam.
        'location': post.location,
        'lat': post.lat,
        'lng': post.lng,
      });
      // Persist the ordered attachments into post_attachments (guarded,
      // fire-and-forget). A text post has an empty list, so nothing is written.
      // PHASE 4 SEAM: attachments are carried BY URL here; real byte
      // capture/upload to the storage bucket lands in Phase 4.
      if (post.attachments.isNotEmpty) {
        await supabase.from('post_attachments').insert(<Map<String, dynamic>>[
          for (final a in post.attachments)
            <String, dynamic>{
              'id': a.id,
              'post_id': post.id,
              'position': a.position,
              'type': a.type.name,
              'url': a.url,
              'thumb_url': a.thumbUrl,
              'width': a.width,
              'height': a.height,
              'alt_text': a.altText,
            },
        ]);
      }
      // Populate the discovery relations (guarded, fire-and-forget). Hashtags
      // are upserted into the shared public.hashtags dictionary then linked via
      // post_hashtags; mentions resolve usernames to user ids and link via
      // post_mentions. Both are indexed for a later search/discovery phase. A
      // failure here (e.g. an unknown mentioned username) never affects the
      // already-inserted post.
      await _persistHashtags(post.id, hashtags);
      await _persistMentions(post.id, mentions);
    } catch (_) {
      // Ignore persistence failures; the post is already shown locally.
    }
  }

  /// Upserts each [tags] entry into `public.hashtags` and links it to [postId]
  /// via `public.post_hashtags`. Tags are normalized (lower-cased, no '#') by
  /// the caller. Guarded so a failure never throws into the compose flow.
  Future<void> _persistHashtags(String postId, Set<String> tags) async {
    if (tags.isEmpty) return;
    try {
      // Upsert the shared tag dictionary and read back the ids.
      final rows = await supabase
          .from('hashtags')
          .upsert(
            <Map<String, dynamic>>[for (final t in tags) <String, dynamic>{'tag': t}],
            onConflict: 'tag',
          )
          .select('id, tag');
      final ids = (rows as List)
          .map((r) => (r as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return;
      await supabase.from('post_hashtags').upsert(<Map<String, dynamic>>[
        for (final hashtagId in ids)
          <String, dynamic>{'post_id': postId, 'hashtag_id': hashtagId},
      ], onConflict: 'post_id,hashtag_id');
    } catch (_) {
      // Ignore; the post itself is already persisted/shown.
    }
  }

  /// Resolves each mentioned username in [usernames] to a profile id and links
  /// it to [postId] via `public.post_mentions`. Usernames are normalized
  /// (lower-cased, no '@') by the caller. Guarded so an unknown username or a
  /// failed lookup never throws into the compose flow.
  Future<void> _persistMentions(String postId, Set<String> usernames) async {
    if (usernames.isEmpty) return;
    try {
      final rows = await supabase
          .from('profiles')
          .select('id, username')
          .inFilter('username', usernames.toList());
      final ids = (rows as List)
          .map((r) => (r as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isEmpty) return;
      await supabase.from('post_mentions').upsert(<Map<String, dynamic>>[
        for (final userId in ids)
          <String, dynamic>{'post_id': postId, 'mentioned_user': userId},
      ], onConflict: 'post_id,mentioned_user');
    } catch (_) {
      // Ignore; the post itself is already persisted/shown.
    }
  }

  /// Fetches the signed-in viewer's own reaction/repost state so hydrated rows
  /// can render their `myReaction`/`liked`/`reposted` flags correctly.
  ///
  /// The server owns the denormalized counters, but per-viewer toggle state is
  /// NOT denormalized onto `posts` (it is derived from the join tables).
  /// Without this, [_postFromRow] would default all flags to `false`, so a
  /// post the viewer already reacted to / reposted would render as un-toggled
  /// after a [load].
  ///
  /// REACTION READ PATH (review v1, issue 1): the viewer's own reaction is now
  /// read from `public.reactions` — the SOLE store the client writes since the
  /// migrate-like-into-reactions decision (see `0007_relations.sql`). It reads
  /// the actual reaction TYPE per post (not a forced `like`), so a `love`/
  /// `laugh`/… reaction survives a reload with the right glyph, and a `like`
  /// keeps the legacy `liked` compatibility view lit (like-implies-liked). The
  /// dormant `public.likes` table is no longer consulted (it has no client
  /// writer). This reads only the viewer's own rows (scoped by `user_id`); RLS +
  /// the `user_id` filter already limit it to the caller's own engagement.
  /// Fully guarded: returns an empty engagement set when Supabase is
  /// unavailable/unauthenticated, preserving the mock-fallback path.
  Future<_ViewerEngagement> _viewerEngagement() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const _ViewerEngagement.empty();
    try {
      final reactionRows = await supabase
          .from('reactions')
          .select('post_id, type')
          .eq('user_id', userId);
      final repostRows = await supabase
          .from('reposts')
          .select('post_id')
          .eq('user_id', userId);
      final reactions = <String, ReactionType>{};
      for (final r in (reactionRows as List)) {
        if (r is! Map) continue;
        final postId = r['post_id']?.toString() ?? '';
        final type = _reactionTypeFromName(r['type']);
        if (postId.isNotEmpty && type != null) reactions[postId] = type;
      }
      final repostedIds = (repostRows as List)
          .map((r) => (r as Map)['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      return _ViewerEngagement(reactions: reactions, reposted: repostedIds);
    } catch (_) {
      // Engagement lookup failed: fall back to no per-viewer state rather than
      // failing the whole hydration.
      return const _ViewerEngagement.empty();
    }
  }

  // -- Mapping -------------------------------------------------------------

  Post _postFromRow(Map<String, dynamic> row, {_ViewerEngagement? viewer}) {
    return mapPostRow(
      row,
      viewerReactions: viewer?.reactions ?? const <String, ReactionType>{},
      repostedIds: viewer?.reposted ?? const <String>{},
    );
  }

  /// Maps a `posts` row (with a joined `profiles(*)` object) to a [Post].
  ///
  /// [viewerReactions] maps a post id to the viewer's own reaction TYPE (read
  /// from `public.reactions` by [_viewerEngagement]); when the row's id is
  /// present the mapped post carries that exact reaction, so a non-like
  /// reaction survives a reload with the right glyph and a `like` keeps the
  /// legacy `liked` view lit. [repostedIds] is the viewer's own repost set.
  /// [likedIds]/[reactedIds] are the LEGACY like/reaction-id sets kept for
  /// backward compatibility (a row id in either means a `like`); new callers
  /// should prefer [viewerReactions] which carries the real type. The
  /// server-owned counts are always taken from the row as-is. Exposed for
  /// testing so the row->model mapping (including per-viewer hydration) is
  /// verifiable without booting Supabase.
  @visibleForTesting
  static Post mapPostRow(
    Map<String, dynamic> row, {
    Map<String, ReactionType> viewerReactions = const <String, ReactionType>{},
    Set<String> likedIds = const <String>{},
    Set<String> repostedIds = const <String>{},
    Set<String> reactedIds = const <String>{},
  }) {
    final id = row['id']?.toString() ?? '';
    final attachments = _attachmentsFromRow(id, row);
    final reactionCounts = _reactionCountsFromRow(row);
    // The viewer's own reaction, resolved in precedence order:
    //   1. an explicit joined `my_reaction`/`viewer_reaction` field on the row;
    //   2. the viewer's actual reaction TYPE from public.reactions
    //      (viewerReactions), so love/laugh/… survive a reload, not just like;
    //   3. the LEGACY like/reaction id sets (a row id => a `like`).
    // Guarded so absence yields no reaction (and, via the like-implies-liked
    // rule, liked == false).
    final myReaction =
        _reactionTypeFromName(row['my_reaction'] ?? row['viewer_reaction']) ??
            viewerReactions[id] ??
            (likedIds.contains(id) || reactedIds.contains(id)
                ? ReactionType.like
                : null);
    return Post(
      id: id,
      author: _authorFromRow(row['profiles']),
      content: (row['content'] as String?) ?? '',
      location: row['location'] as String?,
      lat: _asDoubleOrNull(row['lat']),
      lng: _asDoubleOrNull(row['lng']),
      myReaction: myReaction,
      reactionCounts: reactionCounts,
      // The ordered attachments drive the polymorphic `kind` (via deriveKind in
      // the Post constructor). When the joined post_attachments array is
      // present we map it; otherwise we fall back to the legacy single
      // media_url/media_type slot so pre-0005 rows still map to a one-image or
      // one-video post (or a text post when there is no media).
      attachments: attachments,
      createdAt: _parseDate(row['created_at']),
      replyCount: _asInt(row['reply_count']),
      repostCount: _asInt(row['repost_count']),
      likeCount: _asInt(row['like_count']),
      viewCount: _asInt(row['view_count']),
      reposted: repostedIds.contains(id),
    );
  }

  /// Builds the per-type reaction counts from a joined reactions aggregate on
  /// the row when present, else an empty map. Two shapes are accepted:
  ///   * `reaction_counts`: a `{ 'like': 3, 'love': 1, ... }` map, or
  ///   * `reactions`: an array of `{ 'type': 'like', 'count': 3 }` aggregate
  ///     rows (as a PostgREST group-by join would return).
  /// Unknown/zero types are ignored. Defaults to `const {}` so a row without a
  /// reactions join maps to a post with no reaction counts (existing feed
  /// assertions are unaffected).
  static Map<ReactionType, int> _reactionCountsFromRow(
    Map<String, dynamic> row,
  ) {
    final counts = <ReactionType, int>{};
    final map = row['reaction_counts'];
    if (map is Map) {
      map.forEach((key, value) {
        final type = _reactionTypeFromName(key);
        final n = _asInt(value);
        if (type != null && n > 0) counts[type] = n;
      });
      return counts;
    }
    final raw = row['reactions'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          final type = _reactionTypeFromName(entry['type']);
          // Two shapes: a pre-aggregated `{type, count}` group-by row, or a
          // raw un-aggregated `{type}` reaction row from a plain
          // `reactions(type)` join (each such row counts as one).
          final n = entry.containsKey('count') ? _asInt(entry['count']) : 1;
          if (type != null && n > 0) {
            counts[type] = (counts[type] ?? 0) + n;
          }
        }
      }
    }
    return counts;
  }

  static ReactionType? _reactionTypeFromName(Object? name) {
    switch (name?.toString()) {
      case 'like':
        return ReactionType.like;
      case 'love':
        return ReactionType.love;
      case 'laugh':
        return ReactionType.laugh;
      case 'wow':
        return ReactionType.wow;
      case 'sad':
        return ReactionType.sad;
      case 'angry':
        return ReactionType.angry;
      default:
        return null;
    }
  }

  static double? _asDoubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Maps a post's attachments from the joined `post_attachments` array when
  /// present (ORDERED by `position`), falling back to the legacy
  /// `media_url`/`media_type` single-attachment slot for pre-0005 rows.
  ///
  /// Returns an empty list for a text post (no attachments and no legacy
  /// media), which [deriveKind] maps to [PostKind.text].
  static List<PostAttachment> _attachmentsFromRow(
    String postId,
    Map<String, dynamic> row,
  ) {
    final raw = row['post_attachments'];
    if (raw is List && raw.isNotEmpty) {
      final list = raw
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _attachmentFromRow(postId, m.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      return list;
    }
    // Legacy fallback: build a single attachment from the old media columns.
    final mediaUrl = row['media_url'] as String?;
    final mediaType = _mediaTypeFromName(row['media_type'] as String?);
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

  static PostAttachment _attachmentFromRow(
    String postId,
    Map<String, dynamic> m,
  ) {
    return PostAttachment(
      id: m['id']?.toString() ?? '',
      postId: m['post_id']?.toString() ?? postId,
      position: _asInt(m['position']),
      type: (m['type'] as String?) == 'video'
          ? AttachmentType.video
          : AttachmentType.image,
      url: (m['url'] as String?) ?? '',
      thumbUrl: m['thumb_url'] as String?,
      width: m['width'] == null ? null : _asInt(m['width']),
      height: m['height'] == null ? null : _asInt(m['height']),
      altText: m['alt_text'] as String?,
    );
  }

  /// Builds a [UserProfile] from the joined `profiles` object. Falls back to a
  /// minimal placeholder when the join is absent.
  static UserProfile _authorFromRow(Object? profiles) {
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

  static MediaType _mediaTypeFromName(String? name) {
    switch (name) {
      case 'image':
        return MediaType.image;
      case 'video':
        return MediaType.video;
      default:
        return MediaType.none;
    }
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

/// The signed-in viewer's own reaction/repost state, keyed by post id.
///
/// Used to hydrate per-viewer `myReaction`/`liked`/`reposted` flags onto mapped
/// posts, which the server-owned counters on `posts` do not carry. [reactions]
/// maps a post id to the viewer's actual reaction TYPE (read from
/// `public.reactions`), so a non-like reaction survives a reload with the right
/// glyph and a `like` keeps the legacy `liked` view lit (like-implies-liked).
/// An empty instance represents "no viewer / unauthenticated / lookup failed",
/// in which case all flags default to their un-engaged value.
class _ViewerEngagement {
  const _ViewerEngagement({required this.reactions, required this.reposted});

  const _ViewerEngagement.empty()
      : reactions = const <String, ReactionType>{},
        reposted = const <String>{};

  /// Post id -> the viewer's own reaction type on that post.
  final Map<String, ReactionType> reactions;

  /// Post ids the viewer has reposted.
  final Set<String> reposted;
}
