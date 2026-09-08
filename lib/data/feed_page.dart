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
    this.error = false,
  });

  /// The posts in this page (already ranked/ordered by the caller).
  final List<Post> posts;

  /// Cursor pointing at the last row of this page, or null when [posts] is
  /// empty. Pass it to [PostRepository.loadMore] to fetch the next page.
  ///
  /// INVARIANT: this is the KEYSET tail of the fetched page — the oldest row by
  /// `(created_at desc, id desc)` — because the query orders by that key and
  /// the last mapped row is therefore the keyset-min. Threading it back into
  /// the next [PostRepository.loadMore] makes the cursor STRICTLY MONOTONIC
  /// DECREASING across pages (each page's tail sorts strictly AFTER the
  /// previous one under [FeedCursor.compareTo]), so no row is skipped or
  /// repeated. This is deliberately DECOUPLED from the display ranking: the
  /// ranking strategy orders what is SHOWN, while this cursor always tracks the
  /// keyset frontier.
  final FeedCursor? nextCursor;

  /// Whether another page is likely available. True when a full page
  /// ([kFeedPageSize] rows) was returned.
  final bool hasMore;

  /// True when the fetch FAILED (e.g. Supabase threw) as opposed to simply
  /// running out of rows. The repository swallows fetch errors to preserve its
  /// guarded no-throw contract, so this flag is how a failed page is signalled
  /// to the UI WITHOUT throwing: an errored page carries no posts and
  /// `hasMore: true` (so the pager can offer a retry) but `error: true`.
  final bool error;

  /// An empty terminal page (no posts, no more pages).
  static const FeedPage empty = FeedPage(posts: <Post>[]);

  /// A failed page (no posts fetched, more may still exist, error signalled).
  /// The pager renders a retry affordance and can re-arm the fetch.
  static const FeedPage failure =
      FeedPage(posts: <Post>[], hasMore: true, error: true);
}

/// The distinct footer states an infinite-scroll feed can render below its
/// rows, chosen by the pure [footerStateFor] decision function so the choice is
/// unit-testable without a device or golden.
enum FeedFooterState {
  /// The feed is empty (no rows at all) — the caller shows its empty state, not
  /// a footer.
  empty,

  /// A next-page fetch is in flight — show a spinner as the last list item.
  loadingNext,

  /// The last fetch failed — show an inline "Couldn't load more — Retry".
  error,

  /// No more pages remain and the feed is non-empty — show "You're all caught
  /// up".
  endOfFeed,

  /// More pages remain and nothing is in flight — show no footer (a fetch will
  /// be triggered by scrolling / prefetch).
  idle,
}

/// Pure decision for which [FeedFooterState] a feed footer should render.
///
/// Precedence, evaluated top-down:
///  1. [isEmpty] -> [FeedFooterState.empty] (the list has no rows; the caller
///     renders its dedicated empty view instead of a footer).
///  2. [hasError] -> [FeedFooterState.error] (a failed fetch takes priority so
///     the user is always offered a retry, even while `loadingMore` briefly
///     overlaps a retry attempt is guarded elsewhere).
///  3. [loadingMore] -> [FeedFooterState.loadingNext].
///  4. `!hasMore` -> [FeedFooterState.endOfFeed] (non-empty here, per rule 1).
///  5. otherwise -> [FeedFooterState.idle].
///
/// Extracted from the widget so the state machine is verifiable in isolation;
/// the `_FeedList` widget renders directly off the returned value.
FeedFooterState footerStateFor({
  required bool loadingMore,
  required bool hasMore,
  required bool hasError,
  required bool isEmpty,
}) {
  if (isEmpty) return FeedFooterState.empty;
  if (hasError) return FeedFooterState.error;
  if (loadingMore) return FeedFooterState.loadingNext;
  if (!hasMore) return FeedFooterState.endOfFeed;
  return FeedFooterState.idle;
}
