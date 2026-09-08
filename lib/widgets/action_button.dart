import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/format.dart';

/// A single post action: an icon, an optional formatted count, and an
/// active/idle color. Used for reply / repost / like / views / bookmark /
/// share in [PostCard].
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    this.activeIcon,
    this.count,
    this.active = false,
    this.activeColor = AppColors.accent,
    this.onTap,
    this.tooltip,
  });

  /// Idle icon.
  final IconData icon;

  /// Optional icon shown when [active] is true (e.g. a filled heart).
  final IconData? activeIcon;

  /// Optional count rendered next to the icon.
  final int? count;

  /// Whether this action is in its active/engaged state.
  final bool active;

  /// Color used for the icon + count when [active] is true.
  final Color activeColor;

  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : AppColors.secondaryText;
    final displayIcon = active ? (activeIcon ?? icon) : icon;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(displayIcon, size: 18, color: color),
        if (count != null && count! > 0) ...<Widget>[
          const SizedBox(width: 6),
          Text(
            fmtCount(count!),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );

    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      splashColor: activeColor.withOpacity(0.12),
      highlightColor: activeColor.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: row,
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
