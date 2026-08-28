import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:recordo/core/bootstrap.dart';
import 'package:recordo/core/storage/local_store.dart';
import 'package:recordo/features/session/remind_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  const SettingsState({
    this.haptics = true,
    this.remindLog = false,
    this.wedgeExplained = false,
    this.loaded = false,
    this.snackMessage,
  });

  final bool haptics;
  final bool remindLog;
  final bool wedgeExplained;
  final bool loaded;
  final String? snackMessage;

  SettingsState copyWith({
    bool? haptics,
    bool? remindLog,
    bool? wedgeExplained,
    bool? loaded,
    String? snackMessage,
    bool clearSnack = false,
  }) {
    return SettingsState(
      haptics: haptics ?? this.haptics,
      remindLog: remindLog ?? this.remindLog,
      wedgeExplained: wedgeExplained ?? this.wedgeExplained,
      loaded: loaded ?? this.loaded,
      snackMessage: clearSnack ? null : (snackMessage ?? this.snackMessage),
    );
  }
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit() : super(const SettingsState());

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final wedge =
        Bootstrap.store.getString(StorageKeys.wedgeExplained) == '1';
    emit(
      SettingsState(
        haptics: prefs.getBool(StorageKeys.prefHaptics) ?? true,
        remindLog: prefs.getBool(StorageKeys.prefRemindLog) ?? false,
        wedgeExplained: wedge,
        loaded: true,
      ),
    );
  }

  Future<void> setHaptics(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.prefHaptics, value);
    emit(state.copyWith(haptics: value));
  }

  Future<void> setRemindLog(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.prefRemindLog, value);
    if (value) {
      await RemindLogService.instance.init();
    } else {
      await RemindLogService.instance.cancel();
    }
    emit(
      state.copyWith(
        remindLog: value,
        snackMessage:
            value ? '已開 · 泊車後會提醒你填收費' : '已關閉提醒',
      ),
    );
  }

  void clearSnack() {
    if (state.snackMessage != null) {
      emit(state.copyWith(clearSnack: true));
    }
  }

  Future<void> markWedgeExplained() async {
    await Bootstrap.store.setString(StorageKeys.wedgeExplained, '1');
    emit(state.copyWith(wedgeExplained: true));
  }
}
