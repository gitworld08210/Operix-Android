import 'package:flutter/material.dart';

import '../data/post_repository.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';

/// Lists the signed-in user's bookmarked posts, read from the `bookmarks`
/// table joined to `posts` + author profile via
/// [PostRepository.bookmarkedPosts]. Handles loading / empty / error states and
/// supports pull-to-refresh.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Post> _posts = const <Post>[];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final posts = await PostRepository.instance.bookmarkedPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error) {
      return _StateMessage(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        subtitle: 'We could not load your bookmarks.',
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_posts.isEmpty) {
      return const _StateMessage(
        icon: Icons.bookmark_border,
        title: 'No bookmarks yet',
        subtitle: 'Tap the bookmark icon on a post to save it here.',
      );
    }
    final repo = PostRepository.instance;
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        return ListView.builder(
          itemCount: _posts.length,
          itemBuilder: (context, index) {
            // Prefer the live cached copy so toggles reflect immediately.
            final post = repo.postById(_posts[index].id) ?? _posts[index];
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
        );
      },
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 48, color: AppColors.secondaryText),
              const SizedBox(height: 12),
              Text(title, style: AppTextStyles.title),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.handle,
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
