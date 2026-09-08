import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// A single reusable, honest placeholder screen used by drawer entries that
/// have no real backend/data wiring yet (Premium, Communities, Lists, Spaces,
/// Creator Studio, Settings and privacy, Help Center).
///
/// It intentionally shows one clean, non-spammy "not available yet" message in
/// the X visual style rather than faking functionality.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  /// The section title shown in the AppBar (e.g. 'Premium', 'Lists').
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.construction_outlined,
                size: 48,
                color: AppColors.secondaryText,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                "This section isn't available yet.",
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Check back later.',
                textAlign: TextAlign.center,
                style: AppTextStyles.handle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
