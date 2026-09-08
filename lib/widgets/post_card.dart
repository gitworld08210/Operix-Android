import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../data/safety_repository.dart';
import '../data/save_repository.dart';
import '../models/post.dart';
import '../models/post_attachment.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/text_entities.dart';
import 'action_button.dart';
import 'avatar.dart';
import 'report_sheet.dart';
import 'verified_badge.dart';

/// Display metadata for the 6 reaction types: the picker emoji glyph and a
/// short label (used for the tooltip). The ordering here is the order shown in
/// the long-press picker popover.
const Map<ReactionType, ({String emoji, String label})> kReactionDisplay =
    <ReactionType, ({String emoji, String label})>{
  ReactionType.like: (emoji: '👍', label: 'Like'),
  ReactionType.love: (emoji: '❤️', label: 'Love'),
  ReactionType.laugh: (emoji: '😂', label: 'Haha'),
  ReactionType.wow: (emoji: '😮', label: 'Wow'),
  ReactionType.sad: (emoji: '😢', label: 'Sad'),
  ReactionType.angry: (emoji: '😡', label: 'Angry'),
};

/// A stateless PostCard mirroring the web PostCard: avatar column + content
/// column, a header row, linkified caption with 'Show more', optional rounded
/// media, and the full modern-X action row. All state changes are driven by
/// the [post] model and the toggle callbacks.
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onReact,
    this.onClearReaction,
    this.onRepost,
    this.onBookmark,
    this.onReply,
    this.onShare,
    this.onTap,
    this.onAuthorTap,
  });

  final Post post;

  /// Quick like/unlike: a plain TAP on the like button (unchanged behavior).
  final VoidCallback? onLike;

  /// Applies a specific reaction, invoked from the long-press picker.
  final void Function(ReactionType type)? onReact;

  /// Clears the viewer's reaction, invoked when the picker's currently-selected
  /// reaction is tapped again.
  final VoidCallback? onClearReaction;

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
    // Guard the safety overflow menu the same way the profile screen does
    // (`if (_isCurrentUser) ... else PopupMenuButton(...)`): a viewer must not
    // be able to mute/block/report their OWN post. On own-authored posts the
    // menu collapses to an empty (zero-size) widget so nothing is reachable.
    final isOwnPost = author.id == ProfileRepository.instance.currentUser.id;

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
                    overflow: isOwnPost
                        ? const SizedBox.shrink()
                        : _PostOverflowMenu(post: post),
                  ),
                  const SizedBox(height: 2),
                  _caption(context),
                  if (post.hasMedia) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    // Switch the media block on the polymorphic content kind:
                    // a carousel (>1 attachment) renders a swipeable PageView;
                    // single image/video keeps the existing single _Media.
                    // Text posts never reach here (hasMedia is false).
                    if (post.kind == PostKind.carousel)
                      _Carousel(attachments: post.attachments)
                    else
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
  ///
  /// Highlighting uses the SAME grammar the extractors use (see
  /// `utils/text_entities.dart` [hashtagPattern] / [mentionPattern]) so the
  /// highlighted span and the extracted/linked entity are byte-identical: a
  /// hashtag body excludes dots (a trailing `.` ends the tag), while a mention
  /// body allows dots. The two source patterns are combined into one alternation
  /// so a single left-to-right scan colors both kinds.
  TextSpan _linkify(String text) {
    final spans = <TextSpan>[];
    final pattern = RegExp(
      '(?:${hashtagPattern.pattern})|(?:${mentionPattern.pattern})',
    );
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
        _LikeReactionButton(
          post: post,
          onLike: widget.onLike,
          onReact: widget.onReact,
          onClearReaction: widget.onClearReaction,
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
            AnimatedBuilder(
              animation: SaveRepository.instance,
              builder: (context, _) => ActionButton(
                icon: Icons.bookmark_border,
                activeIcon: Icons.bookmark,
                active: SaveRepository.instance.isSaved(post.id),
                activeColor: AppColors.accent,
                onTap: widget.onBookmark,
                tooltip: 'Bookmark',
              ),
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

/// The like button + its 6-type reaction picker.
///
/// A PLAIN TAP is the unchanged quick like/unlike (drives [onLike]). A
/// LONG-PRESS opens a small horizontal popover of the 6 reaction emojis
/// (ordered per [kReactionDisplay]); tapping one applies it via [onReact],
/// tapping the currently-selected reaction clears it via [onClearReaction]. The
/// button reflects the viewer's current [Post.myReaction]: a non-`like`
/// reaction shows its emoji glyph + label color; `like`/none keep the classic
/// heart. The action-row layout is unchanged (this replaces exactly the single
/// like [ActionButton]).
class _LikeReactionButton extends StatelessWidget {
  const _LikeReactionButton({
    required this.post,
    this.onLike,
    this.onReact,
    this.onClearReaction,
  });

  final Post post;
  final VoidCallback? onLike;
  final void Function(ReactionType type)? onReact;
  final VoidCallback? onClearReaction;

  @override
  Widget build(BuildContext context) {
    final reaction = post.myReaction;
    final hasNonLikeReaction =
        reaction != null && reaction != ReactionType.like;

    return GestureDetector(
      onLongPress: () => _openPicker(context),
      child: hasNonLikeReaction
          ? _reactionGlyphButton(reaction)
          : ActionButton(
              icon: Icons.favorite_border,
              activeIcon: Icons.favorite,
              count: post.likeCount,
              active: post.liked,
              activeColor: AppColors.like,
              onTap: onLike,
              tooltip: 'Like (long-press to react)',
            ),
    );
  }

  /// The like button rendered as the chosen non-like reaction: its emoji glyph
  /// plus the like count, colored active. Tapping it clears the reaction (so a
  /// plain tap still toggles the reaction off, mirroring the quick-like tap).
  Widget _reactionGlyphButton(ReactionType reaction) {
    final display = kReactionDisplay[reaction]!;
    return Tooltip(
      message: '${display.label} (long-press to change)',
      child: InkWell(
        onTap: onClearReaction,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(display.emoji, style: const TextStyle(fontSize: 16)),
              if (post.likeCount > 0) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  fmtCount(post.likeCount),
                  style: const TextStyle(
                    color: AppColors.like,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showDialog<ReactionType>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => _ReactionPickerOverlay(current: post.myReaction),
    );
    if (selected == null) return;
    if (selected == post.myReaction) {
      onClearReaction?.call();
    } else {
      onReact?.call(selected);
    }
  }
}

/// A small centered horizontal popover of the 6 reaction emojis. Returns the
/// tapped [ReactionType] (or null when dismissed). The currently-selected
/// reaction is highlighted so tapping it again reads as a clear.
class _ReactionPickerOverlay extends StatelessWidget {
  const _ReactionPickerOverlay({this.current});

  final ReactionType? current;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final entry in kReactionDisplay.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message: entry.value.label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(context).pop(entry.key),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: entry.key == current
                              ? AppColors.accent.withValues(alpha: 0.18)
                              : Colors.transparent,
                        ),
                        child: Text(
                          entry.value.emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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

/// The single-media block (single image or single video). Reads the post's
/// first attachment via the polymorphic model.
class _Media extends StatelessWidget {
  const _Media({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final attachment = post.attachments.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: _AttachmentImage(
          url: attachment.url,
          isVideo: attachment.type == AttachmentType.video,
        ),
      ),
    );
  }
}

/// A swipeable multi-image carousel for a [PostKind.carousel] post.
///
/// A horizontal [PageView] of the ordered attachments inside the SAME
/// ClipRRect/AspectRatio frame as [_Media], with dot page-indicators and a
/// '1/N' counter overlay. Each page uses the same Image.network
/// loading/error fallbacks as the single-media path, and video attachments
/// keep the play-button overlay.
class _Carousel extends StatefulWidget {
  const _Carousel({required this.attachments});

  final List<PostAttachment> attachments;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  final PageController _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.attachments;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PageView.builder(
              controller: _controller,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                final attachment = items[i];
                return _AttachmentImage(
                  url: attachment.url,
                  isVideo: attachment.type == AttachmentType.video,
                );
              },
            ),
            // '1/N' counter overlay (top-right).
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    '${_current + 1}/${items.length}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ),
            // Dot page-indicators (bottom-center).
            Positioned(
              bottom: AppSpacing.sm,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (var i = 0; i < items.length; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _current
                            ? AppColors.white
                            : const Color(0x80FFFFFF),
                      ),
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

/// A single network image page shared by [_Media] and [_Carousel]: the same
/// [Image.network] loading/error fallbacks, plus the video play-button overlay
/// when [isVideo] is true.
class _AttachmentImage extends StatelessWidget {
  const _AttachmentImage({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Stack(
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
        if (isVideo)
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
