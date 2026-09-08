import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../models/user_profile.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/placeholder_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_scaffold.dart';
import 'avatar.dart';

/// The X-style left navigation drawer, opened from the Home top-bar avatar.
///
/// Header shows the signed-in user's avatar, display name, @handle and a
/// 'N Following  M Followers' row (live via [ProfileRepository]). The menu
/// routes Profile and Bookmarks to their real screens, while the remaining
/// entries share a single honest [PlaceholderScreen]. The bottom carries an
/// informational theme control (the app is dark-only) that stays honest about
/// not switching themes.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  /// Closes the drawer, then runs [action]. The drawer's own context stays
  /// valid for the remainder of this synchronous frame, so [action] (which
  /// pushes a route via the root navigator) resolves correctly.
  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _DrawerHeader(),
            const Divider(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _DrawerTile(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    onTap: () => _closeThen(context, () => openProfile(context)),
                  ),
                  _DrawerTile(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Premium',
                    trailing: const _DiscountBadge(),
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Premium'),
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.people_outline,
                    label: 'Communities',
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Communities'),
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.bookmark_border,
                    label: 'Bookmarks',
                    onTap: () => _closeThen(context, () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BookmarksScreen(),
                        ),
                      );
                    }),
                  ),
                  _DrawerTile(
                    icon: Icons.list_alt_outlined,
                    label: 'Lists',
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Lists'),
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.mic_none_outlined,
                    label: 'Spaces',
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Spaces'),
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.monetization_on_outlined,
                    label: 'Creator Studio',
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Creator Studio'),
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Get Grok',
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Get Grok'),
                    ),
                  ),
                  const Divider(),
                  _DrawerTile(
                    icon: Icons.settings_outlined,
                    label: 'Settings and privacy',
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Settings and privacy'),
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.help_outline,
                    label: 'Help Center',
                    onTap: () => _closeThen(
                      context,
                      () => _openPlaceholder(context, 'Help Center'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            const _ThemeControl(),
          ],
        ),
      ),
    );
  }

  void _openPlaceholder(BuildContext context, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderScreen(title: title),
      ),
    );
  }
}

/// Header: avatar, display name, @handle, and a following/followers row.
/// Rebuilds live with [ProfileRepository] and degrades gracefully to
/// placeholders before the current user has loaded.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProfileRepository.instance,
      builder: (context, _) {
        final UserProfile? user = ProfileRepository.instance.currentUser;
        final String displayName = user?.displayName ?? 'Sign in';
        final String handle = user != null ? user.handle : '@you';
        final int following = user?.following ?? 0;
        final int followers = user?.followers ?? 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Avatar(
                url: user?.avatarUrl,
                displayName: user?.displayName ?? '',
                size: 44,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                displayName,
                style: AppTextStyles.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                handle,
                style: AppTextStyles.handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  _CountItem(count: following, label: 'Following'),
                  const SizedBox(width: AppSpacing.lg),
                  _CountItem(count: followers, label: 'Followers'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A 'N Label' fragment (e.g. '128 Following') with a bold count.
class _CountItem extends StatelessWidget {
  const _CountItem({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(text: fmtCount(count), style: AppTextStyles.name),
          const TextSpan(text: ' '),
          TextSpan(text: label, style: AppTextStyles.handle),
        ],
      ),
    );
  }
}

/// A single menu row: leading outline icon, label, optional trailing widget.
class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryText),
      title: Text(label, style: AppTextStyles.title),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Small blue '50% off' promo chip shown next to the Premium entry.
class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Text(
        '50% off',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Bottom theme control. The app ships dark-only, so this is an honest,
/// disabled informational affordance rather than a fake toggle: it shows the
/// current (dark) theme and does not pretend to switch.
class _ThemeControl extends StatelessWidget {
  const _ThemeControl();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.dark_mode_outlined, color: AppColors.secondaryText),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Dark mode',
              style: AppTextStyles.title.copyWith(color: AppColors.secondaryText),
            ),
          ),
          // Honest: fixed-on, disabled — the app is dark-only and this does
          // not switch themes.
          Switch(
            value: true,
            onChanged: null,
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
