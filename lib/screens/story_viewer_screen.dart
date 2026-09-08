import 'package:flutter/material.dart';

import '../data/story_repository.dart';
import '../models/story.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';

/// A full-screen, tap-through story viewer (Instagram-style).
///
/// Displays the active story groups starting at [startGroupIndex]. Each story
/// auto-advances after [_storyDuration] via a single [AnimationController]
/// driving the segmented progress bars at the top. Tapping the RIGHT half
/// advances to the next story/group; tapping the LEFT half goes back. On
/// showing a story it calls [StoryRepository.markSeen]. The controller is
/// disposed in [dispose] so no timer leaks.
///
/// This widget is DISPLAY-ONLY: no device features are required. The grouping /
/// expiry / seen logic it renders lives in [StoryRepository] and is verified by
/// unit tests; the viewer just walks that data.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, this.startGroupIndex = 0});

  /// Which active group to open first (index into
  /// [StoryRepository.activeStoryGroups]).
  final int startGroupIndex;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  /// How long each story is shown before auto-advancing.
  static const Duration _storyDuration = Duration(seconds: 5);

  late final AnimationController _controller;

  /// Snapshot of the active groups taken when the viewer opened, so expiry
  /// during viewing does not reshuffle indices mid-walk.
  late List<StoryGroup> _groups;

  int _groupIndex = 0;
  int _storyIndex = 0;

  @override
  void initState() {
    super.initState();
    _groups = StoryRepository.instance.activeStoryGroups();
    _groupIndex = widget.startGroupIndex.clamp(
      0,
      _groups.isEmpty ? 0 : _groups.length - 1,
    );
    _controller = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });

    // If there is nothing to show, close after the first frame.
    if (_groups.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return;
    }
    _startCurrent();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  StoryGroup? get _currentGroup =>
      (_groupIndex >= 0 && _groupIndex < _groups.length)
          ? _groups[_groupIndex]
          : null;

  Story? get _currentStory {
    final group = _currentGroup;
    if (group == null) return null;
    if (_storyIndex < 0 || _storyIndex >= group.stories.length) return null;
    return group.stories[_storyIndex];
  }

  /// Marks the current story seen and (re)starts the progress animation.
  void _startCurrent() {
    final story = _currentStory;
    if (story == null) {
      _close();
      return;
    }
    // Mark seen: idempotent + single-notify in the repository.
    StoryRepository.instance.markSeen(story.id);
    _controller
      ..reset()
      ..forward();
  }

  void _next() {
    final group = _currentGroup;
    if (group == null) {
      _close();
      return;
    }
    if (_storyIndex < group.stories.length - 1) {
      setState(() => _storyIndex++);
      _startCurrent();
    } else if (_groupIndex < _groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _startCurrent();
    } else {
      _close(); // past the last story of the last group
    }
  }

  void _previous() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startCurrent();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = _groups[_groupIndex].stories.length - 1;
      });
      _startCurrent();
    } else {
      // Already at the very first story: restart it.
      _startCurrent();
    }
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _currentGroup;
    final story = _currentStory;
    if (group == null || story == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 3) {
            _previous();
          } else {
            _next();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _StoryMedia(url: story.mediaUrl),
            // Top scrim for readability of the progress bars + header.
            const _TopScrim(),
            SafeArea(
              child: Column(
                children: <Widget>[
                  _SegmentedProgress(
                    count: group.stories.length,
                    currentIndex: _storyIndex,
                    controller: _controller,
                  ),
                  _ViewerHeader(
                    story: story,
                    onClose: _close,
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

/// The story media, shown via [Image.network] with the shared loading/error
/// fallback treatment used across the app.
class _StoryMedia extends StatelessWidget {
  const _StoryMedia({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _MediaFallback();
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _MediaFallback(loading: true);
      },
      errorBuilder: (context, error, stackTrace) => const _MediaFallback(),
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: loading
            ? const CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.secondaryText)
            : const Icon(Icons.broken_image_outlined,
                size: 48, color: AppColors.secondaryText),
      ),
    );
  }
}

class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x99000000), Color(0x00000000)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The row of Instagram-style segmented progress bars; the active segment fills
/// as the [controller] animates, past segments are full, future ones empty.
class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({
    required this.count,
    required this.currentIndex,
    required this.controller,
  });

  final int count;
  final int currentIndex;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Row(
        children: List<Widget>.generate(count, (i) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _ProgressBar(
                fill: i < currentIndex
                    ? const AlwaysStoppedAnimation<double>(1)
                    : i == currentIndex
                        ? controller
                        : const AlwaysStoppedAnimation<double>(0),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fill});

  final Animation<double> fill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: AnimatedBuilder(
        animation: fill,
        builder: (context, _) {
          return LinearProgressIndicator(
            value: fill.value,
            minHeight: 3,
            backgroundColor: AppColors.white.withValues(alpha: 0.3),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.white),
          );
        },
      ),
    );
  }
}

class _ViewerHeader extends StatelessWidget {
  const _ViewerHeader({required this.story, required this.onClose});

  final Story story;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: <Widget>[
          Avatar(
            url: story.author.avatarUrl,
            displayName: story.author.displayName,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    story.author.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.name.copyWith(color: AppColors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeAgo(story.createdAt),
                  style: AppTextStyles.caption.copyWith(color: AppColors.white),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.white),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
