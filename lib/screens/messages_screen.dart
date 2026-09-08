import 'package:flutter/material.dart';

import '../data/message_repository.dart';
import '../models/conversation.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';
import 'conversation_screen.dart';

/// Direct-message thread list backed by [MessageRepository.instance].
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: AnimatedBuilder(
        animation: MessageRepository.instance,
        builder: (context, _) {
          final conversations = MessageRepository.instance.conversations();
          if (conversations.isEmpty) {
            return Center(
              child: Text('No messages yet', style: AppTextStyles.handle),
            );
          }
          return ListView.separated(
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const Divider(height: 0.5),
            itemBuilder: (context, index) =>
                _ConversationTile(conversation: conversations[index]),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final participant = conversation.participant;
    final unread = conversation.unread > 0;
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationScreen(conversation: conversation),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Avatar(
              url: participant.avatarUrl,
              displayName: participant.displayName,
              size: 48,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          participant.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.name,
                        ),
                      ),
                      if (participant.verified) ...<Widget>[
                        const SizedBox(width: 4),
                        VerifiedBadge(kind: participant.verificationKind),
                      ],
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          participant.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.handle,
                        ),
                      ),
                      Text(
                        timeAgo(conversation.updatedAt),
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          conversation.lastPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.handle.copyWith(
                            color: unread
                                ? AppColors.primaryText
                                : AppColors.secondaryText,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
