import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../data/storage_service.dart';
import '../models/post.dart';
import '../models/post_attachment.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/ids.dart';
import '../utils/text_entities.dart';
import '../utils/text_post.dart';
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
  // PHASE 4/5 SEAM: a free-text location this phase. A real place-picker /
  // geocoder (resolving to a place name + lat/lng) replaces this input later.
  final TextEditingController _locationController = TextEditingController();
  // The canonical text-post limit lives in utils/text_post.dart so the
  // composer, the char counter, and the validator read ONE source of truth.
  static const int _maxChars = kMaxTextPostChars;
  int _length = 0;

  /// Ordered image attachments assembled for this compose (carried BY URL).
  /// See [_attachDemoPhoto] and the PHASE 4 SEAM note there.
  final List<PostAttachment> _attachments = <PostAttachment>[];

  /// A small fixed pool of demo picsum seeds used to append URL-based image
  /// attachments without a device picker (see the PHASE 4 SEAM in
  /// [_attachDemoPhoto]).
  static const List<String> _demoPhotoSeeds = <String>[
    'compose1',
    'compose2',
    'compose3',
    'compose4',
  ];

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
    _locationController.dispose();
    super.dispose();
  }

  // A post is postable when it is a valid text-only tweet OR it carries at
  // least one attachment while staying within the character limit. The
  // text-only path is driven by the shared validateTextPost helper so the
  // composer, counter, and unit tests agree; attachment-post behavior is
  // unchanged (attachments alone remain postable as long as text isn't over
  // the limit).
  bool get _canPost {
    final validation = validateTextPost(_controller.text);
    if (_attachments.isNotEmpty) {
      return !validation.isOverLimit;
    }
    return validation.isValid;
  }

  void _post() {
    if (!_canPost) return;
    final user = ProfileRepository.instance.currentUser;
    // A client-generated UUID so the in-memory id equals the persisted DB row
    // id (the posts.id uuid column accepts it). See utils/ids.dart.
    final id = newUuidV4();
    // Re-key the assembled attachments onto the final post id and their
    // ordering, so the persisted post_attachments rows reference the post and
    // carry a stable (post_id, position). The Post constructor derives `kind`
    // from this list via deriveKind (0 => text, 1 image => image, >1 =>
    // carousel), so kind and attachments never disagree.
    final attachments = <PostAttachment>[
      for (var i = 0; i < _attachments.length; i++)
        _attachments[i].copyWith(id: '${id}_a$i', postId: id, position: i),
    ];
    final content = _controller.text.trim();
    final location = _locationController.text.trim();
    final post = Post(
      id: id,
      author: user,
      content: content,
      attachments: attachments,
      createdAt: DateTime.now(),
      // PHASE 4/5 SEAM: free-text location now; a place-picker/geocoder later
      // resolves lat/lng.
      location: location.isEmpty ? null : location,
    );
    // Extract the discovery entities from the caption using the SAME grammar
    // the card linkifier highlights (see utils/text_entities.dart), so the
    // post_hashtags/post_mentions relations match what the user sees.
    final hashtags = extractHashtags(content);
    final mentions = extractMentions(content);
    // addPost updates the in-memory feed immediately and persists the post,
    // its attachments, and the extracted relations in the background
    // (fire-and-forget).
    PostRepository.instance
        .addPost(post, hashtags: hashtags, mentions: mentions);
    Navigator.of(context).pop();
  }

  /// Appends a DEMO url-based image attachment so a single image or a
  /// multi-image CAROUSEL can be assembled and previewed by URL, WITHOUT a
  /// device picker.
  ///
  /// PHASE 4 SEAM: real gallery/camera capture replaces this URL-based demo
  /// attach. Here attachments are carried BY URL only (picsum placeholders);
  /// Phase 4 wires a real picker + upload to the storage bucket that populates
  /// the attachment url/thumbUrl from device bytes.
  void _attachDemoPhoto() {
    final seed = _demoPhotoSeeds[_attachments.length % _demoPhotoSeeds.length];
    setState(() {
      _attachments.add(
        PostAttachment(
          // Ids/positions are re-keyed onto the final post id in [_post];
          // these are placeholders for the in-progress preview.
          id: 'draft_a${_attachments.length}',
          postId: 'draft',
          position: _attachments.length,
          type: AttachmentType.image,
          url: 'https://picsum.photos/seed/$seed/900/600',
        ),
      );
    });
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
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
    final reelId = newUuidV4();
    final reelPost = Post(
      id: reelId,
      author: ProfileRepository.instance.currentUser,
      content: caption,
      // A reel surfaces as a single-video post: one video attachment (position
      // 0) whose url is the uploaded video. The Post constructor derives
      // kind=PostKind.video via deriveKind.
      attachments: <PostAttachment>[
        PostAttachment(
          id: '${reelId}_a0',
          postId: reelId,
          position: 0,
          type: AttachmentType.video,
          url: videoUrl,
        ),
      ],
      createdAt: DateTime.now(),
    );
    PostRepository.instance.addPost(reelPost);
  }

  /// Toolbar affordances that are not part of this phase (GIF, Poll) show a
  /// clearly-labeled placeholder. Photos routes to [_attachDemoPhoto] instead.
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
                disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
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
                              hintStyle:
                                  AppTextStyles.handle.copyWith(fontSize: 18),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_attachments.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      _AttachmentStrip(
                        attachments: _attachments,
                        onRemove: _removeAttachment,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // PHASE 4/5 SEAM: a free-text location field. A real
                    // place-picker/geocoder replaces this later, filling a
                    // place name + lat/lng.
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.place_outlined,
                          size: 20,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: _locationController,
                            cursorColor: AppColors.accent,
                            style: AppTextStyles.body,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: 'Add location',
                              hintStyle: AppTextStyles.handle,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _Toolbar(
              length: _length,
              maxChars: _maxChars,
              onAttach: _mockAttach,
              onAddPhoto: _attachDemoPhoto,
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
    required this.onAddPhoto,
  });

  final int length;
  final int maxChars;
  final void Function(String label) onAttach;
  final VoidCallback onAddPhoto;

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
            // PHASE 4 SEAM: real gallery/camera capture replaces this
            // URL-based demo attach. For now this appends a demo picsum image
            // attachment so a single image or a carousel can be assembled.
            onPressed: onAddPhoto,
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

/// A horizontal preview strip of the demo image attachments assembled for the
/// in-progress compose, each with a remove affordance. Attachments are carried
/// BY URL (see the PHASE 4 SEAM in [_ComposeScreenState._attachDemoPhoto]).
class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({required this.attachments, required this.onRemove});

  final List<PostAttachment> attachments;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final attachment = attachments[i];
          return Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Image.network(
                  attachment.url,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 96,
                    height: 96,
                    color: AppColors.surface,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => onRemove(i),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, color: AppColors.white, size: 16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
