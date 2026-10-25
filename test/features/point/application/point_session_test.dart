import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountingHaptics implements Haptics {
  int taps = 0;

  @override
  void transaction() => taps++;
}

ProviderContainer containerWith({PointStorage? storage, Haptics? haptics}) {
  final c = ProviderContainer(
    overrides: [
      pointStorageProvider.overrideWithValue(storage ?? MemoryPointStorage()),
      if (haptics != null) hapticsProvider.overrideWithValue(haptics),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

PointNotifier notifier(ProviderContainer c) => c.read(pointProvider.notifier);

PointGame game(ProviderContainer c) => c.read(pointProvider)!;

String json(PointGame g) => jsonEncode(g.toJson());

void main() {
  group('backup', () {
    test('there is no game until one is started', () {
      expect(containerWith().read(pointProvider), isNull);
    });

    test('starting backs the new game up', () {
      final storage = MemoryPointStorage();
      final c = containerWith(storage: storage);
      notifier(c).start(redName: 'ต้น', blueName: 'ใบ');
      expect(game(c).redName, 'ต้น');
      expect(json(storage.loadGame()!), json(game(c)));
    });

    test('every change is backed up', () {
      final storage = MemoryPointStorage();
      final c = containerWith(storage: storage);
      final n = notifier(c)..start();
      void backedUp() => expect(json(storage.loadGame()!), json(game(c)));

      n.addPoint(Side.red);
      backedUp();
      n.addPoint(Side.blue);
      backedUp();
      n.removePoint(Side.blue);
      backedUp();
      n.undo();
      backedUp();
      n.chooseServer(Side.blue);
      backedUp();
      n.swapSides();
      backedUp();
      n.rename(Side.red, 'ทีมแดง');
      backedUp();
      n.finishRound();
      backedUp();
      n.startNextRound(firstServer: Side.red);
      backedUp();
      n.addPoint(Side.red);
      n.reset();
      backedUp();
      n.endGame();
      backedUp();
      expect(storage.loadGame()!.isOver, isTrue);
    });

    test('restoring does not rewrite the backup it came from', () {
      final storage = MemoryPointStorage();
      final c = containerWith(storage: storage);
      notifier(c).restore(PointGame.start().addPoint(Side.red));
      expect(game(c).red, 1);
      expect(storage.loadGame(), isNull);
    });

    test('ending drops the game and its backup', () {
      final storage = MemoryPointStorage();
      final c = containerWith(storage: storage);
      notifier(c)
        ..start()
        ..addPoint(Side.red)
        ..end();
      expect(c.read(pointProvider), isNull);
      expect(storage.loadGame(), isNull);
    });

    test('settings are kept apart from the game backup', () async {
      final storage = MemoryPointStorage();
      await storage.saveSettings(
        PointSettings(
          redName: 'ต้น',
          blueName: 'ใบ',
          rules: PointRules(target: 21, deuce: true, cap: 30),
        ),
      );
      final c = containerWith(storage: storage);
      notifier(c)
        ..start()
        ..end();
      final saved = storage.loadSettings()!;
      expect(saved.redName, 'ต้น');
      expect(saved.rules.cap, 30);
    });

    test('the real storage keeps the game under its own key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          pointStorageProvider.overrideWithValue(PrefsPointStorage(prefs)),
        ],
      );
      addTearDown(c.dispose);
      notifier(c)
        ..start()
        ..addPoint(Side.blue);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.containsKey(PrefsPointStorage.gameKey), isTrue);
      expect(prefs.containsKey('score.game.v1'), isFalse);
    });

    test('the installed app uses the real storage and screen mode', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: productionOverrides(prefs));
      addTearDown(c.dispose);
      expect(c.read(pointStorageProvider), isA<PrefsPointStorage>());
      expect(c.read(screenModeProvider), isA<SystemScreenMode>());
    });

    test('a corrupt saved game is dropped when read', () {
      final raw = MemoryJsonStore()..putRaw(PointStorage.gameKey, '{"v": 99}');
      expect(PointStorage(raw).loadGame(), isNull);
      expect(raw.read(PointStorage.gameKey), isNull);
    });
  });

  group('haptics', () {
    test('a point either way is felt', () {
      final haptics = CountingHaptics();
      final c = containerWith(haptics: haptics);
      notifier(c)
        ..start()
        ..addPoint(Side.red)
        ..removePoint(Side.red);
      expect(haptics.taps, 2);
    });

    test('taking a point off a side at zero is not felt', () {
      final haptics = CountingHaptics();
      final c = containerWith(haptics: haptics);
      final n = notifier(c)..start();
      n.removePoint(Side.red);
      expect(haptics.taps, 0);
      expect(game(c).red, 0);
    });

    test('undo and the control buttons stay quiet', () {
      final haptics = CountingHaptics();
      final c = containerWith(haptics: haptics);
      notifier(c)
        ..start()
        ..swapSides()
        ..chooseServer(Side.red)
        ..reset();
      expect(haptics.taps, 0);
    });
  });

  group('play', () {
    test('the rules given at the start decide the round', () {
      final c = containerWith();
      notifier(c).start(rules: PointRules(target: 2));
      notifier(c)
        ..addPoint(Side.blue)
        ..addPoint(Side.blue);
      expect(game(c).roundWinner, Side.blue);
    });

    test('a round finished and the next started keeps the score list', () {
      final c = containerWith();
      notifier(c)
        ..start()
        ..addPoint(Side.red)
        ..finishRound()
        ..startNextRound(firstServer: Side.blue);
      expect(game(c).rounds.length, 1);
      expect(game(c).red, 0);
      expect(game(c).serving, Side.blue);
    });
  });
}
