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

  /// True while a [PostRepository.loadMore] fetch is in flight, so overlapping
  /// scroll events don't trigger duplicate page fetches.
  bool _loadingMore = false;

  /// False once a page returns with no more rows, so we stop querying.
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Trigger a page fetch when within ~600px of the bottom.
    if (position.pixels >= position.maxScrollExtent - 600) {
      // ignore: discarded_futures
      _maybeLoadMore();
    }
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore || !_hasMore) return;
    final posts = _posts();
    if (posts.isEmpty) return;
    _loadingMore = true;
    try {
      final cursor = FeedCursor.fromPost(posts.last);
      final page = await PostRepository.instance.loadMore(cursor);
      // A page smaller than the bound (or empty) means we've reached the end.
      if (!page.hasMore && mounted) {
        setState(() => _hasMore = false);
      }
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts();
    if (posts.isEmpty) {
      return const _EmptyFeed();
    }
    final repo = PostRepository.instance;
    return ListView.builder(
      controller: _scrollController,
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return PostCard(
          post: post,
          onLike: () => repo.toggleLike(post.id),
          onRepost: () => repo.toggleRepost(post.id),
          onBookmark: () => repo.toggleBookmark(post.id),
          onReply: () => _openComments(context, post),
          onShare: () => _snack(context, 'Share sheet coming soon'),
          onTap: () => _openComments(context, post),
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

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
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
              'Nothing here yet',
              style: AppTextStyles.title,
            ),
            const SizedBox(height: 6),
            Text(
              'Posts from people you follow will show up here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
          ],
        ),
      ),
    );
  }
}
