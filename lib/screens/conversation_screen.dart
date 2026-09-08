import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';

/// A single DM thread. Messages are kept in local state; sending appends a
/// message from the current user (in-memory only).
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final List<Message> _messages;

  @override
  void initState() {
    super.initState();
    _messages = List<Message>.of(widget.conversation.messages)
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(
        Message(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}',
          fromMe: true,
          text: text,
          sentAt: DateTime.now(),
        ),
      );
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final participant = widget.conversation.participant;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            Avatar(
              url: participant.avatarUrl,
              displayName: participant.displayName,
              size: 34,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      participant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title,
                    ),
                  ),
                  if (participant.verified) ...<Widget>[
                    const SizedBox(width: 4),
                    VerifiedBadge(kind: participant.verificationKind),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return _Bubble(message: message);
              },
            ),
          ),
          _Composer(controller: _controller, onSend: _send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final fromMe = message.fromMe;
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: fromMe ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadii.lg),
            topRight: const Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(fromMe ? AppRadii.lg : AppRadii.sm),
            bottomRight: Radius.circular(fromMe ? AppRadii.sm : AppRadii.lg),
          ),
        ),
        child: Text(
          message.text,
          style: AppTextStyles.body.copyWith(
            color: fromMe ? AppColors.white : AppColors.primaryText,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                cursorColor: AppColors.accent,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Start a message',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: onSend,
              icon: const Icon(Icons.send, color: AppColors.accent),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
