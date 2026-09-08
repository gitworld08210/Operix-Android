import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../data/safety_repository.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar.dart';

/// Which safety set a [BlockedMutedScreen] manages.
enum SafetyListKind {
  /// Blocked accounts (server-backed via public.blocks).
  blocked,

  /// Muted accounts (client-authoritative, in-memory this phase).
  muted,
}

/// Lists the accounts in one safety set ([SafetyListKind.blocked] or
/// [SafetyListKind.muted]) with an unblock/unmute affordance per row.
///
/// Reachable from [SettingsScreen]'s Privacy & Safety section. Ids are resolved
/// to profiles via [ProfileRepository.profiles]; an id with no known profile
/// still renders with a lightweight placeholder so it can always be removed.
/// Listens via `AnimatedBuilder(animation: SafetyRepository.instance)` so the
/// list updates reactively as entries are removed.
class BlockedMutedScreen extends StatelessWidget {
  const BlockedMutedScreen({super.key, required this.kind});

  final SafetyListKind kind;

  bool get _isBlocked => kind == SafetyListKind.blocked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isBlocked ? 'Blocked accounts' : 'Muted accounts'),
      ),
      body: AnimatedBuilder(
        animation: SafetyRepository.instance,
        builder: (context, _) {
          final safety = SafetyRepository.instance;
          final ids = _isBlocked ? safety.blockedIds : safety.mutedIds;
          if (ids.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  _isBlocked
                      ? 'You have not blocked anyone.'
                      : 'You have not muted anyone.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.handle,
                ),
              ),
            );
          }
          final profiles = ProfileRepository.instance.profiles;
          final rows = ids.toList();
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final id = rows[index];
              final profile = _resolve(profiles, id);
              return _SafetyRow(
                profile: profile,
                id: id,
                isBlocked: _isBlocked,
                onRemove: () {
                  if (_isBlocked) {
                    safety.unblock(id);
                  } else {
                    safety.unmute(id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  UserProfile? _resolve(List<UserProfile> profiles, String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({
    required this.profile,
    required this.id,
    required this.isBlocked,
    required this.onRemove,
  });

  final UserProfile? profile;
  final String id;
  final bool isBlocked;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.displayName ?? 'Unknown account';
    final handle = profile != null ? '@${profile!.username}' : id;
    return ListTile(
      leading: Avatar(
        url: profile?.avatarUrl,
        displayName: displayName,
        size: 40,
      ),
      title: Text(displayName, style: AppTextStyles.name),
      subtitle: Text(handle, style: AppTextStyles.handle),
      trailing: OutlinedButton(
        onPressed: onRemove,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryText,
          side: const BorderSide(color: AppColors.border),
          shape: const StadiumBorder(),
        ),
        child: Text(isBlocked ? 'Unblock' : 'Unmute'),
      ),
    );
  }
}
