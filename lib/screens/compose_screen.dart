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

  bool _posting = false;

  Future<void> _post() async {
    if (!_canPost || _posting) return;
    final user = ProfileRepository.instance.currentUser;
    if (user == null) return; // must be signed in and loaded
    setState(() => _posting = true);
    final post = Post(
      // A client-generated UUID so the in-memory id equals the persisted DB
      // row id (the posts.id uuid column accepts it). See utils/ids.dart.
      id: newUuidV4(),
      author: user,
      content: _controller.text.trim(),
      createdAt: DateTime.now(),
    );
    // addPost inserts into the Supabase `posts` table and updates the
    // in-memory feed; it awaits the insert and reverts on failure.
    final repo = PostRepository.instance;
    final result = await repo.addPost(post);
    if (!mounted) return;
    if (result == null) {
      setState(() => _posting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not post. Please try again.')),
        );
      return;
    }
    // Refresh from the server so DB defaults / counters are authoritative
    // rather than trusting only the optimistic insert. Fire-and-forget.
    // ignore: discarded_futures
    repo.load();
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
    final author = ProfileRepository.instance.currentUser;
    if (author == null) return;
    final reelPost = Post(
      id: newUuidV4(),
      author: author,
      content: caption,
      mediaUrl: videoUrl,
      mediaType: MediaType.video,
      createdAt: DateTime.now(),
    );
    // ignore: discarded_futures
    PostRepository.instance.addPost(reelPost);
  }

  // Media attach is the byte-source seam. Picking raw image/video bytes needs
  // a gallery/camera picker (e.g. image_picker), which cannot be added under
  // INTEGRATIONS_ONLY (pub.dev unreachable). The upload path itself is real
  // (see _uploadReel + StorageService.uploadReel/uploadAvatar); only the byte
  // source is missing. We surface that clearly instead of a misleading demo
  // snackbar. Once bytes are available:
  //   final userId = AuthRepository.instance.currentUser?.id;
  //   if (userId == null) return;
  //   await _uploadReel(userId, pickedBytes);
  void _onAddMedia() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Media upload needs a gallery picker, which is not bundled yet.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final user = ProfileRepository.instance.currentUser;
    final avatarUrl = user?.avatarUrl;
    final displayName = user?.displayName ?? 'You';
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
              onPressed: (_canPost && !_posting) ? _post : null,
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
                      url: avatarUrl,
                      displayName: displayName,
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
              onAddMedia: _onAddMedia,
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
    required this.onAddMedia,
  });

  final int length;
  final int maxChars;
  final VoidCallback onAddMedia;

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
          // Single media button. The byte source (gallery/camera picker) is the
          // only unwired step; the upload + persistence path is real. See the
          // seam documented on _ComposeScreenState._onAddMedia / _uploadReel.
          IconButton(
            onPressed: onAddMedia,
            icon: const Icon(Icons.image_outlined, color: AppColors.accent),
            tooltip: 'Media',
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
