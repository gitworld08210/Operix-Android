import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// X-faithful multi-step sign-in / sign-up screen.
///
/// The visual flow mirrors X (Twitter): a black welcome screen with the white
/// X wordmark, then an "Enter your email address" step, then a 6-digit code
/// step. The WORKING mechanism underneath is unchanged Supabase email OTP:
/// [AuthRepository.sendOtp] sends the code and [AuthRepository.verifyOtp]
/// verifies it. On successful verification the app's `AuthGate` (which listens
/// to Supabase auth state) automatically swaps this screen for the main shell,
/// so no explicit navigation is needed on success.
///
/// Honesty constraints: this Supabase project has no SMS provider, so any
/// phone / social affordance either routes into the working email flow or
/// shows a clear "not available yet, use email" message. Nothing here
/// fabricates a fake OTP or silently fails.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Step { welcome, email, code }

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  _Step _step = _Step.welcome;
  bool _busy = false;
  bool _emailValid = false;
  bool _codeComplete = false;
  String _email = '';

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailChanged);
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailChanged);
    _codeController.removeListener(_onCodeChanged);
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    final valid = _isValidEmail(_emailController.text);
    if (valid != _emailValid) setState(() => _emailValid = valid);
  }

  void _onCodeChanged() {
    final complete = _codeController.text.trim().length == 6;
    if (complete != _codeComplete) setState(() => _codeComplete = complete);
  }

  bool _isValidEmail(String value) {
    final email = value.trim();
    return email.contains('@') && email.indexOf('@') > 0;
  }

  void _showError(String message) => _showSnack(message);

  void _showInfo(String message) => _showSnack(message);

  void _showSnack(String message) {
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

  /// Honest handling for phone / social affordances: no SMS or OAuth provider
  /// is configured on this project, so we surface a clear message and keep the
  /// user on the working email path rather than pretending to sign them in.
  void _useEmailInstead(String reason) {
    _showInfo(reason);
    setState(() => _step = _Step.email);
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
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

  Future<void> _resendCode() async {
    if (_busy || _email.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AuthRepository.instance.sendOtp(_email);
      _showInfo('We sent a new code to $_email.');
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Could not resend the code. Please try again.');
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
      // Surface Supabase's own message (e.g. "Token has expired or is
      // invalid") plus a readable hint to check the email or resend.
      _showError('${e.message} Check your email or tap "Resend code".');
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.vertical -
                  (AppSpacing.lg * 2),
              maxWidth: 480,
            ),
            child: switch (_step) {
              _Step.welcome => _buildWelcomeStep(),
              _Step.email => _buildEmailStep(),
              _Step.code => _buildCodeStep(),
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Welcome step
  // ---------------------------------------------------------------------------

  Widget _buildWelcomeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xxl),
        const Center(child: _XWordmark(size: 44)),
        const SizedBox(height: AppSpacing.xxl * 2),
        Text('See what\'s happening', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.xl),
        // Circular social row. No OAuth provider is configured, so each button
        // honestly routes into the working email flow with an explanation.
        Row(
          children: <Widget>[
            _CircleSocialButton(
              label: 'G',
              tooltip: 'Continue with Google',
              onPressed: _busy
                  ? null
                  : () => _useEmailInstead(
                        'Google sign-in isn\'t available yet. Use email.',
                      ),
            ),
            const SizedBox(width: AppSpacing.md),
            _CircleSocialButton(
              icon: Icons.alternate_email,
              tooltip: 'Continue with email',
              onPressed: _busy ? null : () => setState(() => _step = _Step.email),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const _OrDivider(),
        const SizedBox(height: AppSpacing.xl),
        // Full-width WHITE pill primary button. For visual fidelity it reads
        // "Continue with Phone", but since no SMS provider exists it honestly
        // routes into the email flow with an explanation.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: AppTheme.whitePillButton(),
            onPressed: _busy
                ? null
                : () => _useEmailInstead(
                      'Phone sign-in isn\'t available yet. Use email.',
                    ),
            child: const Text('Continue with Phone'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _LegalText(),
        const SizedBox(height: AppSpacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Have an account already?', style: AppTextStyles.subtitle),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _step = _Step.email),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              child: const Text('Log in'),
            ),
          ],
        ),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => setState(() => _step = _Step.email),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('Login with username / Use email'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Email step
  // ---------------------------------------------------------------------------

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const _XWordmark(size: 26),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _showInfo(
                        'Phone sign-in isn\'t available yet. Use email.',
                      ),
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryText),
              child: const Text('Use phone'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Enter your email address', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.sm),
        Text('We\'ll send you a verification code', style: AppTextStyles.subtitle),
        const SizedBox(height: AppSpacing.xxl),
        TextField(
          controller: _emailController,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          textInputAction: TextInputAction.done,
          style: AppTextStyles.body,
          cursorColor: AppColors.accent,
          onSubmitted: (_) => (_busy || !_emailValid) ? null : _sendCode(),
          decoration: _inlineFieldDecoration('Email'),
        ),
        const SizedBox(height: AppSpacing.xxl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: AppTheme.darkPillButton(),
            onPressed: (_busy || !_emailValid) ? null : _sendCode,
            child: _busy ? const _ButtonSpinner() : const Text('Continue'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Code step
  // ---------------------------------------------------------------------------

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const _XWordmark(size: 26),
            TextButton(
              onPressed: _busy ? null : _changeEmail,
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryText),
              child: const Text('Change email'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('We sent you a code', style: AppTextStyles.headline),
        const SizedBox(height: AppSpacing.sm),
        Text('Enter it below to verify $_email', style: AppTextStyles.subtitle),
        const SizedBox(height: AppSpacing.xxl),
        TextField(
          controller: _codeController,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: AppTextStyles.display.copyWith(letterSpacing: 8),
          cursorColor: AppColors.accent,
          onSubmitted: (_) => (_busy || !_codeComplete) ? null : _verifyCode(),
          decoration: _inlineFieldDecoration('Verification code'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : _resendCode,
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            child: const Text('Resend code'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: AppTheme.darkPillButton(),
            onPressed: (_busy || !_codeComplete) ? null : _verifyCode,
            child: _busy ? const _ButtonSpinner() : const Text('Next'),
          ),
        ),
      ],
    );
  }

  /// Minimal inline (underline) field decoration matching X's borderless look
  /// rather than the app's default filled pill.
  InputDecoration _inlineFieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: AppTextStyles.handle,
      floatingLabelStyle: AppTextStyles.handle.copyWith(color: AppColors.accent),
      filled: false,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.accent, width: 2),
      ),
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
    );
  }
}

/// White X wordmark built from a bold styled glyph (no external image asset,
/// so it renders offline). Uses the app's sans stack via [AppTextStyles].
class _XWordmark extends StatelessWidget {
  const _XWordmark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      'X',
      style: AppTextStyles.headline.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: AppColors.white,
        letterSpacing: -1,
        height: 1,
      ),
    );
  }
}

/// Circular social/action button used on the welcome step.
class _CircleSocialButton extends StatelessWidget {
  const _CircleSocialButton({
    this.icon,
    this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget child = icon != null
        ? Icon(icon, color: AppColors.background, size: 22)
        : Text(
            label ?? '',
            style: AppTextStyles.title.copyWith(color: AppColors.background),
          );
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 44, height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// "or" divider with hairlines on either side.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('or', style: AppTextStyles.subtitle),
        ),
        const Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
      ],
    );
  }
}

/// Small legal blurb shown under the primary welcome button.
class _LegalText extends StatelessWidget {
  const _LegalText();

  @override
  Widget build(BuildContext context) {
    return Text(
      'By signing up, you agree to the Terms of Service and Privacy Policy, '
      'including Cookie Use.',
      style: AppTextStyles.caption,
    );
  }
}

/// Small white spinner shown inside a busy pill button.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryText),
      ),
    );
  }
}
