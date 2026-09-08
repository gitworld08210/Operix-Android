import 'package:flutter/material.dart';

import '../data/profile_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// Edit-profile flow for the signed-in user: display name + bio.
///
/// Pre-fills from `ProfileRepository.instance.currentUser` and, on save,
/// commits through [ProfileRepository.updateProfile] (optimistic + guarded
/// persistence). Avatar/banner upload is intentionally out of scope for this
/// slice (no image byte source bundled); only text fields are editable here.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;

  /// Upper bound for the bio, mirroring a reasonable server limit and keeping
  /// the field bounded.
  static const int _maxBioLength = 160;

  /// Upper bound for the display name.
  static const int _maxNameLength = 50;

  @override
  void initState() {
    super.initState();
    final user = ProfileRepository.instance.currentUser;
    _nameController = TextEditingController(text: user.displayName);
    _bioController = TextEditingController(text: user.bio);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _save() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    ProfileRepository.instance.updateProfile(
      displayName: _nameController.text.trim(),
      bio: _bioController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: <Widget>[
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Display name', style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameController,
                  maxLength: _maxNameLength,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Your name',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Display name cannot be empty.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Bio', style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _bioController,
                  maxLength: _maxBioLength,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Tell people about yourself',
                  ),
                  validator: (value) {
                    if (value != null && value.trim().length > _maxBioLength) {
                      return 'Bio cannot exceed $_maxBioLength characters.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
