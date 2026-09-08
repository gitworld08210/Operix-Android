import 'package:flutter/material.dart';

import '../data/load_status.dart';
import '../data/notification_repository.dart';
import '../data/post_repository.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';
import 'post_detail_screen.dart';

/// Activity feed backed by [NotificationRepository.instance]. Shows real
/// loading / empty / error states, marks all read as a real DB update, and
/// navigates on tap to the relevant post detail (like/reply/repost/mention
/// with a post) or the actor's profile (follow).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Load on screen entry if it has not been loaded yet (a fresh sign-in
    // already triggers load() via AuthGate; this covers direct entry).
    final repo = NotificationRepository.instance;
    if (repo.status == LoadStatus.idle) {
      // ignore: discarded_futures
      repo.load();
    }
  }

  Future<void> _openTarget(NotificationItem item) async {
    final navContext = context;
    switch (item.type) {
      case NotificationType.follow:
        await openAuthorProfile(navContext, item.actor.id);
        return;
      case NotificationType.like:
      case NotificationType.reply:
      case NotificationType.repost:
      case NotificationType.mention:
        final postId = item.postId;
        if (postId == null || postId.isEmpty) {
          // No post to open (e.g. a mention without a post); fall back to the
          // actor's profile so the tap is never a dead end.
          await openAuthorProfile(navContext, item.actor.id);
          return;
        }
        final messenger = ScaffoldMessenger.of(navContext);
        final Post? post =
            await PostRepository.instance.fetchPostById(postId);
        if (!mounted) return;
        if (post == null) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('That post is no longer available.')),
            );
          return;
        }
        await openPostDetail(navContext, post);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          AnimatedBuilder(
            animation: NotificationRepository.instance,
            builder: (context, _) {
              final hasUnread =
                  NotificationRepository.instance.unreadNotifications > 0;
              return TextButton(
                onPressed: hasUnread
                    ? () => NotificationRepository.instance
                        .markNotificationsRead()
                    : null,
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: NotificationRepository.instance,
        builder: (context, _) {
          final repo = NotificationRepository.instance;
          final items = repo.notifications();
          if (items.isEmpty) {
            switch (repo.status) {
              case LoadStatus.loading:
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                );
              case LoadStatus.error:
                return _ErrorState(onRetry: repo.load);
              case LoadStatus.idle:
              case LoadStatus.loaded:
                return _EmptyState(onRefresh: repo.load);
            }
          }
          return RefreshIndicator(
            onRefresh: repo.load,
            color: AppColors.accent,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 0.5),
              itemBuilder: (context, index) => _NotificationTile(
                item: items[index],
                onTap: () => _openTarget(items[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(
        children: <Widget>[
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Center(
            child: Text('No notifications yet', style: AppTextStyles.handle),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Could not load notifications', style: AppTextStyles.handle),
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

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  IconData get _typeIcon {
    switch (item.type) {
      case NotificationType.like:
        return Icons.favorite;
      case NotificationType.reply:
        return Icons.chat_bubble;
      case NotificationType.repost:
        return Icons.repeat;
      case NotificationType.follow:
        return Icons.person_add;
      case NotificationType.mention:
        return Icons.alternate_email;
    }
  }

  Color get _typeColor {
    switch (item.type) {
      case NotificationType.like:
        return AppColors.like;
      case NotificationType.repost:
        return AppColors.repost;
      case NotificationType.reply:
      case NotificationType.follow:
      case NotificationType.mention:
        return AppColors.accent;
    }
  }

  /// A human action phrase describing what the actor did, so the tile never
  /// reads as a bare "Name  <post text>" fragment. The optional post preview
  /// is rendered separately as secondary text.
  String get _actionPhrase {
    switch (item.type) {
      case NotificationType.like:
        return 'liked your post';
      case NotificationType.reply:
        return 'replied to your post';
      case NotificationType.repost:
        return 'reposted your post';
      case NotificationType.follow:
        return 'started following you';
      case NotificationType.mention:
        return 'mentioned you';
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = item.actor;
    final preview = item.preview?.trim();
    return InkWell(
      onTap: onTap,
      child: Container(
        color: item.read ? AppColors.background : AppColors.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(_typeIcon, color: _typeColor, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Avatar(
                    url: actor.avatarUrl,
                    displayName: actor.displayName,
                    size: 32,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                            text: actor.displayName, style: AppTextStyles.name),
                        if (actor.verified) ...<InlineSpan>[
                          const WidgetSpan(child: SizedBox(width: 4)),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: VerifiedBadge(
                              kind: actor.verificationKind,
                              size: 15,
                            ),
                          ),
                        ],
                        TextSpan(
                          text: ' $_actionPhrase',
                          style: AppTextStyles.body,
                        ),
                      ],
                    ),
                  ),
                  if (preview != null && preview.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.handle,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(timeAgo(item.createdAt), style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
