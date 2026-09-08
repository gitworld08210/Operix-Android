import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../data/relationship_repository.dart';
import '../data/safety_repository.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/report_sheet.dart';
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

  void _snack(String message, {VoidCallback? undo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          action: undo == null
              ? null
              : SnackBarAction(
                  label: 'Undo',
                  textColor: AppColors.accent,
                  onPressed: undo,
                ),
        ),
      );
  }

  Future<void> _onSafetyAction(String value) async {
    final safety = SafetyRepository.instance;
    final profile = widget.profile;
    switch (value) {
      case 'mute':
        safety.mute(profile.id);
        _snack('Muted @${profile.username}', undo: () => safety.unmute(profile.id));
      case 'unmute':
        safety.unmute(profile.id);
        _snack('Unmuted @${profile.username}');
      case 'block':
        safety.block(profile.id);
        _snack('Blocked @${profile.username}', undo: () => safety.unblock(profile.id));
      case 'unblock':
        safety.unblock(profile.id);
        _snack('Unblocked @${profile.username}');
      case 'report':
        await showReportSheet(
          context,
          targetType: 'profile',
          targetId: profile.id,
          targetLabel: '@${profile.username}',
        );
    }
  }

  void _onFollowTap() {
    final rel = RelationshipRepository.instance;
    final profile = widget.profile;
    final state = rel.followStateFor(profile.id);
    if (state == FollowState.none) {
      rel.follow(profile);
      _snack(
        profile.isPrivate
            ? 'Requested to follow @${profile.username}'
            : 'Following @${profile.username}',
        undo: () => rel.unfollow(profile.id),
      );
    } else {
      // Following or Requested -> unfollow / cancel the request.
      rel.unfollow(profile.id);
      _snack(
        state == FollowState.requested
            ? 'Request cancelled'
            : 'Unfollowed @${profile.username}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          PostRepository.instance,
          SafetyRepository.instance,
          RelationshipRepository.instance,
        ]),
        builder: (context, _) {
          final posts = _userPosts;
          final media = posts.where((p) => p.hasMedia).toList();
          final isBlocked = SafetyRepository.instance.isBlocked(profile.id);
          final isMuted = SafetyRepository.instance.isMuted(profile.id);
          final followState =
              RelationshipRepository.instance.followStateFor(profile.id);
          // A private account's content is gated until the viewer's follow is
          // accepted. This is a UX mirror of the server's can_view_profile
          // gate (migration 0002), which is the TRUE enforcement.
          final isPrivateGated = !_isCurrentUser &&
              profile.isPrivate &&
              followState != FollowState.following;
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
                  ] else
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_horiz),
                      color: AppColors.surface,
                      onSelected: _onSafetyAction,
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: isMuted ? 'unmute' : 'mute',
                          child: Text(isMuted ? 'Unmute' : 'Mute'),
                        ),
                        PopupMenuItem<String>(
                          value: isBlocked ? 'unblock' : 'block',
                          child: Text(isBlocked ? 'Unblock' : 'Block'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'report',
                          child: Text('Report'),
                        ),
                      ],
                    ),
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
                  isBlocked: isBlocked,
                  followState: followState,
                  onEditProfile: _openEditProfile,
                  onFollowTap: _onFollowTap,
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
            body: isPrivateGated
                ? const _PrivateAccountGate()
                : TabBarView(
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
    required this.isBlocked,
    required this.followState,
    required this.onEditProfile,
    required this.onFollowTap,
  });

  final UserProfile profile;
  final bool isCurrentUser;
  final bool isBlocked;
  final FollowState followState;
  final VoidCallback onEditProfile;
  final VoidCallback onFollowTap;

  String get _followLabel {
    switch (followState) {
      case FollowState.none:
        return 'Follow';
      case FollowState.requested:
        return 'Requested';
      case FollowState.following:
        return 'Following';
    }
  }

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
                    onPressed: isCurrentUser
                        ? onEditProfile
                        : (isBlocked ? null : onFollowTap),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      side: const BorderSide(color: AppColors.border),
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (!isCurrentUser &&
                            !isBlocked &&
                            profile.isPrivate &&
                            followState != FollowState.following) ...<Widget>[
                          const Icon(Icons.lock_outline, size: 15),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          isCurrentUser
                              ? 'Edit profile'
                              : (isBlocked ? 'Blocked' : _followLabel),
                        ),
                      ],
                    ),
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
                if (isBlocked) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Text(
                      'You have blocked this account. Their posts are hidden '
                      'from your feed.',
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
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
          onReact: (type) => repo.react(post.id, type),
          onClearReaction: () => repo.clearReaction(post.id),
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

/// Shown in place of the tab content when a private account has not accepted
/// the viewer's follow. This is a UX mirror of the server-side
/// `can_view_profile` gate (migration 0002), which is the true enforcement.
class _PrivateAccountGate extends StatelessWidget {
  const _PrivateAccountGate();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.lock_outline,
              size: 44,
              color: AppColors.secondaryText,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('This account is private', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Follow this account to see their posts and media.',
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
          ],
        ),
      ),
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
