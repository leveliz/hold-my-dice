import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/core/settings/app_settings.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer containerWith(AppSettingsStorage storage) {
  final c = ProviderContainer(
    overrides: [appSettingsStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('follows the phone until a mode is chosen', () {
    final c = containerWith(MemoryAppSettingsStorage());
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('a chosen mode is kept and read back next time', () {
    final storage = MemoryAppSettingsStorage();
    final first = containerWith(storage);
    first.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(first.read(themeModeProvider), ThemeMode.dark);
    expect(storage.loadThemeMode(), ThemeMode.dark);
    expect(containerWith(storage).read(themeModeProvider), ThemeMode.dark);
  });

  test('every mode survives the round trip', () {
    for (final mode in ThemeMode.values) {
      final storage = MemoryAppSettingsStorage();
      containerWith(storage).read(themeModeProvider.notifier).set(mode);
      expect(storage.loadThemeMode(), mode);
    }
  });

  test('an unknown saved mode falls back to the phone setting', () {
    final raw = MemoryJsonStore()
      ..putRaw(AppSettingsStorage.key, '{"themeMode": "sepia"}');
    expect(AppSettingsStorage(raw).loadThemeMode(), ThemeMode.system);
  });

  test('unreadable saved settings fall back to the phone setting', () {
    final raw = MemoryJsonStore()..putRaw(AppSettingsStorage.key, 'not json');
    expect(AppSettingsStorage(raw).loadThemeMode(), ThemeMode.system);
  });

  test('the installed app keeps the mode in shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: productionOverrides(prefs));
    addTearDown(c.dispose);
    expect(c.read(appSettingsStorageProvider), isA<PrefsAppSettingsStorage>());
    c.read(themeModeProvider.notifier).set(ThemeMode.light);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(AppSettingsStorage.key), contains('light'));
  });
}
