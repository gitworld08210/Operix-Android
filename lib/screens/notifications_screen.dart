import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../data/relationship_repository.dart';
import '../models/notification_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';

/// Activity feed backed by [ProfileRepository.instance].
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          TextButton(
            onPressed: ProfileRepository.instance.markNotificationsRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          ProfileRepository.instance,
          RelationshipRepository.instance,
        ]),
        builder: (context, _) {
          final items = ProfileRepository.instance.notifications();
          if (items.isEmpty) {
            return const _EmptyNotifications();
          }
          final pendingIds = RelationshipRepository.instance
              .pendingRequests()
              .map((p) => p.id)
              .toSet();
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0.5),
            itemBuilder: (context, index) {
              final item = items[index];
              final isPending = item.type == NotificationType.followRequest &&
                  pendingIds.contains(item.actor.id);
              return _NotificationTile(
                item: item,
                requestPending: isPending,
                onAccept: () => RelationshipRepository.instance
                    .acceptFollowRequest(item.actor.id),
                onDeny: () => RelationshipRepository.instance
                    .denyFollowRequest(item.actor.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.notifications_none,
              size: 44,
              color: AppColors.secondaryText,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No notifications yet', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Likes, replies, reposts, and follows will show up here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    this.requestPending = false,
    this.onAccept,
    this.onDeny,
  });

  final NotificationItem item;

  /// Whether this is a follow-request notification whose request is still
  /// pending (drives the Accept/Deny affordances).
  final bool requestPending;
  final VoidCallback? onAccept;
  final VoidCallback? onDeny;

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
      case NotificationType.followRequest:
        return Icons.person_add_alt_1;
      case NotificationType.system:
        return Icons.campaign;
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
      case NotificationType.followRequest:
        return AppColors.accent;
      case NotificationType.system:
        return AppColors.secondaryText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = item.actor;
    return Container(
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
                      TextSpan(text: actor.displayName, style: AppTextStyles.name),
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
                        text: '  ${item.preview ?? ''}',
                        style: AppTextStyles.body,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(timeAgo(item.createdAt), style: AppTextStyles.caption),
                if (item.type == NotificationType.followRequest) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  if (requestPending)
                    Row(
                      children: <Widget>[
                        FilledButton(
                          onPressed: onAccept,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Accept'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton(
                          onPressed: onDeny,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryText,
                            side: const BorderSide(color: AppColors.border),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Deny'),
                        ),
                      ],
                    )
                  else
                    Text('Request handled', style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
