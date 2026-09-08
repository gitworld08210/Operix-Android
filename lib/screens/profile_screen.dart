import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/message_repository.dart';
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
import 'bookmarks_screen.dart';
import 'conversation_screen.dart';
import 'post_detail_screen.dart';

/// Profile screen with a banner, overlapping avatar, bio + counts, and
/// Posts / Media tabs. Supabase-backed for ANY profile: the current user gets
/// Edit profile + a Bookmarks entry, other users get a real Follow/Following
/// button wired to [ProfileRepository.toggleFollow]. The Posts/Media tabs read
/// that profile's real posts via [PostRepository.postsByOwner].
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<Post> _posts = const <Post>[];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isCurrentUser =>
      widget.profile.id == ProfileRepository.instance.currentUser?.id;

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final posts =
          await PostRepository.instance.postsByOwner(widget.profile.id);
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

  Future<void> _editProfile() async {
    final repo = ProfileRepository.instance;
    final current = repo.currentUser;
    if (current == null) return;
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => _EditProfileSheet(profile: current),
    );
    if (result == null) return;
    await repo.updateProfile(
      displayName: result.displayName,
      bio: result.bio,
    );
  }

  void _openBookmarks() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BookmarksScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => <Widget>[
          SliverAppBar(
            pinned: true,
            title: Text(profile.displayName),
            actions: <Widget>[
              if (_isCurrentUser) ...<Widget>[
                IconButton(
                  tooltip: 'Bookmarks',
                  icon: const Icon(Icons.bookmark_border),
                  onPressed: _openBookmarks,
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
            child: AnimatedBuilder(
              animation: ProfileRepository.instance,
              builder: (context, _) {
                // Use the live cached copy for the current user so name/bio
                // edits reflect immediately.
                final live = _isCurrentUser
                    ? (ProfileRepository.instance.currentUser ?? profile)
                    : profile;
                return _ProfileHeader(
                  profile: live,
                  isCurrentUser: _isCurrentUser,
                  onEdit: _editProfile,
                );
              },
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
        body: AnimatedBuilder(
          animation: PostRepository.instance,
          builder: (context, _) {
            final repo = PostRepository.instance;
            // Reflect live toggle state onto the fetched list.
            final posts = _posts
                .map((p) => repo.postById(p.id) ?? p)
                .toList(growable: false);
            final media = posts.where((p) => p.hasMedia).toList();
            return TabBarView(
              controller: _tabController,
              children: <Widget>[
                _PostsTab(
                  posts: posts,
                  loading: _loading,
                  error: _error,
                  onRetry: _loadPosts,
                ),
                _MediaGrid(
                  posts: media,
                  loading: _loading,
                  error: _error,
                  onRetry: _loadPosts,
                ),
              ],
            );
          },
        ),
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
    required this.onEdit,
  });

  final UserProfile profile;
  final bool isCurrentUser;
  final VoidCallback onEdit;

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
                  child: isCurrentUser
                      ? _EditButton(onEdit: onEdit)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _MessageButton(targetId: profile.id),
                            const SizedBox(width: AppSpacing.sm),
                            _FollowButton(targetId: profile.id),
                          ],
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

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onEdit});

  final VoidCallback onEdit;

  // Editing name/bio persists through ProfileRepository.updateProfile.
  // Avatar upload is a documented byte-source seam: once raw bytes are picked
  // (no image_picker dependency is bundled under INTEGRATIONS_ONLY), call
  //   final userId = AuthRepository.instance.currentUser?.id;
  //   final url = await StorageService.uploadAvatar(userId: id, bytes: bytes);
  // then persist url onto profiles.avatar_url and reload. Wiring a picker is
  // the only remaining step.
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onEdit,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryText,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
      ),
      child: const Text('Edit profile'),
    );
  }
}

/// Opens (or creates) a 1:1 conversation with [targetId] and navigates to it.
/// Shown only on other users' profiles so DMs are fully user-initiated.
class _MessageButton extends StatefulWidget {
  const _MessageButton({required this.targetId});

  final String targetId;

  @override
  State<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends State<_MessageButton> {
  bool _busy = false;

  Future<void> _openConversation() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final conversationId = await MessageRepository.instance
        .openOrCreateConversationWith(widget.targetId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (conversationId == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open a conversation.')),
        );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(conversationId: conversationId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: _busy ? null : _openConversation,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryText,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
      ),
      child: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            )
          : const Text('Message'),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.targetId});

  final String targetId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProfileRepository.instance,
      builder: (context, _) {
        final following = ProfileRepository.instance.isFollowing(targetId);
        if (following) {
          return OutlinedButton(
            onPressed: () => ProfileRepository.instance.toggleFollow(targetId),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              side: const BorderSide(color: AppColors.border),
              shape: const StadiumBorder(),
            ),
            child: const Text('Following'),
          );
        }
        return ElevatedButton(
          onPressed: () => ProfileRepository.instance.toggleFollow(targetId),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryText,
            foregroundColor: AppColors.background,
            shape: const StadiumBorder(),
          ),
          child: const Text('Follow'),
        );
      },
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
  const _PostsTab({
    required this.posts,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<Post> posts;
  final bool loading;
  final bool error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (error) {
      return _TabError(onRetry: onRetry);
    }
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
          onReply: () => openPostDetail(context, post, focusReply: true),
          onShare: () => sharePost(context, post),
          onTap: () => openPostDetail(context, post),
          onAuthorTap: () => openAuthorProfile(context, post.author.id),
        );
      },
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.posts,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<Post> posts;
  final bool loading;
  final bool error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (error) {
      return _TabError(onRetry: onRetry);
    }
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
        final post = posts[index];
        final url = post.mediaUrl!;
        return GestureDetector(
          onTap: () => openPostDetail(context, post),
          child: Image.network(
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
          ),
        );
      },
    );
  }
}

class _TabError extends StatelessWidget {
  const _TabError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Could not load posts', style: AppTextStyles.handle),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for editing the current user's display name and bio.
class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profile});

  final UserProfile profile;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();
    Navigator.of(context).pop(
      _EditResult(
        displayName: name.isEmpty ? widget.profile.displayName : name,
        bio: bio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: AppSpacing.lg + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Edit profile', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _nameController,
            cursorColor: AppColors.accent,
            style: AppTextStyles.body,
            decoration: const InputDecoration(
              labelText: 'Name',
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _bioController,
            cursorColor: AppColors.accent,
            minLines: 2,
            maxLines: 4,
            style: AppTextStyles.body,
            decoration: const InputDecoration(
              labelText: 'Bio',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _EditResult {
  const _EditResult({required this.displayName, required this.bio});

  final String displayName;
  final String bio;
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
