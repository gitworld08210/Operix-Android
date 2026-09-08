import 'package:flutter/material.dart';

import '../data/safety_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// Manages the viewer's muted keywords/phrases, reachable from
/// [SettingsScreen]'s Privacy & Safety section.
///
/// Mute words are client-authoritative (no server table this phase): any post
/// whose content matches a muted word on a WORD BOUNDARY is hidden from the
/// feed via [SafetyRepository]'s pure [contentMatchesMuteWords] matcher on the
/// feed-filter path. Adds are validated (non-empty after trimming, no longer
/// than [SafetyRepository.maxMuteWordLength]); the repository normalizes
/// (trims + lower-cases) and de-dupes. Listens via
/// `AnimatedBuilder(animation: SafetyRepository.instance)` so the list updates
/// reactively.
class MutedWordsScreen extends StatefulWidget {
  const MutedWordsScreen({super.key});

  @override
  State<MutedWordsScreen> createState() => _MutedWordsScreenState();
}

class _MutedWordsScreenState extends State<MutedWordsScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      _snack('Enter a word or phrase to mute.');
      return;
    }
    if (raw.length > SafetyRepository.maxMuteWordLength) {
      _snack(
        'Mute words must be ${SafetyRepository.maxMuteWordLength} characters '
        'or fewer.',
      );
      return;
    }
    SafetyRepository.instance.addMuteWord(raw);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Muted words')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Posts containing a muted word are hidden from your feed. '
                  'Matching is case-insensitive and respects word boundaries.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.done,
                        maxLength: SafetyRepository.maxMuteWordLength,
                        onSubmitted: (_) => _add(),
                        decoration: const InputDecoration(
                          hintText: 'Add a word or phrase',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: _add,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 0.5),
          Expanded(
            child: AnimatedBuilder(
              animation: SafetyRepository.instance,
              builder: (context, _) {
                final words = SafetyRepository.instance.muteWords;
                if (words.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'You have not muted any words.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.handle,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    final word = words[index];
                    return ListTile(
                      leading: const Icon(Icons.tag),
                      title: Text(word, style: AppTextStyles.name),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            SafetyRepository.instance.removeMuteWord(word),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
