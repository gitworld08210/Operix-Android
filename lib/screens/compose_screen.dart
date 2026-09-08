import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../data/storage_service.dart';
import '../models/post.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/ids.dart';
import '../widgets/avatar.dart';

/// Full-screen compose route. Building a [Post] from the current profile and
/// the entered text, then popping.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final TextEditingController _controller = TextEditingController();
  static const int _maxChars = 280;
  int _length = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _length = _controller.text.characters.length);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canPost => _length > 0 && _length <= _maxChars;

  void _post() {
    if (!_canPost) return;
    final user = ProfileRepository.instance.currentUser;
    final post = Post(
      // A client-generated UUID so the in-memory id equals the persisted DB
      // row id (the posts.id uuid column accepts it). See utils/ids.dart.
      id: newUuidV4(),
      author: user,
      content: _controller.text.trim(),
      createdAt: DateTime.now(),
    );
    // addPost updates the in-memory feed immediately and persists the post to
    // the Supabase `posts` table in the background (fire-and-forget).
    PostRepository.instance.addPost(post);
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // SCAFFOLD: reel upload call site.
  //
  // Composing a reel needs raw video bytes from the device. No file/image
  // picker dependency is bundled (deps are kept minimal), so ONLY the
  // byte-source (gallery/camera picker) is left as a TODO. The rest of the
  // flow below is real: it uploads to the `reels` storage bucket AND writes a
  // first-class row into the `reels` table (so that table is not dead), then
  // surfaces the reel in the timeline as a video post. Once bytes are
  // available, `_uploadReel` runs end-to-end.
  //
  //   final userId = AuthRepository.instance.currentUser?.id;
  //   if (userId == null) return; // must be signed in
  //   final Uint8List bytes = /* TODO: pick from gallery/camera */;
  //   await _uploadReel(userId, bytes);
  //
  // StorageService.uploadReel is imported and ready; wiring a picker is the
  // only remaining step.
  // ignore: unused_element
  Future<void> _uploadReel(String userId, Uint8List bytes) async {
    final videoUrl = await StorageService.uploadReel(
      userId: userId,
      bytes: bytes,
    );
    final caption = _controller.text.trim();
    // Persist the reel metadata into its first-class `reels` table (owner,
    // video_url, caption). This is the real home for reel metadata; the
    // storage object above holds only the bytes. Fire-and-forget + guarded so
    // it never throws into the UI, matching the repositories' pattern.
    await StorageService.insertReel(
      userId: userId,
      videoUrl: videoUrl,
      caption: caption,
    );
    // Also surface the reel in the main timeline as a video post so it is
    // immediately visible. (A dedicated reels feed reading from the `reels`
    // table is a future step.)
    final reelPost = Post(
      id: newUuidV4(),
      author: ProfileRepository.instance.currentUser,
      content: caption,
      mediaUrl: videoUrl,
      mediaType: MediaType.video,
      createdAt: DateTime.now(),
    );
    PostRepository.instance.addPost(reelPost);
  }

  void _mockAttach(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label is not available in this demo')));
  }

  @override
  Widget build(BuildContext context) {
    final user = ProfileRepository.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: ElevatedButton(
              onPressed: _canPost ? _post : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
                foregroundColor: AppColors.white,
                disabledForegroundColor: AppColors.white,
              ),
              child: const Text('Post'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Avatar(
                      url: user.avatarUrl,
                      displayName: user.displayName,
                      size: 44,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        maxLines: null,
                        minLines: 4,
                        cursorColor: AppColors.accent,
                        style: AppTextStyles.body.copyWith(fontSize: 18),
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: "What's happening?",
                          hintStyle: AppTextStyles.handle.copyWith(fontSize: 18),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Toolbar(
              length: _length,
              maxChars: _maxChars,
              onAttach: _mockAttach,
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.length,
    required this.maxChars,
    required this.onAttach,
  });

  final int length;
  final int maxChars;
  final void Function(String label) onAttach;

  @override
  Widget build(BuildContext context) {
    final remaining = maxChars - length;
    final overLimit = remaining < 0;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => onAttach('Photos'),
            icon: const Icon(Icons.image_outlined, color: AppColors.accent),
            tooltip: 'Media',
          ),
          IconButton(
            onPressed: () => onAttach('GIF'),
            icon: const Icon(Icons.gif_box_outlined, color: AppColors.accent),
            tooltip: 'GIF',
          ),
          IconButton(
            onPressed: () => onAttach('Poll'),
            icon: const Icon(Icons.poll_outlined, color: AppColors.accent),
            tooltip: 'Poll',
          ),
          const Spacer(),
          Text(
            '$length/$maxChars',
            style: AppTextStyles.caption.copyWith(
              color: overLimit ? AppColors.like : AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
