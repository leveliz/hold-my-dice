import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/core/settings/app_settings.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BrokenStore extends MemoryJsonStore {
  @override
  Future<void> write(String key, Map<String, dynamic> value) =>
      Future<void>.error(StateError('storage is full'));
}

void main() {
  test('nothing has been seen on a fresh install', () {
    final tours = TourStorage(MemoryJsonStore());
    expect(tours.isSeen(TourIds.bank), isFalse);
    expect(tours.isSeen(TourIds.point), isFalse);
  });

  test('what was seen is remembered next time', () {
    final store = MemoryJsonStore();
    TourStorage(store).markSeen([TourIds.bank, TourIds.score]);
    final next = TourStorage(store);
    expect(next.isSeen(TourIds.bank), isTrue);
    expect(next.isSeen(TourIds.score), isTrue);
    expect(next.isSeen(TourIds.point), isFalse);
  });

  test('forgetting makes a tour show again, only that one', () {
    final store = MemoryJsonStore();
    TourStorage(store)
      ..markSeen([TourIds.bank, TourIds.score])
      ..forget([TourIds.bank]);
    final next = TourStorage(store);
    expect(next.isSeen(TourIds.bank), isFalse);
    expect(next.isSeen(TourIds.score), isTrue);
  });

  test('the tips of a helper are forgotten with its tour', () {
    final store = MemoryJsonStore();
    final tours = TourStorage(store)
      ..markSeen([TourIds.bank, ...TourIds.bankTips, TourIds.score]);
    tours.forget(TourIds.of('bank'));
    expect(tours.isSeen(TourIds.bank), isFalse);
    for (final tip in TourIds.bankTips) {
      expect(tours.isSeen(tip), isFalse, reason: tip);
    }
    expect(tours.isSeen(TourIds.score), isTrue);
  });

  test('the theme and the tours do not overwrite each other', () {
    final store = MemoryJsonStore();
    TourStorage(store).markSeen([TourIds.bank]);
    AppSettingsStorage(store).saveThemeMode(ThemeMode.dark);
    expect(TourStorage(store).isSeen(TourIds.bank), isTrue);
    TourStorage(store).markSeen([TourIds.score]);
    expect(AppSettingsStorage(store).loadThemeMode(), ThemeMode.dark);
  });

  test('unreadable saved data counts as nothing seen', () {
    final store = MemoryJsonStore()..putRaw(TourStorage.key, 'not json');
    expect(TourStorage(store).isSeen(TourIds.bank), isFalse);
    final odd = MemoryJsonStore()..putRaw(TourStorage.key, '{"seen": 7}');
    expect(TourStorage(odd).isSeen(TourIds.bank), isFalse);
  });

  test('a store that cannot write still remembers for this session', () async {
    final tours = TourStorage(_BrokenStore())..markSeen([TourIds.bank]);
    await Future<void>.delayed(Duration.zero);
    expect(tours.isSeen(TourIds.bank), isTrue);
  });

  test('tests start with every tour already seen', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final tours = c.read(tourStorageProvider);
    expect(tours.isSeen(TourIds.bank), isTrue);
    expect(tours.isSeen(TourIds.point), isTrue);
    tours.forget([TourIds.bank]);
    expect(tours.isSeen(TourIds.bank), isTrue);
  });

  test('the installed app keeps what was seen in shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: productionOverrides(prefs));
    addTearDown(c.dispose);
    final tours = c.read(tourStorageProvider);
    expect(tours, isA<PrefsTourStorage>());
    expect(tours.isSeen(TourIds.bank), isFalse);
    tours.markSeen([TourIds.bank]);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(TourStorage.key), contains(TourIds.bank));
  });
}
