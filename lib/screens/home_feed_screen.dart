import 'package:flutter/material.dart';

import '../data/load_status.dart';
import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';

/// Home timeline with 'For You' / 'Following' tabs, wired to
/// [PostRepository.instance] with real loading / empty / error states and
/// pull-to-refresh.
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: AnimatedBuilder(
            animation: ProfileRepository.instance,
            builder: (context, _) {
              final currentUser = ProfileRepository.instance.currentUser;
              return GestureDetector(
                onTap: () => openProfile(context),
                child: Center(
                  child: Avatar(
                    url: currentUser?.avatarUrl,
                    displayName: currentUser?.displayName ?? 'You',
                    size: 32,
                  ),
                ),
              );
            },
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
      body: AnimatedBuilder(
        animation: PostRepository.instance,
        builder: (context, _) {
          final repo = PostRepository.instance;
          return TabBarView(
            controller: _tabController,
            children: <Widget>[
              _FeedTab(
                posts: repo.forYou(),
                status: repo.status,
                emptyKind: _EmptyKind.forYou,
              ),
              _FeedTab(
                posts: repo.following(),
                status: repo.status,
                emptyKind: _EmptyKind.following,
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _EmptyKind { forYou, following }

class _FeedTab extends StatelessWidget {
  const _FeedTab({
    required this.posts,
    required this.status,
    required this.emptyKind,
  });

  final List<Post> posts;
  final LoadStatus status;
  final _EmptyKind emptyKind;

  Future<void> _refresh() => PostRepository.instance.load();

  @override
  Widget build(BuildContext context) {
    // Loading with nothing to show yet: centered spinner.
    if (status == LoadStatus.loading && posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    // Error with nothing to show: message + Retry.
    if (status == LoadStatus.error && posts.isEmpty) {
      return _FeedError(onRetry: _refresh);
    }

    // Loaded/idle but empty.
    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: _EmptyFeed(kind: emptyKind),
          ),
        ),
      );
    }

    final repo = PostRepository.instance;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accent,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          return PostCard(
            post: post,
            onLike: () => repo.toggleLike(post.id),
            onRepost: () => repo.toggleRepost(post.id),
            onBookmark: () => repo.toggleBookmark(post.id),
            onReply: () => openPostDetail(context, post, focusReply: true),
            onShare: () => sharePost(context, post),
            onTap: () => openPostDetail(context, post),
            onAuthorTap: () => openAuthorProfile(context, post.author.id),
          );
        },
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.secondaryText),
            const SizedBox(height: 12),
            Text('Could not load your feed', style: AppTextStyles.title),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.kind});

  final _EmptyKind kind;

  @override
  Widget build(BuildContext context) {
    final isFollowing = kind == _EmptyKind.following;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isFollowing ? Icons.people_outline : Icons.forum_outlined,
              size: 48,
              color: AppColors.secondaryText,
            ),
            const SizedBox(height: 12),
            Text(
              isFollowing ? 'Nothing here yet' : 'Your feed is empty',
              style: AppTextStyles.title,
            ),
            const SizedBox(height: 6),
            Text(
              isFollowing
                  ? 'Posts from people you follow will show up here.'
                  : 'Be the first to post something. Pull down to refresh.',
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
          ],
        ),
      ),
    );
  }
}
