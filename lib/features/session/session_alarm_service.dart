import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/session/end_session_sheet.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _notifId = 71001;

String formatAlarmDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0 && m > 0) return '$h 小時 $m 分';
  if (h > 0) return '$h 小時';
  if (m > 0) return '$m 分鐘';
  return '一陣';
}

String parkingAlarmBody({
  required Duration parkedFor,
  double? estimatedFee,
}) {
  final parked = formatAlarmDuration(parkedFor);
  if (estimatedFee != null) {
    return '已泊約 $parked · 預估 HK\$${estimatedFee.round()} · 決定走定繼續';
  }
  return '已泊約 $parked · 決定而家走定繼續';
}

class SessionAlarmService {
  SessionAlarmService._();
  static final instance = SessionAlarmService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  DateTime? get scheduledAt {
    final raw = Bootstrap.store.getString(StorageKeys.sessionAlarmAt);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String? get scheduledSessionId =>
      Bootstrap.store.getString(StorageKeys.sessionAlarmSessionId);

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Hong_Kong'));
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    _ready = true;
  }

  Future<bool> _ensurePermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final ok = await ios.requestPermissions(
        alert: true,
        sound: true,
        badge: false,
      );
      return ok == true;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final notif = await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
      return notif == true;
    }
    return true;
  }

  Future<bool> schedule({
    required String sessionId,
    required DateTime startedAt,
    required Duration after,
    double? hourlyHkd,
    String? parkName,
  }) async {
    if (!_ready) await init();
    if (after.inSeconds < 30) return false;
    final allowed = await _ensurePermission();
    if (!allowed) return false;

    final when = DateTime.now().add(after);
    final parkedFor = when.difference(startedAt);
    final fee = estimateParkingFee(parkedFor, hourlyHkd);
    final body = parkingAlarmBody(
      parkedFor: parkedFor,
      estimatedFee: fee,
    );
    final title = parkName == null || parkName.isEmpty
        ? 'Recordo 泊車提醒'
        : '$parkName · 泊車提醒';

    await _plugin.cancel(id: _notifId);
    await _plugin.zonedSchedule(
      id: _notifId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'parking_alarm',
          '泊車鬧鐘',
          channelDescription: '泊咗幾耐嘅提醒',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
    await Bootstrap.store.setString(
      StorageKeys.sessionAlarmAt,
      when.toUtc().toIso8601String(),
    );
    await Bootstrap.store.setString(
      StorageKeys.sessionAlarmSessionId,
      sessionId,
    );
    return true;
  }

  Future<void> cancel() async {
    if (!_ready) await init();
    await _plugin.cancel(id: _notifId);
    await Bootstrap.store.remove(StorageKeys.sessionAlarmAt);
    await Bootstrap.store.remove(StorageKeys.sessionAlarmSessionId);
  }

  Future<void> cancelIfSession(String sessionId) async {
    if (scheduledSessionId == sessionId) {
      await cancel();
    }
  }
}
