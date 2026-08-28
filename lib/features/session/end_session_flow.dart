import 'package:recordo/core/supabase/recordo_supabase.dart';
import 'package:recordo/features/parks/contribution_copy.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
import 'package:recordo/features/session/cohort_telemetry.dart';
import 'package:recordo/features/session/parking_session.dart';
import 'package:recordo/features/session/session_cubit.dart';

/// Outcome of ending a session (local save + optional paid share).
class EndSessionOutcome {
  const EndSessionOutcome({required this.snackMessage, required this.saved});

  final String snackMessage;
  final bool saved;
}

/// End-session workflow owned by cubits (not the sheet widget).
abstract final class EndSessionFlow {
  static Future<EndSessionOutcome?> complete({
    required SessionCubit sessionCubit,
    required ParkCatalogCubit catalogCubit,
    required ParkingSession active,
    required double amountHkd,
    required bool sharePaid,
    Park? park,
  }) async {
    final parkId = park?.id ?? active.parkId;
    final parkName = park?.name ?? active.parkName;
    final durationMinutes = active.elapsed.inMinutes;

    await sessionCubit.end(
      amountHkd: amountHkd,
      parkId: parkId,
      parkName: parkName,
    );

    var snack = '已記低';
    var cloudOk = false;
    if (sharePaid && park != null && amountHkd > 0) {
      if (!RecordoSupabase.isReady) {
        snack = ContributionCopy.paidSessionOfflineBuild;
      } else {
        try {
          await RecordoSupabase.ensureSignedIn();
          cloudOk = await catalogCubit.reportPaidSession(
            parkId: park.id,
            amountHkd: amountHkd,
            durationMinutes: durationMinutes,
          );
          snack = ContributionCopy.paidSession(cloud: cloudOk);
        } on ArgumentError catch (e) {
          snack = e.message?.toString() ?? '實付未能分享';
        }
      }
    }

    // Fire-and-forget Phase C exit-gate telemetry.
    // ignore: unawaited_futures
    CohortTelemetry.sessionEnd(
      parkId: parkId,
      amountHkd: amountHkd,
      durationMinutes: durationMinutes,
      sharePaid: sharePaid && park != null && amountHkd > 0,
      cloudOk: cloudOk,
    );

    return EndSessionOutcome(snackMessage: snack, saved: true);
  }
}
