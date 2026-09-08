import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Maps a [verificationKind] to an icon + color, mirroring the web
/// VerificationBadge. Defaults to a blue check for 'verified'.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({
    super.key,
    required this.kind,
    this.size = 16,
  });

  final String kind;
  final double size;

  static const Color _creator = Color(0xFFFFD400);
  static const Color _gov = Color(0xFF829AAB);
  static const Color _brand = Color(0xFFE2B719);
  static const Color _founder = Color(0xFFF7B928);

  _BadgeSpec get _spec {
    switch (kind) {
      case 'creator':
      case 'public_figure':
        return const _BadgeSpec(Icons.auto_awesome, _creator);
      case 'gov':
      case 'government':
        return const _BadgeSpec(Icons.account_balance, _gov);
      case 'brand':
      case 'business':
        return const _BadgeSpec(Icons.star, _brand);
      case 'founder':
        return const _BadgeSpec(Icons.workspace_premium, _founder);
      case 'media':
      case 'verified':
      default:
        return const _BadgeSpec(Icons.verified, AppColors.accent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    return Icon(spec.icon, color: spec.color, size: size);
  }
}

class _BadgeSpec {
  const _BadgeSpec(this.icon, this.color);

  final IconData icon;
  final Color color;
}
