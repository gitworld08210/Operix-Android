import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase project URL.
///
/// Overridable at build/run time via `--dart-define=SUPABASE_URL=...`.
/// Falls back to the Oneleven project's public URL.
const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://xyuzzjwmpyckuhtiygpk.supabase.co',
);

/// Supabase publishable (anon) key.
///
/// Overridable at build/run time via `--dart-define=SUPABASE_ANON_KEY=...`.
/// This is a public, client-safe key (never a service_role/secret key).
const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_57Xuez2QU5tHLbXhVnqi7w_Bhy-Jvmz',
);

/// Initializes the global Supabase client. Call once, before `runApp`, after
/// `WidgetsFlutterBinding.ensureInitialized()`.
Future<void> initSupabase() async => Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );

/// Convenience accessor for the initialized Supabase client.
SupabaseClient get supabase => Supabase.instance.client;

/// Whether the global Supabase client has been initialized.
///
/// [Supabase.instance] throws when [initSupabase] has not run (e.g. under
/// `flutter test` or offline). Guarded repository code uses this to tell an
/// UNINITIALIZED-client no-op (tests/offline: nothing to load, no error to
/// surface) apart from a REAL fetch failure on a live client (network/query),
/// so a failed page can raise a retry affordance without breaking the no-throw
/// contract.
bool get isSupabaseInitialized {
  try {
    // Touching the singleton throws an AssertionError before initialize().
    Supabase.instance;
    return true;
  } catch (_) {
    return false;
  }
}
