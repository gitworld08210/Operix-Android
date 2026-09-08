import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/verified_badge.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';

/// Profile screen with a banner, overlapping avatar, bio + counts, and
/// Posts / Media tabs.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
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

  bool get _isCurrentUser =>
      widget.profile.id == ProfileRepository.instance.currentUser.id;

  List<Post> get _userPosts => PostRepository.instance
      .forYou()
      .where((p) => p.author.id == widget.profile.id)
      .toList();

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _openEditProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()),
    );
  }

  Future<void> _signOut() async {
    try {
      await AuthRepository.instance.signOut();
      // The AuthGate listens to auth state and returns to AuthScreen,
      // so no manual navigation is required here.
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not sign out. Please try again.'),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      body: AnimatedBuilder(
        animation: PostRepository.instance,
        builder: (context, _) {
          final posts = _userPosts;
          final media = posts.where((p) => p.hasMedia).toList();
          return NestedScrollView(
            headerSliverBuilder: (context, _) => <Widget>[
              SliverAppBar(
                pinned: true,
                title: Text(profile.displayName),
                actions: <Widget>[
                  if (_isCurrentUser) ...<Widget>[
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: _openSettings,
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(Icons.logout),
                      onPressed: _signOut,
                    ),
                  ],
                ],
                expandedHeight: 140,
                flexibleSpace: FlexibleSpaceBar(
                  background: _Banner(url: profile.bannerUrl),
                ),
              ),
              SliverToBoxAdapter(
                child: _ProfileHeader(
                  profile: profile,
                  isCurrentUser: _isCurrentUser,
                  onEditProfile: _openEditProfile,
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.accent,
                    indicatorWeight: 3,
                    labelColor: AppColors.primaryText,
                    unselectedLabelColor: AppColors.secondaryText,
                    labelStyle: AppTextStyles.label,
                    tabs: const <Widget>[
                      Tab(text: 'Posts'),
                      Tab(text: 'Media'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _PostsTab(posts: posts),
                _MediaGrid(posts: media),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final bannerUrl = url;
    if (bannerUrl == null || bannerUrl.isEmpty) {
      return const ColoredBox(color: AppColors.surface);
    }
    return Image.network(
      bannerUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const ColoredBox(color: AppColors.surface);
      },
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: AppColors.surface),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isCurrentUser,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final bool isCurrentUser;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Transform.translate(
            offset: const Offset(0, -32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Avatar(
                  url: profile.avatarUrl,
                  displayName: profile.displayName,
                  size: 72,
                  ring: true,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  // For the current user this opens the Edit profile flow
                  // (display name + bio), which persists through
                  // ProfileRepository.instance.updateProfile.
                  //
                  // TODO(avatar-upload): the edit flow can later update the
                  // avatar via StorageService.uploadAvatar once an image byte
                  // source is wired (no image_picker dependency is bundled, to
                  // keep deps minimal).
                  child: OutlinedButton(
                    onPressed: isCurrentUser ? onEditProfile : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      side: const BorderSide(color: AppColors.border),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(isCurrentUser ? 'Edit profile' : 'Follow'),
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.display,
                      ),
                    ),
                    if (profile.verified) ...<Widget>[
                      const SizedBox(width: 6),
                      VerifiedBadge(kind: profile.verificationKind, size: 20),
                    ],
                  ],
                ),
                Text(profile.handle, style: AppTextStyles.handle),
                if (profile.bio.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(profile.bio, style: AppTextStyles.body),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    _Count(value: profile.following, label: 'Following'),
                    const SizedBox(width: AppSpacing.lg),
                    _Count(value: profile.followers, label: 'Followers'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          TextSpan(
            text: fmtCount(value),
            style: AppTextStyles.label.copyWith(color: AppColors.primaryText),
          ),
          TextSpan(text: ' $label', style: AppTextStyles.handle),
        ],
      ),
    );
  }
}

class _PostsTab extends StatelessWidget {
  const _PostsTab({required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Text('No posts yet', style: AppTextStyles.handle),
      );
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
        );
      },
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Text('No media yet', style: AppTextStyles.handle),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final url = posts[index].mediaUrl!;
        return Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const ColoredBox(color: AppColors.surface);
          },
          errorBuilder: (context, error, stackTrace) => const ColoredBox(
            color: AppColors.surface,
            child: Icon(Icons.broken_image_outlined,
                color: AppColors.secondaryText),
          ),
        );
      },
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}
