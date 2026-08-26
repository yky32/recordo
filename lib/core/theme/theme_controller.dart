import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme mode. Default = dark (Uber night).
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final instance = ThemeController._();

  static const _key = 'theme_mode'; // dark | light | system

  ThemeMode _mode = ThemeMode.dark;
  int _generation = 0;

  ThemeMode get mode => _mode;

  /// Bumps on every mode change — used to force route subtree rebuild.
  int get generation => _generation;

  bool get isDark {
    if (_mode == ThemeMode.light) return false;
    if (_mode == ThemeMode.dark) return true;
    final brightness = PlatformDispatcher.instance.platformBrightness;
    return brightness != Brightness.light;
  }

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? 'dark';
    _mode = switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _generation++;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    _generation++;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await prefs.setString(_key, raw);
  }

  Future<void> toggleLightDark() async {
    await setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}
