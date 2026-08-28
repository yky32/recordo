import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/features/parks/supabase_park_remote.dart';
import 'package:uuid/uuid.dart';

/// Phase C exit-gate telemetry (app_open + session_end).
///
/// Fire-and-forget. Failures never block UX.
abstract final class CohortTelemetry {
  static final _remote = SupabaseParkRemote();
  static const _uuid = Uuid();

  static Future<String> installId() async {
    final existing = Bootstrap.store.getString(StorageKeys.cohortInstallId);
    if (existing != null && existing.length > 8) return existing;
    final id = _uuid.v4();
    await Bootstrap.store.setString(StorageKeys.cohortInstallId, id);
    return id;
  }

  static Future<void> appOpen() async {
    await _send(event: 'app_open');
  }

  static Future<void> sessionEnd({
    String? parkId,
    double? amountHkd,
    int? durationMinutes,
    required bool sharePaid,
    required bool cloudOk,
  }) async {
    await _send(
      event: 'session_end',
      parkId: parkId,
      amountHkd: amountHkd,
      durationMinutes: durationMinutes,
      sharePaid: sharePaid,
      cloudOk: cloudOk,
    );
  }

  static Future<void> _send({
    required String event,
    String? parkId,
    double? amountHkd,
    int? durationMinutes,
    bool? sharePaid,
    bool? cloudOk,
  }) async {
    if (!RecordoSupabase.isReady) return;
    try {
      await RecordoSupabase.ensureSignedIn();
      final id = await installId();
      await _remote.insertCohortEvent(
        installId: id,
        event: event,
        parkId: parkId,
        amountHkd: amountHkd,
        durationMinutes: durationMinutes,
        sharePaid: sharePaid,
        cloudOk: cloudOk,
      );
    } catch (_) {}
  }
}
