import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/auth_repository.dart';
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

  // A pending image attachment picked from the gallery/camera. The bytes are
  // uploaded to the `post-media` bucket on Post; until then we hold them so the
  // compose UI can show a preview and the user can remove them.
  Uint8List? _pendingImageBytes;
  String _pendingImageExt = 'jpg';

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

  // A post is valid when it has text within the limit, or an attached image.
  bool get _canPost =>
      (_length > 0 || _pendingImageBytes != null) && _length <= _maxChars;

  bool _posting = false;

  Future<void> _post() async {
    if (!_canPost || _posting) return;
    final user = ProfileRepository.instance.currentUser;
    if (user == null) return; // must be signed in and loaded
    setState(() => _posting = true);

    // Upload any attached image first so the post row can carry its media_url.
    String? mediaUrl;
    var mediaType = MediaType.none;
    final imageBytes = _pendingImageBytes;
    if (imageBytes != null) {
      final userId = AuthRepository.instance.currentUser?.id;
      if (userId != null) {
        try {
          mediaUrl = await StorageService.uploadPostImage(
            userId: userId,
            bytes: imageBytes,
            ext: _pendingImageExt,
          );
          mediaType = MediaType.image;
        } catch (_) {
          if (!mounted) return;
          setState(() => _posting = false);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Could not upload the image. Please try again.'),
              ),
            );
          return;
        }
      }
    }

    final post = Post(
      // A client-generated UUID so the in-memory id equals the persisted DB
      // row id (the posts.id uuid column accepts it). See utils/ids.dart.
      id: newUuidV4(),
      author: user,
      content: _controller.text.trim(),
      mediaUrl: mediaUrl,
      mediaType: mediaType,
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

  // Uploads a picked video as a reel: stores the bytes in the `reels` storage
  // bucket, writes a first-class row into the `reels` table, and surfaces the
  // reel in the timeline as a video post. The byte source (gallery/camera) is
  // wired via image_picker in _pickVideo below.
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

  // Opens a sheet to attach media. Images are attached to the composed post
  // (uploaded on Post); videos are uploaded immediately as a reel and the
  // compose screen closes. Picking is wired via image_picker.
  Future<void> _onAddMedia() async {
    final choice = await showModalBottomSheet<_MediaChoice>(
      context: context,
      backgroundColor: AppColors.background,
      builder: (_) => const _MediaPickerSheet(),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _MediaChoice.photoLibrary:
        await _pickImage(ImageSource.gallery);
      case _MediaChoice.photoCamera:
        await _pickImage(ImageSource.camera);
      case _MediaChoice.videoLibrary:
        await _pickVideo(ImageSource.gallery);
    }
  }

  /// Picks an image from [source] and stages it as a pending attachment; the
  /// bytes are uploaded to `post-media` when the user taps Post. Handles the
  /// user-cancelled case (null) gracefully.
  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return; // cancelled
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageExt = _extensionOf(picked.name);
    });
  }

  /// Picks a video from [source], uploads it as a reel, and closes compose.
  /// Handles the user-cancelled case (null) gracefully.
  Future<void> _pickVideo(ImageSource source) async {
    final userId = AuthRepository.instance.currentUser?.id;
    if (userId == null) return; // must be signed in
    final XFile? picked = await ImagePicker().pickVideo(source: source);
    if (picked == null || !mounted) return; // cancelled
    setState(() => _posting = true);
    final bytes = await picked.readAsBytes();
    try {
      await _uploadReel(userId, bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not upload the video. Please try again.'),
          ),
        );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _removeImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingImageExt = 'jpg';
    });
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          TextField(
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
                              hintStyle:
                                  AppTextStyles.handle.copyWith(fontSize: 18),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          if (_pendingImageBytes != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            _ImagePreview(
                              bytes: _pendingImageBytes!,
                              onRemove: _posting ? null : _removeImage,
                            ),
                          ],
                        ],
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
          // Attach media: opens a picker sheet for a photo (gallery/camera) or
          // a video (uploaded as a reel). Wired via image_picker.
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

/// The kind of media the user chose from the picker sheet.
enum _MediaChoice { photoLibrary, photoCamera, videoLibrary }

/// Bottom sheet offering photo (gallery/camera) or video (gallery) sources.
class _MediaPickerSheet extends StatelessWidget {
  const _MediaPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.accent),
            title: Text('Photo from library', style: AppTextStyles.body),
            onTap: () =>
                Navigator.of(context).pop(_MediaChoice.photoLibrary),
          ),
          ListTile(
            leading:
                const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
            title: Text('Take a photo', style: AppTextStyles.body),
            onTap: () => Navigator.of(context).pop(_MediaChoice.photoCamera),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined, color: AppColors.accent),
            title: Text('Video from library', style: AppTextStyles.body),
            onTap: () =>
                Navigator.of(context).pop(_MediaChoice.videoLibrary),
          ),
        ],
      ),
    );
  }
}

/// Preview of a staged image attachment with a remove button.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.md),
          child: Image.memory(
            bytes,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, color: AppColors.white, size: 18),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    );
  }
}

/// Returns a lowercase file extension for [fileName] (without the dot),
/// defaulting to `jpg` when there is none. Used to key uploaded images.
String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'jpg';
  return fileName.substring(dot + 1).toLowerCase();
}
