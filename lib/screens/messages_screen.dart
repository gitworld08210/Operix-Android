import 'package:flutter/material.dart';

import '../data/load_status.dart';
import '../data/message_repository.dart';
import '../models/conversation.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';
import 'conversation_screen.dart';
import 'search_screen.dart';

/// Direct-message thread list backed by [MessageRepository.instance]. Shows
/// real loading / empty / error states; tapping a conversation opens the
/// thread and resets its unread counter.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    final repo = MessageRepository.instance;
    if (repo.status == LoadStatus.idle) {
      // ignore: discarded_futures
      repo.load();
    }
  }

  /// Opens Search so the user can find someone to message. A 1:1 DM is started
  /// from the target's profile ("Message" button), so this routes there rather
  /// than duplicating the center-nav compose (which posts, not DMs).
  void _startNewMessage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SearchScreen(),
      ),
    );
  }

  Future<void> _openConversation(Conversation conversation) async {
    // Reset unread immediately so the badge clears when opening the thread.
    // ignore: discarded_futures
    MessageRepository.instance.resetUnread(conversation.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(conversationId: conversation.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewMessage,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.white,
        tooltip: 'New message',
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: AnimatedBuilder(
        animation: MessageRepository.instance,
        builder: (context, _) {
          final repo = MessageRepository.instance;
          final conversations = repo.conversations();
          if (conversations.isEmpty) {
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
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 0.5),
              itemBuilder: (context, index) => _ConversationTile(
                conversation: conversations[index],
                onTap: () => _openConversation(conversations[index]),
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
            child: Text('No messages yet', style: AppTextStyles.handle),
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
          Text('Could not load messages', style: AppTextStyles.handle),
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

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final participant = conversation.participant;
    final unread = conversation.unread > 0;
    return InkWell(
      onTap: onTap,
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
