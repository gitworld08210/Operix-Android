import 'package:flutter/material.dart';

/// Centralized color palette for Oneleven, matching the modern-X (current
/// Twitter/X) look: true-black, dark-first, X-blue accent. No gradients,
/// no glassmorphism.
abstract final class AppColors {
  const AppColors._();

  /// True-black app background.
  static const Color background = Color(0xFF000000);

  /// Surface / hover / elevated card color.
  static const Color surface = Color(0xFF16181C);

  /// Alias kept for readability where a hover tint is meant.
  static const Color hover = Color(0xFF16181C);

  /// Hairline border / divider.
  static const Color border = Color(0xFF2F3336);

  /// Primary (high-emphasis) text.
  static const Color primaryText = Color(0xFFE7E9EA);

  /// Secondary / muted text.
  static const Color secondaryText = Color(0xFF71767B);

  /// Accent: X blue.
  static const Color accent = Color(0xFF1D9BF0);

  /// Like / rose (pink).
  static const Color like = Color(0xFFF91880);

  /// Repost / green.
  static const Color repost = Color(0xFF00BA7C);

  /// Subscribe / premium magenta. Used for X's "Subscribe" button and other
  /// premium/creator upsell accents. Distinct from [like] to avoid confusing
  /// engagement pink with the commerce/subscribe magenta.
  static const Color subscribe = Color(0xFFC9379D);

  /// Premium badge blue tint. A softer blue used for premium/verified badge
  /// backgrounds and promo tints so it reads as a subtle wash rather than the
  /// full-strength [accent].
  static const Color premiumBlue = Color(0xFF1DA1F2);

  /// Pure white helper.
  static const Color white = Color(0xFFFFFFFF);

  /// Fully transparent helper.
  static const Color transparent = Color(0x00000000);
}
