import 'package:recordo/core/config/recordo_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin Supabase bootstrap. No-op when dart-defines missing.
abstract final class RecordoSupabase {
  static bool _ready = false;

  static bool get isReady => _ready && RecordoConfig.supabaseEnabled;

  static SupabaseClient? get client {
    if (!isReady) return null;
    return Supabase.instance.client;
  }

  static Future<void> init() async {
    if (!RecordoConfig.supabaseEnabled) {
      _ready = false;
      return;
    }
    await Supabase.initialize(
      url: RecordoConfig.supabaseUrl,
      publishableKey: RecordoConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _ready = true;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        await client.auth.signInAnonymously();
      }
    } catch (_) {}
  }
}
