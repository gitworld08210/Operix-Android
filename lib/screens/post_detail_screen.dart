import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/post_card.dart';
import 'profile_screen.dart';

/// Opens [ProfileScreen] for [authorId], fetching the profile if needed.
Future<void> openAuthorProfile(BuildContext context, String authorId) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final profile = await ProfileRepository.instance.profileById(authorId);
  if (profile == null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not open that profile.')),
      );
    return;
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(profile: profile),
    ),
  );
}

/// Opens the detail screen for [post]. When [focusReply] is true the reply
/// composer is focused on open (used by the Reply action).
Future<void> openPostDetail(
  BuildContext context,
  Post post, {
  bool focusReply = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PostDetailScreen(post: post, focusReply: focusReply),
    ),
  );
}

/// Copies a shareable link for [post] to the clipboard and confirms via a
/// snackbar. There is no share-sheet package bundled (INTEGRATIONS_ONLY), so
/// share is implemented purely with the Flutter SDK [Clipboard].
Future<void> sharePost(BuildContext context, Post post) async {
  final messenger = ScaffoldMessenger.of(context);
  final link = 'https://oneleven.app/post/${post.id}';
  await Clipboard.setData(ClipboardData(text: link));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
}

/// A post detail view: the parent [PostCard], its threaded replies, and a
/// reply composer at the bottom. Replies are loaded from
/// [PostRepository.replies] and a new reply is inserted via
/// [PostRepository.addReply], which also refreshes the parent reply count.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.post,
    this.focusReply = false,
  });

  final Post post;
  final bool focusReply;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  late Post _parent;
  List<Post> _replies = const <Post>[];
  bool _loading = true;
  bool _error = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _parent = widget.post;
    _loadReplies();
    if (widget.focusReply) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _replyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadReplies() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final repo = PostRepository.instance;
    final replies = await repo.replies(_parent.id);
    if (!mounted) return;
    // Refresh the parent's reply count from the cache if available.
    final cached = repo.postById(_parent.id);
    setState(() {
      _replies = replies;
      _parent = cached ?? _parent;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final repo = PostRepository.instance;
    final reply = await repo.addReply(parentId: _parent.id, content: text);
    if (!mounted) return;
    if (reply == null) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not post your reply.')),
        );
      return;
    }
    _controller.clear();
    final cached = repo.postById(_parent.id);
    setState(() {
      _replies = <Post>[..._replies, reply];
      _parent = cached ?? _parent.copyWith(replyCount: _parent.replyCount + 1);
      _sending = false;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: AnimatedBuilder(
              animation: PostRepository.instance,
              builder: (context, _) {
                final repo = PostRepository.instance;
                final live = repo.postById(_parent.id) ?? _parent;
                return ListView(
                  children: <Widget>[
                    PostCard(
                      post: live,
                      onLike: () => repo.toggleLike(live.id),
                      onRepost: () => repo.toggleRepost(live.id),
                      onBookmark: () => repo.toggleBookmark(live.id),
                      onReply: () => _replyFocus.requestFocus(),
                      onShare: () => sharePost(context, live),
                      onAuthorTap: () =>
                          openAuthorProfile(context, live.author.id),
                    ),
                    _RepliesSection(
                      loading: _loading,
                      error: _error,
                      replies: _replies,
                      onRetry: _loadReplies,
                    ),
                  ],
                );
              },
            ),
          ),
          _ReplyComposer(
            controller: _controller,
            focusNode: _replyFocus,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _RepliesSection extends StatelessWidget {
  const _RepliesSection({
    required this.loading,
    required this.error,
    required this.replies,
    required this.onRetry,
  });

  final bool loading;
  final bool error;
  final List<Post> replies;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }
    if (error) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Could not load replies.', style: AppTextStyles.handle),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (replies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text(
            'No replies yet. Start the conversation.',
            style: AppTextStyles.handle,
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final reply in replies) _ReplyTile(reply: reply),
      ],
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.reply});

  final Post reply;

  @override
  Widget build(BuildContext context) {
    final author = reply.author;
    return InkWell(
      onTap: () => openPostDetail(context, reply),
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
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            GestureDetector(
              onTap: () => openAuthorProfile(context, author.id),
              child: Avatar(
                url: author.avatarUrl,
                displayName: author.displayName,
                size: 36,
              ),
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
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          author.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.handle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(reply.content, style: AppTextStyles.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final user = ProfileRepository.instance.currentUser;
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
            _ComposerAvatar(user: user),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                cursorColor: AppColors.accent,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: AppTextStyles.body,
                decoration: const InputDecoration(
                  hintText: 'Post your reply',
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
              tooltip: 'Reply',
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerAvatar extends StatelessWidget {
  const _ComposerAvatar({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    return Avatar(
      url: user?.avatarUrl,
      displayName: user?.displayName ?? 'You',
      size: 32,
    );
  }
}
