import 'package:flutter/material.dart';

import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
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
      body: AnimatedBuilder(
        animation: PostRepository.instance,
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: <Widget>[
              _FeedList(posts: PostRepository.instance.forYou()),
              _FeedList(posts: PostRepository.instance.following()),
            ],
          );
        },
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const _FeedList({required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const _EmptyFeed();
    }
    final repo = PostRepository.instance;
    return ListView.builder(
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
