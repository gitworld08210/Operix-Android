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
