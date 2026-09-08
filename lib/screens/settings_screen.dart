import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/profile_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import 'blocked_muted_screen.dart';
import 'edit_profile_screen.dart';
import 'muted_words_screen.dart';

/// Account & settings surface, reachable from the profile screen.
///
/// Listens via `AnimatedBuilder(animation: ProfileRepository.instance)` so the
/// private-account toggle reflects `currentUser.isPrivate` reactively. Sections:
/// Account (edit profile, private-account toggle), Privacy & Safety (blocked +
/// muted account management, wired to [BlockedMutedScreen] in FEAT-006), Your
/// data (export + delete scaffolding), and Sign out (reusing
/// [AuthRepository.signOut]).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthRepository.instance.signOut();
      // The AuthGate listens to auth state and returns to AuthScreen.
      if (context.mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not sign out. Please try again.'),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _exportData(BuildContext context) async {
    final export = await ProfileRepository.instance.exportMyData();
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Your data', style: AppTextStyles.title),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${export.posts.length} posts and '
                    '${export.comments.length} comments assembled locally. '
                    'Server-side archive delivery is not available in this '
                    'build.',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadii.md),
                        ),
                        child: SelectableText(
                          export.toJsonString(),
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primaryText,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Delete account?'),
          content: Text(
            'This will permanently remove your account and data. This action '
            'cannot be undone.',
            style: AppTextStyles.body,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.like),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final result = await ProfileRepository.instance.requestAccountDeletion();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            result.succeeded ? 'Account deleted' : 'Not available',
            style: AppTextStyles.title,
          ),
          content: Text(result.message, style: AppTextStyles.body),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: ProfileRepository.instance,
        builder: (context, _) {
          final user = ProfileRepository.instance.currentUser;
          return ListView(
            children: <Widget>[
              const _SectionHeader('Account'),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Edit profile'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.secondaryText),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EditProfileScreen(),
                  ),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline),
                title: const Text('Private account'),
                subtitle: Text(
                  'When enabled, new followers must be approved.',
                  style: AppTextStyles.caption,
                ),
                value: user.isPrivate,
                activeThumbColor: AppColors.accent,
                onChanged: ProfileRepository.instance.setAccountPrivate,
              ),
              const Divider(),
              const _SectionHeader('Privacy & Safety'),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Blocked accounts'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.secondaryText),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BlockedMutedScreen(
                      kind: SafetyListKind.blocked,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.volume_off_outlined),
                title: const Text('Muted accounts'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.secondaryText),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BlockedMutedScreen(
                      kind: SafetyListKind.muted,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.tag_outlined),
                title: const Text('Muted words'),
                subtitle: Text(
                  'Hide posts containing words or phrases you choose.',
                  style: AppTextStyles.caption,
                ),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.secondaryText),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MutedWordsScreen(),
                  ),
                ),
              ),
              const Divider(),
              const _SectionHeader('Your data'),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export my data'),
                subtitle: Text(
                  'Assemble a copy of your profile, posts, and comments.',
                  style: AppTextStyles.caption,
                ),
                onTap: () => _exportData(context),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.like),
                title: Text(
                  'Delete account',
                  style: AppTextStyles.body.copyWith(color: AppColors.like),
                ),
                onTap: () => _deleteAccount(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () => _signOut(context),
              ),
            ],
          );
        },
      ),
    );
  }

}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.label.copyWith(color: AppColors.secondaryText),
      ),
    );
  }
}
