import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/session/parking_session.dart';

/// iOS Live Activity / Dynamic Island for active parking session.
///
/// Requires Widget Extension + App Group (see docs/LIVE_ACTIVITY.md).
/// Timer ticks natively via SwiftUI Text(timerInterval:) — no 1s Flutter loop.
class LiveActivityService {
  LiveActivityService._();
  static final instance = LiveActivityService._();

  static const appGroupId = 'group.com.recordo.live';

  final _plugin = LiveActivities();
  bool _inited = false;
  String? _activityId;

  Future<void> init() async {
    if (_inited) return;
    if (kIsWeb || !Platform.isIOS) {
      _inited = true;
      return;
    }
    try {
      await _plugin.init(
        appGroupId: appGroupId,
        urlScheme: 'recordo',
      );
      _activityId = Bootstrap.store.getString(StorageKeys.liveActivityId);
      _inited = true;
    } catch (e) {
      debugPrint('LiveActivity init failed: $e');
      _inited = true;
    }
  }

  Map<String, dynamic> _payload(ParkingSession s, {String? hourlyLabel}) {
    return {
      'parkName': s.parkName ?? '停車場',
      'startMs': s.startedAt.millisecondsSinceEpoch.toDouble(),
      'hourlyLabel': hourlyLabel ?? '',
      'sessionId': s.id,
    };
  }

  Future<void> startForSession(
    ParkingSession session, {
    String? hourlyLabel,
  }) async {
    await init();
    if (kIsWeb || !Platform.isIOS) return;

    try {
      final enabled = await _plugin.areActivitiesEnabled();
      if (!enabled) {
        debugPrint('Live Activities disabled by system');
        return;
      }

      await end();

      final id = await _plugin.createActivity(
        session.id,
        _payload(session, hourlyLabel: hourlyLabel),
        removeWhenAppIsKilled: false,
        iOSEnableRemoteUpdates: false,
      );
      _activityId = id ?? session.id;
      await Bootstrap.store.setString(StorageKeys.liveActivityId, _activityId!);
      debugPrint('LiveActivity started: $_activityId');
    } catch (e) {
      debugPrint('LiveActivity start failed: $e');
    }
  }

  Future<void> end() async {
    await init();
    if (kIsWeb || !Platform.isIOS) return;
    try {
      final id =
          _activityId ?? Bootstrap.store.getString(StorageKeys.liveActivityId);
      if (id != null) {
        await _plugin.endActivity(id);
      }
      try {
        await _plugin.endAllActivities();
      } catch (_) {}
    } catch (e) {
      debugPrint('LiveActivity end failed: $e');
    }
    _activityId = null;
    await Bootstrap.store.remove(StorageKeys.liveActivityId);
  }
}
