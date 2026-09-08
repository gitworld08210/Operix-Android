import 'package:flutter/material.dart';

import '../data/message_repository.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';

/// A single DM thread, backed by [MessageRepository.instance]. On open it loads
/// the messages for [conversationId] (loading / empty / error states), marks
/// the thread active so live inbound messages do not inflate the unread badge,
/// and its composer sends via [MessageRepository.sendMessage] (which inserts a
/// real `messages` row; preview/updated_at/unread are trigger-maintained).
/// Bubbles are sided from [Message.fromMe]. The thread reflects realtime
/// inserts because it renders the repository's cached conversation.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _error = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    MessageRepository.instance.setActiveConversation(widget.conversationId);
    _load();
  }

  @override
  void dispose() {
    // Clear the active conversation so background inbound messages resume
    // counting toward unread once the thread is closed.
    MessageRepository.instance.setActiveConversation(null);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      await MessageRepository.instance.loadMessages(widget.conversationId);
      if (!mounted) return;
      setState(() => _loading = false);
      // A freshly opened thread may have unread inbound messages.
      // ignore: discarded_futures
      MessageRepository.instance.resetUnread(widget.conversationId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final message =
        await MessageRepository.instance.sendMessage(widget.conversationId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (message == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not send your message.')),
        );
      return;
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MessageRepository.instance,
      builder: (context, _) {
        final conversation =
            MessageRepository.instance.conversationById(widget.conversationId);
        final participant = conversation?.participant;
        final messages = _sortedMessages(conversation);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: _Title(participant: participant),
          ),
          body: Column(
            children: <Widget>[
              Expanded(child: _body(messages)),
              _Composer(
                controller: _controller,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Message> _sortedMessages(Conversation? conversation) {
    final messages = List<Message>.of(conversation?.messages ?? const <Message>[])
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return messages;
  }

  Widget _body(List<Message> messages) {
    if (_loading && messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error && messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Could not load messages', style: AppTextStyles.handle),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Say hello.',
          style: AppTextStyles.handle,
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        return _Bubble(message: message);
      },
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.participant});

  final UserProfile? participant;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    if (p == null) {
      return const Text('Conversation');
    }
    return Row(
      children: <Widget>[
        Avatar(
          url: p.avatarUrl,
          displayName: p.displayName,
          size: 34,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  p.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
              ),
              if (p.verified) ...<Widget>[
                const SizedBox(width: 4),
                VerifiedBadge(kind: p.verificationKind),
              ],
            ],
          ),
        ),
      ],
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
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
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
                decoration: const InputDecoration(
                  hintText: 'Start a message',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : const Icon(Icons.send, color: AppColors.accent),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
