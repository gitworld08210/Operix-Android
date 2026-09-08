import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import '../utils/ids.dart';
import 'load_status.dart';
import 'notification_repository.dart';

/// The post store for the app, fully backed by Supabase (no mock fallback).
///
/// A [ChangeNotifier] singleton (`PostRepository.instance`) so screens listen
/// via `AnimatedBuilder(animation: PostRepository.instance)`. The cache starts
/// empty with [status] == [LoadStatus.idle]; call [load] after sign-in to fill
/// it and [clear] on sign-out. [status] exposes the real loading/loaded/error
/// state so the UI can render spinners, empty states, and errors instead of
/// fabricated data.
///
/// Engagement mutations (`toggleLike`, `toggleRepost`, `toggleBookmark`) update
/// the cache optimistically for a snappy UI, then write to the corresponding
/// join table (`likes` / `reposts` / `bookmarks`). On failure they revert the
/// optimistic change and surface it via [lastError]. The DB-owned counters
/// (`like_count` / `repost_count` / `reply_count`) are trigger-maintained and
/// are NEVER written from the client.
class PostRepository extends ChangeNotifier {
  PostRepository();

  /// Shared singleton for the app.
  static final PostRepository instance = PostRepository();

  final List<Post> _posts = <Post>[];
  final Set<String> _followingIds = <String>{};
  LoadStatus _status = LoadStatus.idle;
  Object? _error;
  Object? _lastError;

  /// The current load state of the timeline.
  LoadStatus get status => _status;

  /// The most recent load error, if [status] is [LoadStatus.error].
  Object? get error => _error;

  /// The most recent mutation error (e.g. a failed like), for surfacing a
  /// transient message. Cleared at the start of each mutation.
  Object? get lastError => _lastError;

  /// The set of author ids the current user follows (populated by [load] /
  /// [loadFollowing]).
  Set<String> get followingIds => Set<String>.unmodifiable(_followingIds);

  /// The "For you" timeline (all top-level posts, newest first).
  List<Post> forYou() {
    final list = List<Post>.of(_posts)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<Post>.unmodifiable(list);
  }

  /// The "Following" timeline: top-level posts by authors the current user
  /// actually follows, newest first.
  List<Post> following() {
    final list = _posts
        .where((p) => _followingIds.contains(p.author.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<Post>.unmodifiable(list);
  }

  /// Loads the main feed (top-level posts only, replies excluded) from
  /// Supabase, then hydrates the current user's follow set and engagement
  /// flags. Sets [status] and notifies in every outcome. Never throws.
  Future<void> load() async {
    _status = LoadStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final rows = await supabase
          .from('posts')
          .select('*, profiles(*)')
          .isFilter('parent_id', null)
          .order('created_at', ascending: false);
      final data = (rows as List).cast<Map<String, dynamic>>();
      _posts
        ..clear()
        ..addAll(data.map(_postFromRow));

      await loadFollowing();
      await _hydrateEngagement();

      _status = LoadStatus.loaded;
      notifyListeners();
    } catch (e) {
      _error = e;
      _status = LoadStatus.error;
      notifyListeners();
    }
  }

  /// Loads (into [_followingIds]) the set of author ids the current user
  /// follows. Safe to call independently; guarded.
  Future<void> loadFollowing() async {
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) {
        _followingIds.clear();
        return;
      }
      final rows = await supabase
          .from('follows')
          .select('followee')
          .eq('follower', myId);
      final data = (rows as List).cast<Map<String, dynamic>>();
      _followingIds
        ..clear()
        ..addAll(
          data
              .map((r) => r['followee']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
    } catch (_) {
      // Leave the current set; following() simply shows what we know.
    }
  }

  /// Hydrates `liked` / `reposted` / `bookmarked` flags on the cached posts
  /// from the current user's rows in `likes` / `reposts` / `bookmarks`.
  Future<void> _hydrateEngagement() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final likeRows = await supabase
          .from('likes')
          .select('post_id')
          .eq('user_id', myId);
      final repostRows = await supabase
          .from('reposts')
          .select('post_id')
          .eq('user_id', myId);
      final bookmarkRows = await supabase
          .from('bookmarks')
          .select('post_id')
          .eq('user_id', myId);

      final liked = _idSet(likeRows);
      final reposted = _idSet(repostRows);
      final bookmarked = _idSet(bookmarkRows);

      for (var i = 0; i < _posts.length; i++) {
        final p = _posts[i];
        _posts[i] = p.copyWith(
          liked: liked.contains(p.id),
          reposted: reposted.contains(p.id),
          bookmarked: bookmarked.contains(p.id),
        );
      }
    } catch (_) {
      // Keep whatever flags mapped from the rows; not fatal.
    }
  }

  int _indexOf(String id) => _posts.indexWhere((p) => p.id == id);

  /// Toggles the like state, writing to the `likes` join table. Optimistic;
  /// reverts and records [lastError] on failure. Returns the updated post or
  /// null for an unknown id.
  Future<Post?> toggleLike(String id) async {
    _lastError = null;
    final i = _indexOf(id);
    if (i < 0) return null;
    final original = _posts[i];
    final nowLiked = !original.liked;
    final optimistic = original.copyWith(
      liked: nowLiked,
      likeCount: original.likeCount + (nowLiked ? 1 : -1),
    );
    _posts[i] = optimistic;
    notifyListeners();

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('Not signed in');
      if (nowLiked) {
        await supabase.from('likes').insert(<String, dynamic>{
          'user_id': userId,
          'post_id': id,
        });
        await NotificationRepository.instance.createNotification(
          recipient: original.author.id,
          type: NotificationType.like,
          postId: id,
          preview: _previewOf(original),
        );
      } else {
        await supabase
            .from('likes')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', id);
      }
      return optimistic;
    } catch (e) {
      _revert(id, original);
      _lastError = e;
      notifyListeners();
      return null;
    }
  }

  /// Toggles the repost state, writing to the `reposts` join table (NOT the
  /// `repost_count` counter, which the DB owns). Optimistic; reverts on
  /// failure.
  Future<Post?> toggleRepost(String id) async {
    _lastError = null;
    final i = _indexOf(id);
    if (i < 0) return null;
    final original = _posts[i];
    final nowReposted = !original.reposted;
    final optimistic = original.copyWith(
      reposted: nowReposted,
      repostCount: original.repostCount + (nowReposted ? 1 : -1),
    );
    _posts[i] = optimistic;
    notifyListeners();

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('Not signed in');
      if (nowReposted) {
        await supabase.from('reposts').insert(<String, dynamic>{
          'user_id': userId,
          'post_id': id,
        });
        await NotificationRepository.instance.createNotification(
          recipient: original.author.id,
          type: NotificationType.repost,
          postId: id,
          preview: _previewOf(original),
        );
      } else {
        await supabase
            .from('reposts')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', id);
      }
      return optimistic;
    } catch (e) {
      _revert(id, original);
      _lastError = e;
      notifyListeners();
      return null;
    }
  }

  /// Toggles the bookmark state, writing to the private `bookmarks` table.
  /// Optimistic; reverts on failure.
  Future<Post?> toggleBookmark(String id) async {
    _lastError = null;
    final i = _indexOf(id);
    if (i < 0) return null;
    final original = _posts[i];
    final optimistic = original.copyWith(bookmarked: !original.bookmarked);
    _posts[i] = optimistic;
    notifyListeners();

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw StateError('Not signed in');
      if (optimistic.bookmarked) {
        await supabase.from('bookmarks').insert(<String, dynamic>{
          'user_id': userId,
          'post_id': id,
        });
      } else {
        await supabase
            .from('bookmarks')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', id);
      }
      return optimistic;
    } catch (e) {
      _revert(id, original);
      _lastError = e;
      notifyListeners();
      return null;
    }
  }

  /// Returns the cached top-level post with [id], or null if not loaded.
  Post? postById(String id) {
    final i = _indexOf(id);
    return i < 0 ? null : _posts[i];
  }

  /// Fetches a single post by [id] (joining the author profile), preferring
  /// the in-memory cache when present so engagement flags stay consistent.
  /// Used to open a post detail from a notification whose post may not be in
  /// the feed cache. Returns null when missing or on failure.
  Future<Post?> fetchPostById(String id) async {
    final cached = postById(id);
    if (cached != null) return cached;
    try {
      final row = await supabase
          .from('posts')
          .select('*, profiles(*)')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      final posts = <Post>[_postFromRow(row)];
      _applyEngagementFlags(posts);
      return posts.first;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the top-level posts authored by [ownerId] (newest first), joining
  /// the author profile. Used by the profile screen for any user. Returns an
  /// empty list on failure.
  Future<List<Post>> postsByOwner(String ownerId) async {
    try {
      final rows = await supabase
          .from('posts')
          .select('*, profiles(*)')
          .eq('owner', ownerId)
          .isFilter('parent_id', null)
          .order('created_at', ascending: false);
      final data = (rows as List).cast<Map<String, dynamic>>();
      final posts = data.map(_postFromRow).toList();
      _applyEngagementFlags(posts);
      return posts;
    } catch (_) {
      return const <Post>[];
    }
  }

  /// Fetches the current user's bookmarked posts (newest bookmark first),
  /// joining the author profile. Returns an empty list on failure.
  Future<List<Post>> bookmarkedPosts() async {
    try {
      final myId = supabase.auth.currentUser?.id;
      if (myId == null) return const <Post>[];
      final rows = await supabase
          .from('bookmarks')
          .select('created_at, posts(*, profiles(*))')
          .eq('user_id', myId)
          .order('created_at', ascending: false);
      final data = (rows as List).cast<Map<String, dynamic>>();
      final posts = <Post>[];
      for (final row in data) {
        final postRow = row['posts'];
        if (postRow is Map) {
          final p = _postFromRow(postRow.cast<String, dynamic>());
          posts.add(p.copyWith(bookmarked: true));
        }
      }
      _applyEngagementFlags(posts, forceBookmarked: true);
      return posts;
    } catch (_) {
      return const <Post>[];
    }
  }

  /// Overlays the cached engagement flags (liked/reposted/bookmarked) onto a
  /// freshly fetched list where the cache already knows the post, so
  /// off-feed lists (profile, bookmarks) render the correct toggle state.
  void _applyEngagementFlags(List<Post> posts, {bool forceBookmarked = false}) {
    for (var i = 0; i < posts.length; i++) {
      final cached = postById(posts[i].id);
      if (cached != null) {
        posts[i] = posts[i].copyWith(
          liked: cached.liked,
          reposted: cached.reposted,
          bookmarked: forceBookmarked ? true : cached.bookmarked,
        );
      }
    }
  }

  /// Returns the replies to [parentId] (posts whose `parent_id` is [parentId]),
  /// oldest first, with their authors joined. Returns an empty list on failure.
  Future<List<Post>> replies(String parentId) async {
    try {
      final rows = await supabase
          .from('posts')
          .select('*, profiles(*)')
          .eq('parent_id', parentId)
          .order('created_at', ascending: true);
      final data = (rows as List).cast<Map<String, dynamic>>();
      return data.map(_postFromRow).toList(growable: false);
    } catch (_) {
      return const <Post>[];
    }
  }

  /// Searches posts by content via the `search_posts` RPC (case-insensitive
  /// trigram / hashtag text match). The RPC returns bare `posts` rows without
  /// the joined author, so this resolves each distinct owner from the
  /// `profiles` table and attaches it. Returns an empty list on failure or for
  /// a blank query.
  Future<List<Post>> searchPosts(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const <Post>[];
    try {
      final rows = await supabase.rpc(
        'search_posts',
        params: <String, dynamic>{'q': q},
      );
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return const <Post>[];

      // Resolve authors for the distinct owners in a single query.
      final ownerIds = data
          .map((r) => r['owner']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final authors = <String, UserProfile>{};
      if (ownerIds.isNotEmpty) {
        final profileRows = await supabase
            .from('profiles')
            .select()
            .inFilter('id', ownerIds);
        final profiles = (profileRows as List).cast<Map<String, dynamic>>();
        for (final row in profiles) {
          final author = _authorFromRow(row);
          if (author.id.isNotEmpty) authors[author.id] = author;
        }
      }

      final posts = <Post>[];
      for (final row in data) {
        final ownerId = row['owner']?.toString() ?? '';
        final author = authors[ownerId] ??
            const UserProfile(id: '', username: 'user', displayName: 'User');
        posts.add(_postFromRowWithAuthor(row, author));
      }
      _applyEngagementFlags(posts);
      return posts;
    } catch (_) {
      return const <Post>[];
    }
  }

  /// Adds a reply to [parentId] with [content], owned by the current user.
  /// Inserts a `posts` row with `parent_id` set and a client-generated UUID so
  /// the returned [Post.id] equals the persisted row id. The parent's
  /// `reply_count` is DB-owned (sync_post_reply_count trigger). Also creates a
  /// reply notification for the parent's owner. Returns the mapped reply or
  /// null on failure.
  Future<Post?> addReply({
    required String parentId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;
      final id = newUuidV4();
      final inserted = await supabase
          .from('posts')
          .insert(<String, dynamic>{
            'id': id,
            'owner': userId,
            'content': trimmed,
            'parent_id': parentId,
          })
          .select('*, profiles(*)')
          .single();
      final reply = _postFromRow(inserted);

      // Bump the cached parent's reply_count optimistically if present.
      final pi = _indexOf(parentId);
      Post? parent;
      if (pi >= 0) {
        parent = _posts[pi];
        _posts[pi] = parent.copyWith(replyCount: parent.replyCount + 1);
        notifyListeners();
      }

      final parentOwner = parent?.author.id;
      if (parentOwner != null) {
        await NotificationRepository.instance.createNotification(
          recipient: parentOwner,
          type: NotificationType.reply,
          postId: parentId,
          preview: trimmed,
        );
      }
      return reply;
    } catch (_) {
      return null;
    }
  }

  /// Adds a newly composed top-level post to the top of the timeline and
  /// persists it. Optimistic; removes it and records [lastError] on failure.
  Future<Post?> addPost(Post post) async {
    _lastError = null;
    _posts.insert(0, post);
    notifyListeners();
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw StateError('Not signed in');
      }
      await supabase.from('posts').insert(<String, dynamic>{
        'id': post.id,
        'owner': userId,
        'content': post.content,
        'media_url': post.mediaUrl,
        'media_type': post.mediaType.name,
      });
      return post;
    } catch (e) {
      _posts.removeWhere((p) => p.id == post.id);
      _lastError = e;
      notifyListeners();
      return null;
    }
  }

  /// Clears the cache and follow set (e.g. on sign-out).
  void clear() {
    _posts.clear();
    _followingIds.clear();
    _status = LoadStatus.idle;
    _error = null;
    _lastError = null;
    notifyListeners();
  }

  // -- Helpers -------------------------------------------------------------

  void _revert(String id, Post original) {
    final i = _indexOf(id);
    if (i >= 0) _posts[i] = original;
  }

  static String _previewOf(Post post) {
    final text = post.content.trim();
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}...';
  }

  static Set<String> _idSet(Object? rows) {
    final list = (rows as List).cast<Map<String, dynamic>>();
    return list
        .map((r) => r['post_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  // -- Mapping -------------------------------------------------------------

  Post _postFromRow(Map<String, dynamic> row) =>
      _postFromRowWithAuthor(row, _authorFromRow(row['profiles']));

  Post _postFromRowWithAuthor(Map<String, dynamic> row, UserProfile author) {
    return Post(
      id: row['id']?.toString() ?? '',
      author: author,
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
