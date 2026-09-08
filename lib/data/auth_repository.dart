import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

/// A typed error carrying a human-readable message for the auth UI.
///
/// Thrown by [AuthRepository.sendOtp] / [AuthRepository.verifyOtp] when an
/// Edge Function reports a failure (bad code, expired code, rate limited,
/// send failure, ...). The UI catches this and surfaces [message] directly.
class OtpException implements Exception {
  const OtpException(this.message);

  final String message;

  @override
  String toString() => 'OtpException: $message';
}

/// Auth state access for Oneleven, backed by Azure ACS email OTP delivered via
/// two Supabase Edge Functions (`send-otp` and `verify-otp`).
///
/// Exposed as a [ChangeNotifier] singleton (`AuthRepository.instance`) so UI
/// can react to auth changes via `AnimatedBuilder(animation: AuthRepository
/// .instance)`, matching the app's repository convention. The underlying auth
/// state of truth is Supabase's own client; this repository forwards to it and
/// re-broadcasts `onAuthStateChange` events as [ChangeNotifier] notifications.
///
/// Flow:
/// 1. [sendOtp] invokes the `send-otp` Edge Function, which generates a 6-digit
///    code and emails it via Azure Communication Services.
/// 2. [verifyOtp] invokes the `verify-otp` Edge Function, which validates the
///    code and returns a `token_hash`. The client then finalizes the Supabase
///    session with `supabase.auth.verifyOTP(type: OtpType.magiclink,
///    tokenHash: ...)`, after which `onAuthStateChange` fires and `AuthGate`
///    swaps to the main shell.
class AuthRepository extends ChangeNotifier {
  AuthRepository._() {
    // Re-broadcast Supabase auth changes to listeners of this repository.
    _authSub = supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  /// Shared singleton instance.
  static final AuthRepository instance = AuthRepository._();

  StreamSubscription<AuthState>? _authSub;

  /// The current authenticated session, or null when signed out.
  Session? get currentSession => supabase.auth.currentSession;

  /// The current authenticated user, or null when signed out.
  User? get currentUser => supabase.auth.currentUser;

  /// Whether a user is currently signed in.
  bool get isAuthenticated => currentSession != null;

  /// Sends a one-time 6-digit login code to [email] via the `send-otp` Edge
  /// Function (which emails it through Azure Communication Services). New
  /// emails are handled server-side; no user is created until the code is
  /// verified.
  ///
  /// Throws an [OtpException] with a human-readable message when the function
  /// reports a failure (rate limiting, invalid email, send failure).
  Future<void> sendOtp(String email) async {
    try {
      // In supabase_flutter v2 `invoke` throws a [FunctionException] on any
      // non-2xx response, so the error body is read from the exception below.
      await supabase.functions.invoke(
        'send-otp',
        body: <String, dynamic>{'email': email},
      );
    } on FunctionException catch (e) {
      // `details` holds the parsed JSON body, e.g.
      // {'error': 'rate_limited', 'message': 'try again in a few minutes'}.
      // Surface the server's specific `message` (notably for rate limiting).
      throw OtpException(
        _sendErrorMessage(_errorCode(e.details), _detailsString(e.details, 'message')),
      );
    }
  }

  /// Verifies the 6-digit [token] for [email] via the `verify-otp` Edge
  /// Function, then finalizes the Supabase session from the returned
  /// `token_hash`. On success `onAuthStateChange` fires with the new session.
  ///
  /// Throws an [OtpException] with a human-readable message when the code is
  /// invalid/expired or too many attempts were made.
  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    final FunctionResponse res;
    try {
      // A non-2xx response throws a [FunctionException] (supabase_flutter v2);
      // the error code is read from its `details` in the catch below. The
      // success path (200) returns normally with the `token_hash` body.
      res = await supabase.functions.invoke(
        'verify-otp',
        body: <String, dynamic>{'email': email, 'code': token},
      );
    } on FunctionException catch (e) {
      throw OtpException(_verifyErrorMessage(_errorCode(e.details)));
    }

    final tokenHash = _dataString(res.data, 'token_hash');
    if (tokenHash == null || tokenHash.isEmpty) {
      throw const OtpException(
        'Could not verify the code. Please try again.',
      );
    }

    // Finalize the Supabase session. The verify-otp function mints the hash via
    // admin.generateLink(type: 'magiclink'), so we redeem it as a magic link.
    return supabase.auth.verifyOTP(
      type: OtpType.magiclink,
      tokenHash: tokenHash,
    );
  }

  /// Signs the current user out, clearing the local session.
  Future<void> signOut() => supabase.auth.signOut();

  @override
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    super.dispose();
  }

  /// Maps a `send-otp` error code to a user-facing message.
  String _sendErrorMessage(String? code, String? serverMessage) {
    switch (code) {
      case 'invalid_email':
        return 'Enter a valid email address.';
      case 'rate_limited':
        return serverMessage?.isNotEmpty == true
            ? serverMessage!
            : 'Too many requests. Please wait a moment and try again.';
      case 'send_failed':
      case 'server_error':
      default:
        return 'Could not send the code. Please try again.';
    }
  }

  /// Maps a `verify-otp` error code to a user-facing message.
  String _verifyErrorMessage(String? code) {
    switch (code) {
      case 'invalid_or_expired':
        return 'That code has expired or is invalid. Tap "Resend code".';
      case 'invalid_code':
        return 'That code is incorrect. Check your email or tap "Resend code".';
      case 'too_many_attempts':
        return 'Too many attempts. Request a new code and try again.';
      case 'server_error':
      default:
        return 'Could not verify the code. Please try again.';
    }
  }

  /// Extracts an error code string from a [FunctionException]'s details, which
  /// may be a `Map` (`{'error': ...}`) or a raw string.
  String? _errorCode(Object? details) {
    if (details is Map) {
      final value = details['error'];
      if (value is String) return value;
    }
    if (details is String && details.isNotEmpty) return details;
    return null;
  }

  /// Reads a string [key] from a [FunctionException]'s `details` when it is a
  /// parsed JSON body (`Map`), e.g. the server's `message`. Returns null when
  /// absent or not a string. Mirrors [_errorCode]'s Map handling.
  String? _detailsString(Object? details, String key) {
    if (details is Map) {
      final value = details[key];
      if (value is String) return value;
    }
    return null;
  }

  /// Reads a string [key] from a [FunctionResponse] `data` payload that may be
  /// a `Map`. Returns null when absent or not a string.
  String? _dataString(Object? data, String key) {
    if (data is Map) {
      final value = data[key];
      if (value is String) return value;
    }
    return null;
  }
}
