import 'package:flutter/material.dart';

import '../data/comment_repository.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/comment_tree.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/verified_badge.dart';

/// Comments (replies) screen for a single [Post], backed by
/// [CommentRepository.instance].
///
/// Shows the parent post at the top, then the THREADED list of comments the
/// repository provides (assembled via [buildThread]: top-level newest-first
/// with replies nested/indented under their parent). Server-side RLS already
/// scopes comments to viewable posts, so only permitted comments are ever
/// rendered. Each tile carries a 'Reply' affordance (which sets a pending
/// parentId and shows a 'Replying to @handle' banner above the composer) and an
/// interactive like control wired to [CommentRepository.toggleCommentLike].
/// Loading / empty / error states and the composer's live character counter +
/// validation are preserved.
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

  /// The comment currently being replied to, or null for a top-level comment.
  /// Drives the 'Replying to @handle' banner and the `parentId` passed to
  /// [CommentRepository.addComment].
  Comment? _replyingTo;

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

  void _startReply(Comment comment) {
    setState(() => _replyingTo = comment);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  void _send() {
    if (!_canSend) return;
    try {
      CommentRepository.instance.addComment(
        widget.post.id,
        _controller.text,
        parentId: _replyingTo?.id,
      );
      _controller.clear();
      setState(() {
        _length = 0;
        _error = null;
        _replyingTo = null;
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
                final flat =
                    CommentRepository.instance.commentsFor(widget.post.id);
                final nodes = flattenThread(buildThread(flat));
                return CustomScrollView(
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: PostCard(post: widget.post),
                    ),
                    if (nodes.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyComments(),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final node = nodes[index];
                            return _CommentTile(
                              comment: node.comment,
                              depth: node.depth,
                              liked: CommentRepository.instance
                                  .isCommentLiked(node.comment.id),
                              onLike: () => CommentRepository.instance
                                  .toggleCommentLike(node.comment.id),
                              onReply: () => _startReply(node.comment),
                            );
                          },
                          childCount: nodes.length,
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
            replyingTo: _replyingTo,
            onCancelReply: _cancelReply,
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
  const _CommentTile({
    required this.comment,
    required this.depth,
    required this.liked,
    required this.onLike,
    required this.onReply,
  });

  final Comment comment;

  /// Visual nesting depth (clamped by [buildThread] to [maxThreadDepth]).
  final int depth;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    // Threaded replies are indented by depth so the parent/child relationship
    // reads clearly. Depth is already clamped upstream so deep chains stop
    // indenting past the cap.
    final leftPad = AppSpacing.lg + (depth * AppSpacing.xl);
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
                    _LikeControl(
                      liked: liked,
                      count: comment.likeCount,
                      onTap: onLike,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _ReplyButton(onTap: onReply),
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

/// A tappable heart + count that reflects the viewer's like on a comment.
class _LikeControl extends StatelessWidget {
  const _LikeControl({
    required this.liked,
    required this.count,
    required this.onTap,
  });

  final bool liked;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = liked ? AppColors.like : AppColors.secondaryText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              fmtCount(count),
              style: AppTextStyles.caption.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact 'Reply' text affordance on each comment tile.
class _ReplyButton extends StatelessWidget {
  const _ReplyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.reply,
              size: 15,
              color: AppColors.secondaryText,
            ),
            const SizedBox(width: 4),
            Text(
              'Reply',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.secondaryText),
            ),
          ],
        ),
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
    required this.replyingTo,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final int maxChars;
  final String? error;
  final bool canSend;
  final Comment? replyingTo;
  final VoidCallback onCancelReply;
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
            if (replyingTo != null)
              _ReplyingBanner(
                handle: replyingTo!.author.handle,
                onCancel: onCancelReply,
              ),
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
                    decoration: InputDecoration(
                      hintText: replyingTo == null
                          ? 'Post your reply'
                          : 'Reply to ${replyingTo!.author.handle}',
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

/// The 'Replying to @handle · cancel' banner shown above the composer while a
/// reply is pending.
class _ReplyingBanner extends StatelessWidget {
  const _ReplyingBanner({required this.handle, required this.onCancel});

  final String handle;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.reply,
            size: 14,
            color: AppColors.secondaryText,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Replying to $handle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption,
            ),
          ),
          Text('  ·  ', style: AppTextStyles.caption),
          InkWell(
            onTap: onCancel,
            child: Text(
              'cancel',
              style: AppTextStyles.caption.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}
