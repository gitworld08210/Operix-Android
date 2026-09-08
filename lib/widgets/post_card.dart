import 'package:flutter/material.dart';

import '../data/safety_repository.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'action_button.dart';
import 'avatar.dart';
import 'report_sheet.dart';
import 'verified_badge.dart';

/// A stateless PostCard mirroring the web PostCard: avatar column + content
/// column, a header row, linkified caption with 'Show more', optional rounded
/// media, and the full modern-X action row. All state changes are driven by
/// the [post] model and the toggle callbacks.
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onRepost,
    this.onBookmark,
    this.onReply,
    this.onShare,
    this.onTap,
    this.onAuthorTap,
  });

  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onRepost;
  final VoidCallback? onBookmark;
  final VoidCallback? onReply;
  final VoidCallback? onShare;
  final VoidCallback? onTap;
  final VoidCallback? onAuthorTap;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  static const int _truncateAt = 240;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final author = post.author;

    return InkWell(
      onTap: widget.onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            GestureDetector(
              onTap: widget.onAuthorTap,
              child: Avatar(
                url: author.avatarUrl,
                displayName: author.displayName,
                size: 44,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Header(
                    post: post,
                    onAuthorTap: widget.onAuthorTap,
                    overflow: _PostOverflowMenu(post: post),
                  ),
                  const SizedBox(height: 2),
                  _caption(context),
                  if (post.hasMedia) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _Media(post: post),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _actions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caption(BuildContext context) {
    final content = widget.post.content;
    final needsTruncation = content.length > _truncateAt && !_expanded;
    final shown =
        needsTruncation ? '${content.substring(0, _truncateAt).trimRight()}…' : content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          _linkify(shown),
          style: AppTextStyles.body,
        ),
        if (needsTruncation)
          GestureDetector(
            onTap: () => setState(() => _expanded = true),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Show more',
                style: AppTextStyles.body.copyWith(color: AppColors.accent),
              ),
            ),
          ),
      ],
    );
  }

  /// Splits the text into runs, coloring #hashtags and @mentions in X-blue.
  TextSpan _linkify(String text) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'([#@][A-Za-z0-9_\.]+)');
    var lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(color: AppColors.accent),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return TextSpan(children: spans);
  }

  Widget _actions() {
    final post = widget.post;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        ActionButton(
          icon: Icons.chat_bubble_outline,
          count: post.replyCount,
          activeColor: AppColors.accent,
          onTap: widget.onReply,
          tooltip: 'Reply',
        ),
        ActionButton(
          icon: Icons.repeat,
          count: post.repostCount,
          active: post.reposted,
          activeColor: AppColors.repost,
          onTap: widget.onRepost,
          tooltip: 'Repost',
        ),
        ActionButton(
          icon: Icons.favorite_border,
          activeIcon: Icons.favorite,
          count: post.likeCount,
          active: post.liked,
          activeColor: AppColors.like,
          onTap: widget.onLike,
          tooltip: 'Like',
        ),
        ActionButton(
          icon: Icons.bar_chart,
          count: post.viewCount,
          activeColor: AppColors.accent,
          tooltip: 'Views',
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ActionButton(
              icon: Icons.bookmark_border,
              activeIcon: Icons.bookmark,
              active: post.bookmarked,
              activeColor: AppColors.accent,
              onTap: widget.onBookmark,
              tooltip: 'Bookmark',
            ),
            ActionButton(
              icon: Icons.ios_share,
              activeColor: AppColors.accent,
              onTap: widget.onShare,
              tooltip: 'Share',
            ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.post, this.onAuthorTap, required this.overflow});

  final Post post;
  final VoidCallback? onAuthorTap;
  final Widget overflow;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return Row(
      children: <Widget>[
        Flexible(
          child: GestureDetector(
            onTap: onAuthorTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
              ],
            ),
          ),
        ),
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
        Text(timeAgo(post.createdAt), style: AppTextStyles.handle),
        const Spacer(),
        overflow,
      ],
    );
  }
}

/// The three-dot overflow menu on a [PostCard]: mute author, block author, and
/// report post. Wired to [SafetyRepository]; mute/block show an Undo snackbar,
/// report opens a reason sheet and confirms optimistically.
class _PostOverflowMenu extends StatelessWidget {
  const _PostOverflowMenu({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(
        Icons.more_horiz,
        size: 18,
        color: AppColors.secondaryText,
      ),
      color: AppColors.surface,
      onSelected: (value) => _onSelected(context, value),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'mute',
          child: Text('Mute @${author.username}'),
        ),
        PopupMenuItem<String>(
          value: 'block',
          child: Text('Block @${author.username}'),
        ),
        const PopupMenuItem<String>(
          value: 'report',
          child: Text('Report post'),
        ),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, String value) async {
    final safety = SafetyRepository.instance;
    final author = post.author;
    switch (value) {
      case 'mute':
        safety.mute(author.id);
        _showUndo(context, 'Muted @${author.username}',
            () => safety.unmute(author.id));
      case 'block':
        safety.block(author.id);
        _showUndo(context, 'Blocked @${author.username}',
            () => safety.unblock(author.id));
      case 'report':
        await showReportSheet(
          context,
          targetType: 'post',
          targetId: post.id,
          targetLabel: 'this post',
        );
    }
  }

  void _showUndo(BuildContext context, String message, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppColors.accent,
            onPressed: undo,
          ),
        ),
      );
  }
}

class _Media extends StatelessWidget {
  const _Media({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final url = post.mediaUrl!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const _MediaFallback(loading: true);
              },
              errorBuilder: (context, error, stackTrace) =>
                  const _MediaFallback(loading: false),
            ),
            if (post.mediaType == MediaType.video)
              const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.play_arrow,
                      color: AppColors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Icon(
        loading ? Icons.image_outlined : Icons.broken_image_outlined,
        color: AppColors.secondaryText,
        size: 32,
      ),
    );
  }
}
