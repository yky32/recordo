import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/session/live_activity_service.dart';
import 'package:recordo/features/session/remind_log_service.dart';
import 'package:recordo/features/session/parking_session.dart';
import 'package:recordo/features/session/session_alarm_service.dart';
import 'package:uuid/uuid.dart';

class SessionState {
  const SessionState({
    this.active,
    this.history = const [],
    this.alarmAt,
    this.alarmSessionId,
    this.alarmBusy = false,
  });

  final ParkingSession? active;
  final List<ParkingSession> history;
  final DateTime? alarmAt;
  final String? alarmSessionId;
  final bool alarmBusy;

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

  /// Scheduled alarm for [sessionId], or null if none / expired / other session.
  DateTime? alarmFor(String sessionId) {
    if (alarmSessionId != sessionId || alarmAt == null) return null;
    if (alarmAt!.isBefore(DateTime.now())) return null;
    return alarmAt;
  }

  SessionState copyWith({
    ParkingSession? active,
    List<ParkingSession>? history,
    DateTime? alarmAt,
    String? alarmSessionId,
    bool? alarmBusy,
    bool clearActive = false,
    bool clearAlarm = false,
  }) {
    return SessionState(
      active: clearActive ? null : (active ?? this.active),
      history: history ?? this.history,
      alarmAt: clearAlarm ? null : (alarmAt ?? this.alarmAt),
      alarmSessionId:
          clearAlarm ? null : (alarmSessionId ?? this.alarmSessionId),
      alarmBusy: alarmBusy ?? this.alarmBusy,
    );
  }
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit() : super(const SessionState());

  final _uuid = const Uuid();

  void _emitAlarmFromStore() {
    emit(
      state.copyWith(
        alarmAt: SessionAlarmService.instance.scheduledAt,
        alarmSessionId: SessionAlarmService.instance.scheduledSessionId,
      ),
    );
  }

  void hydrate() {
    final list = Bootstrap.store
        .getJsonList(StorageKeys.sessions)
        .map(ParkingSession.fromJson)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final activeRaw = Bootstrap.store.getJsonMap(StorageKeys.activeSession);
    final active =
        activeRaw == null ? null : ParkingSession.fromJson(activeRaw);
    emit(
      SessionState(
        active: active,
        history: list,
        alarmAt: SessionAlarmService.instance.scheduledAt,
        alarmSessionId: SessionAlarmService.instance.scheduledSessionId,
      ),
    );

    if (active != null) {
      LiveActivityService.instance.startForSession(active);
    } else {
      SessionAlarmService.instance.cancel();
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
    await RemindLogService.instance.scheduleForSession(
      sessionId: s.id,
      startedAt: s.startedAt,
    );
  }

  /// Driver forgot to start before leaving the car.
  Future<void> adjustStartedAt(DateTime wanted) async {
    final a = state.active;
    if (a == null) return;
    final next = clampSessionStart(wanted);
    if (next.difference(a.startedAt).inSeconds.abs() < 30) return;
    final s = a.copyWith(startedAt: next);
    await Bootstrap.store.setJson(StorageKeys.activeSession, s.toJson());
    emit(state.copyWith(active: s));
    await LiveActivityService.instance.startForSession(s);
    await RemindLogService.instance.scheduleForSession(
      sessionId: s.id,
      startedAt: s.startedAt,
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
    emit(SessionState(history: history));
    await LiveActivityService.instance.end();
    await RemindLogService.instance.cancel();
    await SessionAlarmService.instance.cancelIfSession(a.id);
    _emitAlarmFromStore();
  }

  Future<void> clearHistory() async {
    await Bootstrap.store.remove(StorageKeys.sessions);
    await Bootstrap.store.remove(StorageKeys.activeSession);
    await LiveActivityService.instance.end();
    await RemindLogService.instance.cancel();
    await SessionAlarmService.instance.cancel();
    emit(const SessionState());
  }

  Future<bool> scheduleAlarm({
    required Duration after,
    double? hourlyHkd,
    String? parkName,
  }) async {
    final active = state.active;
    if (active == null) return false;
    emit(state.copyWith(alarmBusy: true));
    final ok = await SessionAlarmService.instance.schedule(
      sessionId: active.id,
      startedAt: active.startedAt,
      after: after,
      hourlyHkd: hourlyHkd,
      parkName: parkName,
    );
    emit(state.copyWith(alarmBusy: false));
    _emitAlarmFromStore();
    return ok;
  }

  Future<void> cancelAlarm() async {
    await SessionAlarmService.instance.cancel();
    emit(state.copyWith(clearAlarm: true));
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
