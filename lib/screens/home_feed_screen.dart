import 'package:flutter/material.dart';

import '../data/feed_page.dart';
import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/story_ring.dart';
import 'comments_screen.dart';
import 'compose_screen.dart';

/// Home timeline with 'For You' / 'Following' tabs, wired to
/// [PostRepository.instance].
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ProfileRepository.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => openProfile(context),
            child: Center(
              child: Avatar(
                url: currentUser.avatarUrl,
                displayName: currentUser.displayName,
                size: 32,
              ),
            ),
          ),
        ),
        title: const Text('Oneleven'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.accent,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: AppColors.primaryText,
              unselectedLabelColor: AppColors.secondaryText,
              labelStyle: AppTextStyles.label,
              tabs: const <Widget>[
                Tab(text: 'For you'),
                Tab(text: 'Following'),
              ],
            ),
          ),
        ),
      ),
      // The story ring sits ABOVE the TabBarView (rendered once for both tabs)
      // so it never interferes with the infinite-scroll ListView pagination in
      // either feed. It manages its own AnimatedBuilder over StoryRepository.
      body: Column(
        children: <Widget>[
          const StoryRing(),
          Expanded(
            child: AnimatedBuilder(
              animation: PostRepository.instance,
              builder: (context, _) {
                return TabBarView(
                  controller: _tabController,
                  children: const <Widget>[
                    _FeedList(feed: _FeedKind.forYou),
                    _FeedList(feed: _FeedKind.following),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Which timeline a [_FeedList] renders.
enum _FeedKind { forYou, following }

/// A scrollable feed that renders one timeline and fetches the next keyset page
/// as the user nears the bottom (infinite scroll).
///
/// The list itself is driven by [PostRepository]'s in-memory cache via the
/// [AnimatedBuilder] in the parent; when [PostRepository.loadMore] appends a
/// fresh keyset page it notifies listeners and the list rebuilds with the new
/// rows. Pagination is guarded end-to-end: `loadMore` is a no-op returning
/// [FeedPage.empty] when Supabase is unavailable (tests/offline), so this stays
/// a pure display concern and never throws into the UI.
class _FeedList extends StatefulWidget {
  const _FeedList({required this.feed});

  final _FeedKind feed;

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  final ScrollController _scrollController = ScrollController();

  /// True while a page fetch is in flight, so overlapping scroll/prefetch
  /// events don't trigger duplicate page fetches.
  bool _loadingMore = false;

  /// False once a page returns with no more rows, so we stop querying.
  bool _hasMore = true;

  /// True when the last page fetch FAILED (as opposed to reaching the end);
  /// drives the inline retry footer. Cleared when a retry is armed.
  bool _hasError = false;

  /// The TRUE keyset frontier (oldest loaded row by `created_at desc, id desc`)
  /// for THIS tab. Seeded from [PostRepository.keysetMinCursor] over the
  /// initial cache, then set from each fetched [FeedPage.nextCursor]. Paging
  /// off this — NOT the ranked display tail — decouples the pagination cursor
  /// from the display ranking, so a non-chronological strategy
  /// (EngagementRanking) cannot corrupt pagination.
  FeedCursor? _cursor;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // After the first frame, kick an initial prefetch if the first page
    // under-fills the viewport (so a short first page still becomes endless).
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfNeeded());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  List<Post> _posts() {
    final repo = PostRepository.instance;
    return widget.feed == _FeedKind.forYou ? repo.forYou() : repo.following();
  }

  /// The cursor to page off: the threaded keyset frontier once set, else the
  /// keyset-min of the current cache (NOT the ranked display tail).
  FeedCursor? _pageCursor() {
    return _cursor ?? PostRepository.keysetMinCursor(_posts());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Trigger a page fetch when within ~600px of the bottom (prefetch).
    if (position.pixels >= position.maxScrollExtent - 600) {
      // ignore: discarded_futures
      _maybeLoadMore();
    }
  }

  /// Prefetch the next page when the initial page doesn't fill the viewport, so
  /// a short first page still becomes an endless feed instead of stalling.
  void _prefetchIfNeeded() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) {
      // ignore: discarded_futures
      _maybeLoadMore();
    }
  }

  /// Routes to the tab's page fetcher: For You uses the global [loadMore],
  /// Following uses the author-scoped [loadMoreFollowing].
  Future<FeedPage> _fetch(FeedCursor cursor) {
    final repo = PostRepository.instance;
    return widget.feed == _FeedKind.forYou
        ? repo.loadMore(cursor)
        : repo.loadMoreFollowing(cursor);
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore || !_hasMore || _hasError) return;
    final cursor = _pageCursor();
    if (cursor == null) return; // empty feed: nothing to page off
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(cursor);
      if (!mounted) return;
      setState(() {
        if (page.error) {
          // Fetch failed: surface a retry without advancing the cursor.
          _hasError = true;
        } else {
          // Advance the keyset frontier to the fetched page's tail (strictly
          // monotonic decreasing), and stop when the page under-filled.
          if (page.nextCursor != null) _cursor = page.nextCursor;
          _hasMore = page.hasMore;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  /// Re-arms pagination after an error (retry footer tap).
  void _retry() {
    setState(() => _hasError = false);
    // ignore: discarded_futures
    _maybeLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts();
    final footer = footerStateFor(
      loadingMore: _loadingMore,
      hasMore: _hasMore,
      hasError: _hasError,
      isEmpty: posts.isEmpty,
    );
    if (footer == FeedFooterState.empty) {
      return _EmptyFeed(feed: widget.feed);
    }
    final repo = PostRepository.instance;
    final hasFooter = footer != FeedFooterState.idle;
    return ListView.builder(
      controller: _scrollController,
      // One extra slot for the footer state widget when there is one.
      itemCount: posts.length + (hasFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= posts.length) {
          return _FeedFooter(state: footer, onRetry: _retry);
        }
        final post = posts[index];
        return PostCard(
          post: post,
          onLike: () => repo.toggleLike(post.id),
          onReact: (type) => repo.react(post.id, type),
          onClearReaction: () => repo.clearReaction(post.id),
          onRepost: () => repo.toggleRepost(post.id),
          onBookmark: () => repo.toggleBookmark(post.id),
          onReply: () => _openComments(context, post),
          onShare: () => _snack(context, 'Share sheet coming soon'),
          onTap: () => _openComments(context, post),
          onQuotedTap: post.quotedPost != null
              ? () => _openComments(context, post.quotedPost!)
              : null,
          onQuote: () => _openQuoteCompose(context, post),
          onAuthorTap: () {},
        );
      },
    );
  }

  void _openComments(BuildContext context, Post post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommentsScreen(post: post),
      ),
    );
  }

  /// Opens the composer pre-attached to [post] as a QUOTE-POST.
  void _openQuoteCompose(BuildContext context, Post post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ComposeScreen(quoted: post),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.feed});

  final _FeedKind feed;

  @override
  Widget build(BuildContext context) {
    // Per-tab copy: For You is a general "nothing yet", Following nudges the
    // user to follow more people.
    final isFollowing = feed == _FeedKind.following;
    final title = isFollowing ? 'No posts yet' : 'Nothing here yet';
    final subtitle = isFollowing
        ? 'Posts from people you follow will show up here.'
        : 'When there are new posts, they will show up here.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.forum_outlined,
                size: 48, color: AppColors.secondaryText),
            const SizedBox(height: 12),
            Text(
              title,
              style: AppTextStyles.title,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
          ],
        ),
      ),
    );
  }
}

/// The footer rendered below the feed rows for the non-empty footer states:
/// a spinner while loading the next page, a "caught up" note at the end of the
/// feed, or an inline retry after a failed fetch. Driven by [footerStateFor].
class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.state, required this.onRetry});

  final FeedFooterState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case FeedFooterState.loadingNext:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case FeedFooterState.endOfFeed:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              "You're all caught up",
              style: AppTextStyles.handle,
            ),
          ),
        );
      case FeedFooterState.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  "Couldn't load more",
                  style: AppTextStyles.handle,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      case FeedFooterState.empty:
      case FeedFooterState.idle:
        // These states never render a footer row (the caller renders the empty
        // view for `empty` and no footer slot for `idle`).
        return const SizedBox.shrink();
    }
  }
}
