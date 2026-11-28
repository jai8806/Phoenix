/// Build-time configuration, passed with `--dart-define`.
///
/// Without SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY the app runs in demo mode:
/// sign in by picking a role and everything uses sample data held in memory.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// The unit's shared folder of précis, papers, question banks and notes.
  static const studyLibraryUrl = String.fromEnvironment(
    'STUDY_LIBRARY_URL',
    defaultValue: 'https://drive.google.com/drive/folders/1hOvLqhLUfe-_-Z8njrDTlpvJV66krrWX',
  );

  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
