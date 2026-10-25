import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that belong to the whole app rather than to one helper.
class AppSettingsStorage {
  AppSettingsStorage(this._store);

  static const key = 'app.settings.v1';

  final JsonStore _store;

  /// Follows the phone unless the person chose a mode.
  ThemeMode loadThemeMode() {
    final name = _store.read(key)?['themeMode'];
    return ThemeMode.values.asNameMap()[name] ?? ThemeMode.system;
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      _store.write(key, {'themeMode': mode.name});
}

class MemoryAppSettingsStorage extends AppSettingsStorage {
  MemoryAppSettingsStorage() : super(MemoryJsonStore());
}

class PrefsAppSettingsStorage extends AppSettingsStorage {
  PrefsAppSettingsStorage(SharedPreferences prefs)
    : super(PrefsJsonStore(prefs));
}

/// In memory by default so tests need no setup; `main()` swaps in
/// [PrefsAppSettingsStorage] (see `productionOverrides`).
final appSettingsStorageProvider = Provider<AppSettingsStorage>(
  (ref) => MemoryAppSettingsStorage(),
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(appSettingsStorageProvider).loadThemeMode();

  void set(ThemeMode mode) {
    state = mode;
    unawaited(ref.read(appSettingsStorageProvider).saveThemeMode(mode));
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
