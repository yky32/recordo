import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> setJson(String key, Object? value) =>
      _prefs.setString(key, jsonEncode(value));

  List<Map<String, dynamic>> getJsonList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic>? getJsonMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> remove(String key) => _prefs.remove(key);
}

abstract final class StorageKeys {
  static const sessions = 'parking_sessions';
  static const ugcPrices = 'ugc_prices';
  static const activeSession = 'active_session';
  static const ugcNewParks = 'ugc_new_parks';
  static const syncOutbox = 'sync_outbox';
  static const prefHaptics = 'pref_haptics';
  static const prefRemindLog = 'pref_remind_log';
  static const liveActivityId = 'live_activity_id';
  static const wedgeExplained = 'wedge_explained';
  static const remindLogSessionId = 'remind_log_session_id';
}
