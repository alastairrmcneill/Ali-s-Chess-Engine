/// Supabase connection details, passed at build time:
///
///     flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// Without them the app still works, only online play is unavailable.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
