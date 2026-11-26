/// Build-time configuration, passed with `--dart-define`.
///
/// Without SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY the app runs in demo mode:
/// sign in by picking a role and everything uses sample data held in memory.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
