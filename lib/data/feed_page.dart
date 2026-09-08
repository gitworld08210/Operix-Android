import '../models/post.dart';

/// The single, shared bounded page size for feed queries.
///
/// Defined once so no unbounded `select` and no scattered magic numbers creep
/// in. Every feed query (initial [PostRepository.load] and
/// [PostRepository.loadMore]) is capped at this many rows.
const int kFeedPageSize = 20;

/// An immutable keyset-pagination cursor pointing at the last row of a page.
///
/// Keyset (a.k.a. seek) pagination beats offset pagination at scale: instead of
/// `offset N` (which the database must scan past), the next page is fetched
/// with a `(created_at, id) < (:createdAt, :id)` predicate over an index on
/// `(created_at desc, id)`. `id` is the stable tie-breaker so rows sharing a
/// `created_at` are never skipped or duplicated across pages.
class FeedCursor {
  const FeedCursor({required this.createdAt, required this.id});

  /// Builds the cursor that points at [post] (the last item of a page).
  factory FeedCursor.fromPost(Post post) =>
      FeedCursor(createdAt: post.createdAt, id: post.id);

  /// Timestamp of the last row on the previous page.
  final DateTime createdAt;

  /// Id of the last row on the previous page (tie-breaker).
  final String id;

  /// Ordering used by the feed: newest-first, with `id` descending as the
  /// tie-breaker. Returns negative when `this` sorts before [other] (i.e. this
  /// is newer / earlier in the feed), positive when after, 0 when equal.
  int compareTo(FeedCursor other) {
    final byTime = other.createdAt.compareTo(createdAt);
    if (byTime != 0) return byTime;
    return other.id.compareTo(id);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeedCursor &&
          other.createdAt == createdAt &&
          other.id == id);

  @override
  int get hashCode => Object.hash(createdAt, id);

  @override
  String toString() => 'FeedCursor($createdAt, $id)';
}

/// An immutable page of feed [posts] plus the cursor for the next page.
class FeedPage {
  const FeedPage({
    required this.posts,
    this.nextCursor,
    this.hasMore = false,
  });

  /// The posts in this page (already ranked/ordered by the caller).
  final List<Post> posts;

  /// Cursor pointing at the last row of this page, or null when [posts] is
  /// empty. Pass it to [PostRepository.loadMore] to fetch the next page.
  final FeedCursor? nextCursor;

  /// Whether another page is likely available. True when a full page
  /// ([kFeedPageSize] rows) was returned.
  final bool hasMore;

  /// An empty terminal page (no posts, no more pages).
  static const FeedPage empty = FeedPage(posts: <Post>[]);
}
