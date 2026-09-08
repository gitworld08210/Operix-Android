import 'package:flutter/material.dart';

import '../data/notification_repository.dart';
import '../models/notification_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';

/// Activity feed backed by [NotificationRepository.instance].
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
            onPressed: () => NotificationRepository.instance
                .markNotificationsRead(),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: NotificationRepository.instance,
        builder: (context, _) {
          final items = NotificationRepository.instance.notifications();
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0.5),
            itemBuilder: (context, index) => _NotificationTile(item: items[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
