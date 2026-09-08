import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

/// Auth state access for Oneleven, backed by Supabase email-OTP.
///
/// Exposed as a [ChangeNotifier] singleton (`AuthRepository.instance`) so UI
/// can react to auth changes via `AnimatedBuilder(animation: AuthRepository
/// .instance)`, matching the app's repository convention. The underlying auth
/// state of truth is Supabase's own client; this repository forwards to it and
/// re-broadcasts `onAuthStateChange` events as [ChangeNotifier] notifications.
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

  /// Sends a one-time login code to [email]. New emails are signed up
  /// automatically (Supabase creates the auth user + profile via trigger).
  Future<void> sendOtp(String email) =>
      supabase.auth.signInWithOtp(email: email);

  /// Verifies the emailed [token] (6-digit code) for [email], completing
  /// sign-in. On success, `onAuthStateChange` fires with the new session.
  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) =>
      supabase.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: token,
      );

  /// Signs the current user out, clearing the local session.
  Future<void> signOut() => supabase.auth.signOut();

  @override
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    super.dispose();
  }
}
