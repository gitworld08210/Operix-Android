import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
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
  PostRepository() : _posts = MockData.posts() {
    // Hydrate from Supabase in the background. Guarded so it is a no-op when
    // Supabase is unavailable (tests / offline), leaving the mock seed intact.
    // ignore: discarded_futures
    load();
  }

  /// Shared singleton for the app.
  static final PostRepository instance = PostRepository();

  final List<Post> _posts;

  /// The "For you" timeline (all posts, newest first).
  List<Post> forYou() {
    final list = List<Post>.of(_posts);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<Post>.unmodifiable(list);
  }

  /// The "Following" timeline (a subset by author).
  List<Post> following() {
    final followedIds = MockData.followingPosts().map((p) => p.author.id).toSet();
    final list = _posts.where((p) => followedIds.contains(p.author.id)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<Post>.unmodifiable(list);
  }

  /// Hydrates [_posts] from Supabase. Fire-and-forget; fully guarded so it
  /// never throws (e.g. when Supabase is uninitialized under tests) and only
  /// notifies when it actually replaces the cache with live rows.
  Future<void> load() async {
    try {
      final rows = await supabase
          .from('posts')
          .select('*, profiles(*)')
          .order('created_at', ascending: false);
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return; // keep the mock seed as a graceful fallback
      final mapped = data.map(_postFromRow).toList();
      _posts
        ..clear()
        ..addAll(mapped);
      notifyListeners();
    } catch (_) {
      // Supabase unavailable/unauthenticated or query failed: keep the mock
      // seed. Never throw into construction or the UI.
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
    _persistRepostCount(updated);
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

  /// Reflects a repost toggle into the post's `repost_count`.
  ///
  /// Known limitation: unlike likes, there is no `reposts` join table, so this
  /// counter is client-authoritative and can drift under concurrent clients
  /// (last-writer-wins). A production version should add a `reposts` join
  /// table plus a trigger mirroring `sync_post_like_count`, and stop writing
  /// `repost_count` from the client. Kept as-is for this pass to avoid
  /// expanding the schema/scope; documented in the migration and README.
  Future<void> _persistRepostCount(Post post) async {
    try {
      await supabase
          .from('posts')
          .update(<String, dynamic>{'repost_count': post.repostCount})
          .eq('id', post.id);
    } catch (_) {
      // Ignore persistence failures.
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

  // -- Mapping -------------------------------------------------------------

  /// Maps a `posts` row (with a joined `profiles(*)` object) to a [Post].
  Post _postFromRow(Map<String, dynamic> row) {
    return Post(
      id: row['id']?.toString() ?? '',
      author: _authorFromRow(row['profiles']),
      content: (row['content'] as String?) ?? '',
      mediaUrl: row['media_url'] as String?,
      mediaType: _mediaTypeFromName(row['media_type'] as String?),
      createdAt: _parseDate(row['created_at']),
      replyCount: _asInt(row['reply_count']),
      repostCount: _asInt(row['repost_count']),
      likeCount: _asInt(row['like_count']),
      viewCount: _asInt(row['view_count']),
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
