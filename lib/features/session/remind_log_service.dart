import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _notifId = 71002;
const _remindAfter = Duration(minutes: 90);

/// Reminds the driver to log parking fees after a session starts.
class RemindLogService {
  RemindLogService._();
  static final instance = RemindLogService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

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

  Future<bool> _prefEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageKeys.prefRemindLog) ?? false;
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
      return (await android.requestNotificationsPermission()) == true;
    }
    return true;
  }

  Future<void> scheduleForSession({
    required String sessionId,
    required DateTime startedAt,
  }) async {
    if (!_ready) return;
    if (!await _prefEnabled()) return;
    if (!await _ensurePermission()) return;

    await cancel();
    final fireAt = startedAt.add(_remindAfter);
    if (!fireAt.isAfter(DateTime.now())) return;

    await Bootstrap.store.setString(StorageKeys.remindLogSessionId, sessionId);

    const android = AndroidNotificationDetails(
      'recordo_remind_log',
      '提醒記低',
      channelDescription: '泊完提醒填收費',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const ios = DarwinNotificationDetails();
    await _plugin.zonedSchedule(
      id: _notifId,
      title: '泊完未？',
      body: '記低今次收費 · 幫其他司機知實付',
      scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> cancel() async {
    if (!_ready) return;
    await _plugin.cancel(id: _notifId);
    await Bootstrap.store.remove(StorageKeys.remindLogSessionId);
  }
}
