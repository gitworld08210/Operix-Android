import 'package:flutter/material.dart';

import '../data/comment_repository.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/verified_badge.dart';

/// Comments (replies) screen for a single [Post], backed by
/// [CommentRepository.instance].
///
/// Shows the parent post at the top, then the list of comments the repository
/// provides (which server-side RLS already scopes to viewable posts, so only
/// permitted comments are ever rendered), with loading / empty / error states,
/// and a composer with a live character counter + validation.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({super.key, required this.post});

  final Post post;

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _length = 0;
  String? _error;

  static const int _maxChars = CommentRepository.maxContentLength;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _length = _controller.text.characters.length;
        // Clear a stale validation error as the user edits.
        if (_error != null) _error = null;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSend {
    final trimmed = _controller.text.trim();
    return trimmed.isNotEmpty && trimmed.length <= _maxChars;
  }

  void _send() {
    if (!_canSend) return;
    try {
      CommentRepository.instance.addComment(
        widget.post.id,
        _controller.text,
      );
      _controller.clear();
      setState(() {
        _length = 0;
        _error = null;
      });
      _focusNode.unfocus();
    } on CommentValidationError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Replies')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: AnimatedBuilder(
              animation: CommentRepository.instance,
              builder: (context, _) {
                final comments =
                    CommentRepository.instance.commentsFor(widget.post.id);
                return CustomScrollView(
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: PostCard(post: widget.post),
                    ),
                    if (comments.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyComments(),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _CommentTile(comment: comments[index]),
                          childCount: comments.length,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          _Composer(
            controller: _controller,
            focusNode: _focusNode,
            length: _length,
            maxChars: _maxChars,
            error: _error,
            canSend: _canSend,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _EmptyComments extends StatelessWidget {
  const _EmptyComments();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.chat_bubble_outline,
              size: 44,
              color: AppColors.secondaryText,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No comments yet', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Be the first to reply.',
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    // Threaded replies are indented so the parent/child relationship reads
    // clearly in the flat newest-first list.
    final leftPad = AppSpacing.lg + (comment.isTopLevel ? 0 : AppSpacing.xl);
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        leftPad,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Avatar(
            url: author.avatarUrl,
            displayName: author.displayName,
            size: 36,
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
                        author.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.name,
                      ),
                    ),
                    if (author.verified) ...<Widget>[
                      const SizedBox(width: 4),
                      VerifiedBadge(kind: author.verificationKind),
                    ],
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        author.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.handle,
                      ),
                    ),
                    Text('  ·  ', style: AppTextStyles.handle),
                    Text(timeAgo(comment.createdAt), style: AppTextStyles.handle),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.content, style: AppTextStyles.body),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.favorite_border,
                      size: 15,
                      color: AppColors.secondaryText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      fmtCount(comment.likeCount),
                      style: AppTextStyles.caption,
                    ),
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.maxChars,
    required this.error,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final int maxChars;
  final String? error;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final remaining = maxChars - length;
    final overLimit = remaining < 0;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  error!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.like),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 4,
                    minLines: 1,
                    cursorColor: AppColors.accent,
                    style: AppTextStyles.body,
                    decoration: const InputDecoration(
                      hintText: 'Post your reply',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '$length/$maxChars',
                  style: AppTextStyles.caption.copyWith(
                    color: overLimit ? AppColors.like : AppColors.secondaryText,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  onPressed: canSend ? onSend : null,
                  icon: Icon(
                    Icons.send,
                    color: canSend ? AppColors.accent : AppColors.secondaryText,
                  ),
                  tooltip: 'Send',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
