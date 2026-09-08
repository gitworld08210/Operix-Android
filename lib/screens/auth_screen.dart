import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// Two-step email one-time-code sign-in / sign-up screen.
///
/// Step 1 collects an email and sends a login code via
/// [AuthRepository.sendOtp]. Step 2 collects the 6-digit code and verifies it
/// via [AuthRepository.verifyOtp]. On successful verification the app's
/// `AuthGate` (which listens to Supabase auth state) automatically swaps this
/// screen for the main shell, so no explicit navigation is needed here.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Step { email, code }

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  String _email = '';

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
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

  void _showInfo(String message) {
    if (!mounted) return;
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

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Enter a valid email address.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthRepository.instance.sendOtp(email);
      if (!mounted) return;
      setState(() {
        _email = email;
        _step = _Step.code;
      });
      _showInfo('We sent a code to $email.');
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final token = _codeController.text.trim();
    if (token.length != 6) {
      _showError('Enter the 6-digit code.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthRepository.instance.verifyOtp(email: _email, token: token);
      // On success the AuthGate stream flips to the main shell automatically.
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not verify the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    setState(() {
      _step = _Step.email;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _step == _Step.email
                  ? _buildEmailStep()
                  : _buildCodeStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Sign in to Oneleven', style: AppTextStyles.display),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Enter your email and we\'ll send you a one-time code. New here? '
          'An account is created automatically.',
          style: AppTextStyles.handle,
        ),
        const SizedBox(height: AppSpacing.xl),
        // TODO: phone OTP is out of scope; only email OTP is supported here.
        TextField(
          controller: _emailController,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          textInputAction: TextInputAction.done,
          style: AppTextStyles.body,
          onSubmitted: (_) => _busy ? null : _sendCode(),
          decoration: _fieldDecoration('Email', 'you@example.com'),
        ),
        const SizedBox(height: AppSpacing.lg),
        _PrimaryButton(
          label: 'Send code',
          busy: _busy,
          onPressed: _busy ? null : _sendCode,
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Enter your code', style: AppTextStyles.display),
        const SizedBox(height: AppSpacing.sm),
        Text('We sent a 6-digit code to $_email.', style: AppTextStyles.handle),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: _codeController,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: AppTextStyles.display,
          onSubmitted: (_) => _busy ? null : _verifyCode(),
          decoration: _fieldDecoration('6-digit code', '000000'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PrimaryButton(
          label: 'Verify',
          busy: _busy,
          onPressed: _busy ? null : _verifyCode,
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: _busy ? null : _changeEmail,
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('Change email'),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: AppTextStyles.handle,
      hintStyle: AppTextStyles.handle,
      filled: true,
      fillColor: AppColors.surface,
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.5),
          shape: const StadiumBorder(),
          textStyle: AppTextStyles.label,
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.white),
                ),
              )
            : Text(label),
      ),
    );
  }
}
