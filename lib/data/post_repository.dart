import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'feed_page.dart';
import 'feed_ranking.dart';
import 'mock_data.dart';

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
  List<Post> forYou() {
    return List<Post>.unmodifiable(_ranking.rank(_posts));
  }

  /// The "Following" timeline (a subset by author, ranked by [_ranking]).
  List<Post> following() {
    final followedIds = MockData.followingPosts().map((p) => p.author.id).toSet();
    final subset = _posts.where((p) => followedIds.contains(p.author.id)).toList();
    return List<Post>.unmodifiable(_ranking.rank(subset));
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
          .select('*, profiles(*)')
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
          .select('*, profiles(*)')
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
  Post? toggleLike(String id) {
    final i = _indexOf(id);
    if (i < 0) return null;
    final current = _posts[i];
    final nowLiked = !current.liked;
    final updated = current.copyWith(
      liked: nowLiked,
      likeCount: current.likeCount + (nowLiked ? 1 : -1),
    );
    _posts[i] = updated;
    notifyListeners();
    // Persist in the background; never blocks or throws into the UI.
    // ignore: discarded_futures
    _persistLike(updated);
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

  /// Toggles the bookmark state. Returns the updated post, or null.
  ///
  /// Bookmarks are a local-only affordance (no bookmarks table in the schema),
  /// so this stays in-memory and does not persist.
  Post? toggleBookmark(String id) {
    final i = _indexOf(id);
    if (i < 0) return null;
    final current = _posts[i];
    final updated = current.copyWith(bookmarked: !current.bookmarked);
    _posts[i] = updated;
    notifyListeners();
    return updated;
  }

  /// Adds a new post to the top of the timeline (compose flow) and persists it.
  void addPost(Post post) {
    _posts.insert(0, post);
    notifyListeners();
    // ignore: discarded_futures
    _persistNewPost(post);
  }

  // -- Supabase persistence (fire-and-forget, fully guarded) ---------------

  /// Reflects a like toggle into the `likes` join table only.
  ///
  /// The `posts.like_count` counter is owned by the database: an
  /// `after insert or delete` trigger on `likes` recomputes it from
  /// `count(*)` (see `sync_post_like_count` in `0001_init.sql`). The client
  /// deliberately does NOT write `like_count` here, which would race with
  /// concurrent clients and drift from the true like set; it only records the
  /// user's like/unlike and lets the server reconcile the count. The local
  /// optimistic count remains a display-only estimate until the next [load].
  /// No-op/guarded when Supabase is unavailable.
  Future<void> _persistLike(Post post) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      if (post.liked) {
        await supabase.from('likes').insert(<String, dynamic>{
          'user_id': userId,
          'post_id': post.id,
        });
      } else {
        await supabase
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', post.id);
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
  Future<void> _persistNewPost(Post post) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      await supabase.from('posts').insert(<String, dynamic>{
        'id': post.id,
        'owner': userId,
        'content': post.content,
        'media_url': post.mediaUrl,
        'media_type': post.mediaType.name,
      });
    } catch (_) {
      // Ignore persistence failures; the post is already shown locally.
    }
  }

  /// Fetches the signed-in viewer's own like/repost sets so hydrated rows can
  /// render their `liked`/`reposted` state correctly.
  ///
  /// The server owns the denormalized counters, but per-viewer toggle state is
  /// NOT denormalized onto `posts` (it is derived from the `likes`/`reposts`
  /// join tables). Without this, [_postFromRow] would default both flags to
  /// `false`, so a post the viewer already liked/reposted would render as
  /// un-toggled after a [load]. This reads only the viewer's own rows (scoped
  /// by `user_id`), bounded to the ids present is unnecessary because RLS +
  /// the `user_id` filter already limit it to the caller's own engagement.
  /// Fully guarded: returns an empty engagement set when Supabase is
  /// unavailable/unauthenticated, preserving the mock-fallback path.
  Future<_ViewerEngagement> _viewerEngagement() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const _ViewerEngagement.empty();
    try {
      final likeRows = await supabase
          .from('likes')
          .select('post_id')
          .eq('user_id', userId);
      final repostRows = await supabase
          .from('reposts')
          .select('post_id')
          .eq('user_id', userId);
      final likedIds = (likeRows as List)
          .map((r) => (r as Map)['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final repostedIds = (repostRows as List)
          .map((r) => (r as Map)['post_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      return _ViewerEngagement(liked: likedIds, reposted: repostedIds);
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
      likedIds: viewer?.liked ?? const <String>{},
      repostedIds: viewer?.reposted ?? const <String>{},
    );
  }

  /// Maps a `posts` row (with a joined `profiles(*)` object) to a [Post].
  ///
  /// [likedIds]/[repostedIds] are the signed-in viewer's own like/repost post
  /// ids; when the row's id is present in those sets the mapped post carries
  /// the corresponding `liked`/`reposted` flag. The server-owned counts are
  /// always taken from the row as-is. Exposed for testing so the row->model
  /// mapping (including per-viewer hydration) is verifiable without booting
  /// Supabase.
  @visibleForTesting
  static Post mapPostRow(
    Map<String, dynamic> row, {
    Set<String> likedIds = const <String>{},
    Set<String> repostedIds = const <String>{},
  }) {
    final id = row['id']?.toString() ?? '';
    return Post(
      id: id,
      author: _authorFromRow(row['profiles']),
      content: (row['content'] as String?) ?? '',
      mediaUrl: row['media_url'] as String?,
      mediaType: _mediaTypeFromName(row['media_type'] as String?),
      createdAt: _parseDate(row['created_at']),
      replyCount: _asInt(row['reply_count']),
      repostCount: _asInt(row['repost_count']),
      likeCount: _asInt(row['like_count']),
      viewCount: _asInt(row['view_count']),
      liked: likedIds.contains(id),
      reposted: repostedIds.contains(id),
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

/// The signed-in viewer's own like/repost sets, keyed by post id.
///
/// Used to hydrate per-viewer `liked`/`reposted` flags onto mapped posts, which
/// the server-owned counters on `posts` do not carry. An empty instance
/// represents "no viewer / unauthenticated / lookup failed", in which case both
/// flags default to `false`.
class _ViewerEngagement {
  const _ViewerEngagement({required this.liked, required this.reposted});

  const _ViewerEngagement.empty()
      : liked = const <String>{},
        reposted = const <String>{};

  /// Post ids the viewer has liked.
  final Set<String> liked;

  /// Post ids the viewer has reposted.
  final Set<String> reposted;
}
