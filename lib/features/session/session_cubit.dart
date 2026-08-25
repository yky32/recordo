import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/session/live_activity_service.dart';
import 'package:recordo/features/session/parking_session.dart';
import 'package:uuid/uuid.dart';

class SessionState {
  const SessionState({
    this.active,
    this.history = const [],
  });

  final ParkingSession? active;
  final List<ParkingSession> history;

  double get monthTotal {
    final now = DateTime.now();
    return history
        .where(
          (s) =>
              s.endedAt != null &&
              s.endedAt!.year == now.year &&
              s.endedAt!.month == now.month &&
              s.amountHkd != null,
        )
        .fold<double>(0, (a, b) => a + (b.amountHkd ?? 0));
  }

  SessionState copyWith({
    ParkingSession? active,
    List<ParkingSession>? history,
    bool clearActive = false,
  }) {
    return SessionState(
      active: clearActive ? null : (active ?? this.active),
      history: history ?? this.history,
    );
  }
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit() : super(const SessionState());

  final _uuid = const Uuid();

  void hydrate() {
    final list = Bootstrap.store
        .getJsonList(StorageKeys.sessions)
        .map(ParkingSession.fromJson)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final activeRaw = Bootstrap.store.getJsonMap(StorageKeys.activeSession);
    final active =
        activeRaw == null ? null : ParkingSession.fromJson(activeRaw);
    emit(SessionState(active: active, history: list));

    // Restore Live Activity if session still active
    if (active != null) {
      LiveActivityService.instance.startForSession(active);
    }
  }

  Future<void> start({
    String? parkId,
    String? parkName,
    String? hourlyLabel,
  }) async {
    if (state.active != null) return;
    final s = ParkingSession(
      id: _uuid.v4(),
      startedAt: DateTime.now(),
      parkId: parkId,
      parkName: parkName,
    );
    await Bootstrap.store.setJson(StorageKeys.activeSession, s.toJson());
    emit(state.copyWith(active: s));
    await LiveActivityService.instance.startForSession(
      s,
      hourlyLabel: hourlyLabel,
    );
  }

  Future<void> end({
    required double amountHkd,
    String note = '',
    String? parkId,
    String? parkName,
  }) async {
    final a = state.active;
    if (a == null) return;
    final done = a.copyWith(
      endedAt: DateTime.now(),
      amountHkd: amountHkd,
      note: note,
      parkId: parkId ?? a.parkId,
      parkName: parkName ?? a.parkName,
    );
    final history = [done, ...state.history];
    await Bootstrap.store.setJson(
      StorageKeys.sessions,
      history.map((e) => e.toJson()).toList(),
    );
    await Bootstrap.store.remove(StorageKeys.activeSession);
    emit(SessionState(active: null, history: history));
    await LiveActivityService.instance.end();
  }

  /// Completed sessions for a park with amount (newest first).
  List<ParkingSession> paidSessionsForPark(String parkId, {int limit = 5}) {
    final list = state.history
        .where(
          (s) =>
              s.parkId == parkId &&
              s.amountHkd != null &&
              s.endedAt != null,
        )
        .toList();
    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

}

