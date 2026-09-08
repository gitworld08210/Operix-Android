import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../data/story_repository.dart';
import '../screens/story_viewer_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'avatar.dart';

/// A horizontally-scrollable row of circular story avatars shown at the top of
/// the home feed.
///
/// Each active author is one tile: a GRADIENT ring when the group has unseen
/// stories, a muted/gray ring when all its stories are seen. The current user's
/// own tile always leads and carries a '+' add affordance. Tapping a tile opens
/// the full-screen [StoryViewerScreen] for that author's active stories.
///
/// Listens to [StoryRepository.instance] via an [AnimatedBuilder] so seen/unseen
/// state (and hydrated live stories) rebuild the ring. Renders nothing when
/// there are no active groups (keeps the feed unchanged when stories are off).
class StoryRing extends StatelessWidget {
  const StoryRing({super.key});

  /// The unseen-ring gradient (Instagram-like sweep of the app accents).
  static const List<Color> _unseenGradient = <Color>[
    AppColors.accent,
    AppColors.like,
    Color(0xFFFF7A00),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StoryRepository.instance,
      builder: (context, _) {
        final groups = StoryRepository.instance.activeStoryGroups();
        final me = ProfileRepository.instance.currentUser;
        final hasOwnGroup =
            groups.isNotEmpty && groups.first.author.id == me.id;

        // Nothing to show and no own story: render nothing so the feed is
        // visually unchanged.
        if (groups.isEmpty) return const SizedBox.shrink();

        return DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                final isOwn = index == 0 && hasOwnGroup;
                return _StoryTile(
                  displayName: isOwn ? 'Your story' : group.author.displayName,
                  avatarUrl: group.author.avatarUrl,
                  hasUnseen: group.hasUnseen,
                  showAdd: isOwn,
                  onTap: () => _openViewer(context, index),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openViewer(BuildContext context, int startGroupIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StoryViewerScreen(startGroupIndex: startGroupIndex),
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.displayName,
    required this.avatarUrl,
    required this.hasUnseen,
    required this.showAdd,
    required this.onTap,
  });

  final String displayName;
  final String? avatarUrl;
  final bool hasUnseen;
  final bool showAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const double ringSize = 64;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: ringSize,
                  height: ringSize,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Gradient ring for unseen, flat muted ring for all-seen.
                    gradient: hasUnseen
                        ? const SweepGradient(colors: StoryRing._unseenGradient)
                        : null,
                    color: hasUnseen ? null : AppColors.border,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background,
                    ),
                    child: Avatar(
                      url: avatarUrl,
                      displayName: displayName,
                      size: ringSize - 10,
                    ),
                  ),
                ),
                if (showAdd)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                        border: Border.all(
                          color: AppColors.background,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 14,
                        color: AppColors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}
