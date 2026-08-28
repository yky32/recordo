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

  static bool get hasSession {
    final c = client;
    return c != null && c.auth.currentSession != null;
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
    await ensureSignedIn();
  }

  /// Anonymous auth is required for paid_sessions / price_reports / cohort_events.
  static Future<bool> ensureSignedIn() async {
    final c = client;
    if (c == null) return false;
    if (c.auth.currentSession != null) return true;
    try {
      await c.auth.signInAnonymously();
      return c.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }
}
