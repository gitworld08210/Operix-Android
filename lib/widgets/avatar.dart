import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A circular avatar. Shows a network image when [url] is provided (with
/// loading + error fallbacks), otherwise a colored circle with initials.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.url,
    this.displayName = '',
    this.size = 44,
    this.ring = false,
  });

  /// Optional avatar image URL.
  final String? url;

  /// Used to derive initials for the fallback.
  final String displayName;

  /// Diameter of the avatar in logical pixels.
  final double size;

  /// Whether to draw a subtle background ring (used on profile headers).
  final bool ring;

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    final first = parts.first.characters.first;
    final last = parts.last.characters.first;
    return '$first$last'.toUpperCase();
  }

  Color get _seedColor {
    if (displayName.isEmpty) return AppColors.surface;
    final hash = displayName.codeUnits.fold<int>(0, (a, b) => a + b);
    const palette = <Color>[
      Color(0xFF1D9BF0),
      Color(0xFF00BA7C),
      Color(0xFFF91880),
      Color(0xFF7856FF),
      Color(0xFFFF7A00),
      Color(0xFF1B95E0),
    ];
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _Fallback(
      size: size,
      initials: _initials,
      color: _seedColor,
    );

    Widget child;
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) {
      child = placeholder;
    } else {
      child = Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, widget, progress) {
          if (progress == null) return widget;
          return placeholder;
        },
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }

    final avatar = ClipOval(
      child: SizedBox(width: size, height: size, child: child),
    );

    if (!ring) return avatar;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
      ),
      child: avatar,
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.size,
    required this.initials,
    required this.color,
  });

  final double size;
  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: color,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
