/// Compile-time config. Pass via --dart-define.
///
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
abstract final class RecordoConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get supabaseEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
