import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth_repository.dart';
import '../data/message_repository.dart';
import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../data/storage_service.dart';
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
import 'placeholder_screen.dart';
import 'post_detail_screen.dart';

/// Returns a lowercase file extension for [fileName] (without the dot),
/// defaulting to `jpg` when there is none. Used to key uploaded images.
String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'jpg';
  return fileName.substring(dot + 1).toLowerCase();
}

/// Profile screen with a banner, large overlapping avatar, bio + counts, and
/// Posts / Replies / Media tabs. Supabase-backed for ANY profile: the current
/// user gets a Share + Edit profile pair (and a "Get verified" pill + Bookmarks
/// entry), other users get a Message button + a Subscribe-styled button wired
/// to [ProfileRepository.toggleFollow]. Posts read that profile's real posts
/// via [PostRepository.postsByOwner]; Media filters those to media; Replies
/// shows an honest empty state (no per-owner replies query exists). A
/// "Who to follow" footer uses real [ProfileRepository.suggestedProfiles].
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

  List<UserProfile> _suggested = const <UserProfile>[];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPosts();
    _loadSuggested();
  }

  Future<void> _loadSuggested() async {
    final people = await ProfileRepository.instance.suggestedProfiles(limit: 3);
    if (!mounted) return;
    setState(() => _suggested = people);
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

  /// Picks an image from the gallery, uploads it to the `avatars` bucket, and
  /// persists the returned public URL onto `profiles.avatar_url` (then the
  /// header reflects it via the repository's notifyListeners). Handles the
  /// user-cancelled case (null) gracefully and surfaces failures.
  Future<void> _changeAvatar() async {
    final userId = AuthRepository.instance.currentUser?.id;
    if (userId == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return; // user cancelled

    final bytes = await picked.readAsBytes();
    final ext = _extensionOf(picked.name);
    try {
      final url = await StorageService.uploadAvatar(
        userId: userId,
        bytes: bytes,
        ext: ext,
      );
      await ProfileRepository.instance.updateProfile(avatarUrl: url);
      // Refresh so the persisted avatar_url is authoritative across screens.
      // ignore: discarded_futures
      ProfileRepository.instance.load();
    } catch (_) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not update your photo.')),
        );
    }
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
                  onChangeAvatar: _changeAvatar,
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
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const <Widget>[
                  Tab(text: 'Posts'),
                  Tab(text: 'Replies'),
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
                  suggested: _suggested,
                ),
                // There is no dedicated per-owner replies query in the data
                // layer (PostRepository exposes postsByOwner / bookmarkedPosts
                // / replies(parentId) / searchPosts), so rather than fabricate
                // a list we show an honest empty state here. This keeps the
                // tab structure ready for a future replies-by-owner feed.
                _RepliesTab(
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
    required this.onChangeAvatar,
  });

  final UserProfile profile;
  final bool isCurrentUser;
  final VoidCallback onEdit;
  final Future<void> Function() onChangeAvatar;

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
                isCurrentUser
                    ? _EditableAvatar(
                        profile: profile,
                        onChangeAvatar: onChangeAvatar,
                      )
                    : Avatar(
                        url: profile.avatarUrl,
                        displayName: profile.displayName,
                        size: 72,
                        ring: true,
                      ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: isCurrentUser
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _ShareProfileButton(profile: profile),
                            const SizedBox(width: AppSpacing.sm),
                            _EditButton(onEdit: onEdit),
                          ],
                        )
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
                // Own, not-yet-verified account gets X's "Get verified" upsell
                // pill. It routes to the honest shared PlaceholderScreen rather
                // than claiming a purchase/subscription flow this app has no
                // backend for.
                if (isCurrentUser && !profile.verified) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  const _GetVerifiedPill(),
                ],
                const SizedBox(height: 2),
                Text(profile.handle, style: AppTextStyles.handle),
                if (profile.bio.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(profile.bio, style: AppTextStyles.body),
                ],
                const SizedBox(height: AppSpacing.sm),
                // Meta row: only fields that actually exist on UserProfile are
                // rendered. The model carries no born/joined/location, so we
                // deliberately omit those rather than fabricate them, showing a
                // small handle glyph instead.
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.alternate_email,
                      size: 15,
                      color: AppColors.secondaryText,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        profile.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
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

/// The current user's avatar with a tap-to-change affordance (camera badge).
/// Tapping runs [onChangeAvatar], which picks + uploads a new photo.
class _EditableAvatar extends StatefulWidget {
  const _EditableAvatar({
    required this.profile,
    required this.onChangeAvatar,
  });

  final UserProfile profile;
  final Future<void> Function() onChangeAvatar;

  @override
  State<_EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends State<_EditableAvatar> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onChangeAvatar();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _busy ? null : _onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: <Widget>[
          Avatar(
            url: widget.profile.avatarUrl,
            displayName: widget.profile.displayName,
            size: 72,
            ring: true,
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Icon(
                    Icons.camera_alt,
                    size: 14,
                    color: AppColors.white,
                  ),
          ),
        ],
      ),
    );
  }
}

/// X's "Get verified" upsell pill shown on the current user's own profile when
/// they are not yet verified. This app has no real verification purchase flow,
/// so it routes to the honest shared [PlaceholderScreen] instead of pretending
/// to sell a subscription.
class _GetVerifiedPill extends StatelessWidget {
  const _GetVerifiedPill();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const PlaceholderScreen(title: 'Get verified'),
        ),
      ),
      icon: const Icon(Icons.verified, size: 16, color: AppColors.accent),
      label: const Text('Get verified'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 2,
        ),
        visualDensity: VisualDensity.compact,
        textStyle: AppTextStyles.label.copyWith(color: AppColors.accent),
      ),
    );
  }
}

/// Copies a shareable link to this profile to the clipboard, mirroring
/// [sharePost] in post_detail_screen.dart (no share-sheet package is bundled).
class _ShareProfileButton extends StatelessWidget {
  const _ShareProfileButton({required this.profile});

  final UserProfile profile;

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final link = 'https://oneleven.app/${profile.username}';
    await Clipboard.setData(ClipboardData(text: link));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Profile link copied to clipboard')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => _share(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryText,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
      ),
      child: const Text('Share'),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onEdit});

  final VoidCallback onEdit;

  // Editing name/bio persists through ProfileRepository.updateProfile. The
  // avatar is changed by tapping the header photo (see _EditableAvatar), which
  // picks an image, uploads it via StorageService.uploadAvatar, and persists
  // the returned URL onto profiles.avatar_url.
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
        // Not following: X shows a filled follow/subscribe CTA here. We use the
        // magenta subscribe token for a Subscribe-styled button while keeping
        // the real toggleFollow wiring intact (it inserts a follows row).
        return ElevatedButton.icon(
          onPressed: () => ProfileRepository.instance.toggleFollow(targetId),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.subscribe,
            foregroundColor: AppColors.white,
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.star, size: 16, color: AppColors.white),
          label: const Text('Subscribe'),
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
    this.suggested = const <UserProfile>[],
  });

  final List<Post> posts;
  final bool loading;
  final bool error;
  final Future<void> Function() onRetry;

  /// Real suggested profiles (from [ProfileRepository.suggestedProfiles]) shown
  /// as a "Who to follow" footer. Empty when none are available, in which case
  /// the section is omitted rather than faked.
  final List<UserProfile> suggested;

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
      if (suggested.isEmpty) {
        return Center(
          child: Text('No posts yet', style: AppTextStyles.handle),
        );
      }
      return ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Text('No posts yet', style: AppTextStyles.handle),
            ),
          ),
          _WhoToFollow(people: suggested),
        ],
      );
    }
    final repo = PostRepository.instance;
    final hasSuggestions = suggested.isNotEmpty;
    return ListView.builder(
      itemCount: posts.length + (hasSuggestions ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == posts.length) {
          return _WhoToFollow(people: suggested);
        }
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

/// A "Who to follow" footer built ONLY from real suggested profiles
/// ([ProfileRepository.suggestedProfiles]). Each row navigates to the real
/// profile and offers a working follow toggle. Omitted entirely when there are
/// no suggestions, so nothing is fabricated.
class _WhoToFollow extends StatelessWidget {
  const _WhoToFollow({required this.people});

  final List<UserProfile> people;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(height: 0.5),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text('Who to follow', style: AppTextStyles.title),
        ),
        for (final person in people) _SuggestedTile(person: person),
      ],
    );
  }
}

class _SuggestedTile extends StatelessWidget {
  const _SuggestedTile({required this.person});

  final UserProfile person;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => openAuthorProfile(context, person.id),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      leading: Avatar(
        url: person.avatarUrl,
        displayName: person.displayName,
        size: 44,
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              person.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.name,
            ),
          ),
          if (person.verified) ...<Widget>[
            const SizedBox(width: 4),
            VerifiedBadge(kind: person.verificationKind),
          ],
        ],
      ),
      subtitle: Text(person.handle, style: AppTextStyles.handle),
      trailing: _FollowPill(targetId: person.id),
    );
  }
}

/// A compact follow/following pill wired to [ProfileRepository.toggleFollow],
/// used in the "Who to follow" list.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.targetId});

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
              visualDensity: VisualDensity.compact,
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
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Follow'),
        );
      },
    );
  }
}

/// The Replies tab. There is no per-owner replies query in the data layer, so
/// rather than fabricate content this shows a clean empty state (mirroring the
/// Posts/Media tabs' loading/error handling). Ready to swap in a real
/// replies-by-owner feed if the repository gains one.
class _RepliesTab extends StatelessWidget {
  const _RepliesTab({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

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
    return Center(
      child: Text('No replies yet', style: AppTextStyles.handle),
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
