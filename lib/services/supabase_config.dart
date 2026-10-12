/// Supabase configuration injected at build/run time.
///
/// Values are supplied via --dart-define so credentials never live in
/// source control:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// The anon key is public-by-design (all authorisation is enforced by
/// Postgres RLS); the service-role key must never appear here.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Deep link that receives password-recovery links from Supabase email.
  /// Must match an intent-filter in AndroidManifest.xml (and Info.plist
  /// on iOS) and be listed in Supabase Auth redirect URLs.
  static const String resetRedirectUrl = 'bragmat://reset-callback';

  /// Whether Supabase credentials were supplied at build time.
  /// Dev/test builds without credentials bypass the auth gate entirely.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
