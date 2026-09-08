import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/message_repository.dart';
import 'data/notification_repository.dart';
import 'data/post_repository.dart';
import 'data/profile_repository.dart';
import 'screens/auth_screen.dart';
import 'supabase_config.dart';
import 'theme/app_text_styles.dart';
import 'theme/app_theme.dart';
import 'widgets/app_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Configure fonts for a possibly-offline target before the first frame.
  AppTextStyles.configureFonts();
  // Initialize the Supabase client (URL / anon key live in supabase_config.dart).
  await initSupabase();
  runApp(const OnelevenApp());
}

/// Root of the Oneleven app. Dark-first, modern-X styling.
class OnelevenApp extends StatelessWidget {
  const OnelevenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.buildDarkTheme();
    return MaterialApp(
      title: 'Oneleven',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}

/// Gates the app on Supabase auth state: shows the main [AppScaffold] shell
/// when a session exists, otherwise the [AuthScreen] OTP flow. Listens to
/// `supabase.auth.onAuthStateChange` and rebuilds on sign-in / sign-out.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSub;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _session = supabase.auth.currentSession;
    if (_session != null) {
      _loadRepositories();
    }
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final hadSession = _session != null;
      final hasSession = data.session != null;
      setState(() => _session = data.session);
      if (hasSession && !hadSession) {
        // Fresh sign-in: load each user-scoped repository.
        _loadRepositories();
      } else if (!hasSession && hadSession) {
        // Sign-out: clear cached state so the next login starts clean.
        _clearRepositories();
      }
    });
  }

  /// Loads all user-scoped repositories after sign-in. Each [load] is guarded
  /// internally and sets its own load-state, so this is safe to fire.
  void _loadRepositories() {
    // ignore: discarded_futures
    ProfileRepository.instance.load();
    // ignore: discarded_futures
    PostRepository.instance.load();
    // ignore: discarded_futures
    NotificationRepository.instance.load();
    // ignore: discarded_futures
    MessageRepository.instance.load();
  }

  /// Clears all user-scoped repositories on sign-out.
  void _clearRepositories() {
    ProfileRepository.instance.clear();
    PostRepository.instance.clear();
    NotificationRepository.instance.clear();
    MessageRepository.instance.clear();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _session != null ? const AppScaffold() : const AuthScreen();
  }
}
