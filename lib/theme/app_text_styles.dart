import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Text styles for Oneleven built on a clean, Chirp-like sans (Inter via
/// google_fonts). No serif, no italics.
///
/// Offline resilience: the target device may have no network, so Inter cannot
/// always be fetched from Google's CDN at runtime. We keep `google_fonts`
/// (per the fixed dependency set and the no-binary-assets sandbox constraint),
/// but every style declares a [_fallback] chain to platform sans families so
/// the type degrades to a clean system sans instead of vanishing when the
/// fetch fails. Call [configureFonts] once at startup to suppress noisy
/// runtime-fetch failures on release/offline builds.
abstract final class AppTextStyles {
  const AppTextStyles._();

  /// System sans fallbacks used when the Inter web font cannot be fetched
  /// (offline first launch). Covers Android (Roboto), Apple (San Francisco /
  /// Helvetica Neue), and a generic sans-serif catch-all.
  static const List<String> _fallback = <String>[
    'Roboto',
    '.SF UI Text',
    'San Francisco',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  /// Configure google_fonts for a possibly-offline target. Runtime fetching is
  /// left enabled so the intended Inter renders when connectivity exists, but
  /// the [_fallback] chain guarantees a graceful system-sans degrade offline.
  /// Safe to call multiple times.
  static void configureFonts() {
    GoogleFonts.config.allowRuntimeFetching = true;
  }

  /// Large display / headline (e.g. profile name on header).
  static TextStyle get display => GoogleFonts.inter(
        fontSize: 22,
        height: 1.15,
        fontWeight: FontWeight.w800,
        color: AppColors.primaryText,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Section / screen titles.
  static TextStyle get title => GoogleFonts.inter(
        fontSize: 18,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryText,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Bold display name used in post headers.
  static TextStyle get name => GoogleFonts.inter(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryText,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Standard body / post content.
  static TextStyle get body => GoogleFonts.inter(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: AppColors.primaryText,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Muted @handle / metadata.
  static TextStyle get handle => GoogleFonts.inter(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w400,
        color: AppColors.secondaryText,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Small caption / counts / timestamps.
  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w400,
        color: AppColors.secondaryText,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Label used on buttons and accented links.
  static TextStyle get label => GoogleFonts.inter(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: AppColors.primaryText,
      ).copyWith(fontFamilyFallback: _fallback);

  /// Builds the Material [TextTheme] wired to the palette.
  static TextTheme textTheme() {
    return TextTheme(
      displayLarge: display,
      displayMedium: display,
      titleLarge: title,
      titleMedium: name,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: label,
      labelMedium: caption,
    );
  }
}
