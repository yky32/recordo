import 'package:recordo/features/parks/contribution_copy.dart';
import 'package:recordo/features/parks/park.dart';
import 'package:recordo/features/parks/park_catalog_cubit.dart';
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
    if (sharePaid && park != null && amountHkd > 0) {
      try {
        final cloud = await catalogCubit.reportPaidSession(
          parkId: park.id,
          amountHkd: amountHkd,
          durationMinutes: durationMinutes,
        );
        snack = ContributionCopy.paidSession(cloud: cloud);
      } on ArgumentError catch (e) {
        snack = e.message?.toString() ?? '實付未能分享';
      }
    }

    return EndSessionOutcome(snackMessage: snack, saved: true);
  }
}
