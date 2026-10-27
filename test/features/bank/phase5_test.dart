import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'presentation/bank_flow_test.dart' as f;

class CountingAwake implements ScreenAwake {
  int enabled = 0;
  int disabled = 0;

  @override
  void enable() => enabled++;

  @override
  void disable() => disabled++;
}

class CountingHaptics implements Haptics {
  int taps = 0;

  @override
  void transaction() => taps++;
}

ProviderContainer containerWith({
  BankStorage? storage,
  ScreenAwake? awake,
  Haptics? haptics,
}) {
  final c = ProviderContainer(
    overrides: [
      bankStorageProvider.overrideWithValue(storage ?? MemoryBankStorage()),
      if (awake != null) screenAwakeProvider.overrideWithValue(awake),
      if (haptics != null) hapticsProvider.overrideWithValue(haptics),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

const _players = [
  Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
  Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
  Player(id: 'p3', name: 'ฟ้า', color: 0xFFE8920C),
];

GameState sampleGame() => GameState.start(
  players: _players,
  startingCash: 1500,
  goAmount: 200,
).passGo('p1').receiveFromBank('p2', 300);

GameSettings sampleSettings() => const GameSettings(
  players: [
    PlayerSetting(name: 'ต้น', color: 0xFF3D5AFE),
    PlayerSetting(name: 'ใบ', color: 0xFF2E9E57),
    PlayerSetting(name: 'ฟ้า', color: 0xFFE8920C),
  ],
  startingCash: 1500,
  goAmount: 200,
);

String gameJson(GameState g) => jsonEncode(g.toJson());

Finder byKey(String k) => f.byKey(k);

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('PrefsBankStorage', () {
    Future<PrefsBankStorage> storage([
      Map<String, Object> initial = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initial);
      return PrefsBankStorage(await SharedPreferences.getInstance());
    }

    test('settings survive a save and load', () async {
      final s = await storage();
      expect(s.loadSettings(), isNull);
      await s.saveSettings(sampleSettings());
      final loaded = s.loadSettings()!;
      expect(loaded.players.map((p) => p.name), ['ต้น', 'ใบ', 'ฟ้า']);
      expect(loaded.players.map((p) => p.color), [
        0xFF3D5AFE,
        0xFF2E9E57,
        0xFFE8920C,
      ]);
      expect(loaded.startingCash, 1500);
      expect(loaded.goAmount, 200);
    });

    test(
      'a running game survives a save and load, then can be cleared',
      () async {
        final s = await storage();
        expect(s.loadGame(), isNull);
        await s.saveGame(sampleGame());
        expect(gameJson(s.loadGame()!), gameJson(sampleGame()));
        await s.clearGame();
        expect(s.loadGame(), isNull);
      },
    );

    test('data written by a new PrefsBankStorage is read by another', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await PrefsBankStorage(prefs).saveGame(sampleGame());
      expect(PrefsBankStorage(prefs).loadGame(), isNotNull);
    });

    test('a corrupt backup is dropped instead of crashing', () async {
      final s = await storage({PrefsBankStorage.gameKey: 'not json {'});
      expect(s.loadGame(), isNull);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          PrefsBankStorage.gameKey,
        ),
        isFalse,
      );
    });

    test('a backup from another version is dropped', () async {
      final json = sampleGame().toJson()..['v'] = 99;
      final s = await storage({PrefsBankStorage.gameKey: jsonEncode(json)});
      expect(s.loadGame(), isNull);
    });

    test('corrupt settings are dropped too', () async {
      final s = await storage({PrefsBankStorage.settingsKey: '{"players": 5}'});
      expect(s.loadSettings(), isNull);
    });
  });

  group('session backup', () {
    test('starting a game backs it up straight away', () {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      expect(storage.loadGame(), isNotNull);
      expect(storage.loadGame()!.history, isEmpty);
    });

    test('every transaction and every undo updates the backup', () {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      final n = c.read(bankProvider.notifier);
      n.start(players: _players, startingCash: 1500, goAmount: 200);

      n.passGo('p1');
      expect(storage.loadGame()!.balanceOf('p1'), 1700);
      n.transfer('p1', 'p2', 500);
      expect(storage.loadGame()!.balanceOf('p2'), 2000);
      n.undo();
      expect(storage.loadGame()!.balanceOf('p2'), 1500);
      expect(
        gameJson(storage.loadGame()!),
        gameJson(c.read(bankProvider)!.game),
      );
    });

    test('a refused payment is not backed up', () {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      final n = c.read(bankProvider.notifier);
      n.start(players: _players, startingCash: 1500, goAmount: 200);
      n.pay('p1', 5000);
      expect(storage.loadGame()!.history, isEmpty);
    });

    test('ending the game deletes the backup', () {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      final n = c.read(bankProvider.notifier);
      n.start(players: _players, startingCash: 1500, goAmount: 200);
      n.passGo('p1');
      n.end();
      expect(storage.loadGame(), isNull);
      expect(c.read(bankProvider), isNull);
    });

    test('restore continues the game with nothing to undo', () {
      final c = containerWith();
      c.read(bankProvider.notifier).restore(sampleGame());
      final s = c.read(bankProvider)!;
      expect(s.game.balanceOf('p1'), 1700);
      expect(s.undoAvailable, isFalse);
    });

    test('a restored game keeps being backed up', () {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      final n = c.read(bankProvider.notifier);
      n.restore(sampleGame());
      n.passGo('p2');
      expect(storage.loadGame()!.balanceOf('p2'), 2000);
    });
  });

  group('haptics', () {
    test('a successful transaction gives one tap', () {
      final h = CountingHaptics();
      final c = containerWith(haptics: h);
      final n = c.read(bankProvider.notifier);
      n.start(players: _players, startingCash: 1500, goAmount: 200);
      expect(h.taps, 0);
      n.passGo('p1');
      expect(h.taps, 1);
      n.receive('p2', 100);
      n.pay('p3', 100);
      n.transfer('p1', 'p2', 50);
      expect(h.taps, 4);
    });

    test('a refused payment, undo and restore give none', () {
      final h = CountingHaptics();
      final c = containerWith(haptics: h);
      final n = c.read(bankProvider.notifier);
      n.start(players: _players, startingCash: 1500, goAmount: 200);
      n.pay('p1', 5000);
      expect(h.taps, 0);
      n.passGo('p1');
      n.undo();
      expect(h.taps, 1);
    });

    test('mortgage with payment and bankruptcy count once each', () {
      final h = CountingHaptics();
      final c = containerWith(haptics: h);
      final n = c.read(bankProvider.notifier);
      n.start(players: _players, startingCash: 1500, goAmount: 200);
      n.payWithMortgage(
        payerId: 'p1',
        payeeId: 'p2',
        amount: 2000,
        mortgages: [200, 300],
      );
      expect(h.taps, 1);
      n.pay('p3', 1500);
      n.declareBankrupt('p3', owed: 10);
      expect(h.taps, 3);
    });

    testWidgets('SystemHaptics sends a light impact to the platform', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const SystemHaptics().transaction();
      await tester.pump();
      expect(
        calls
            .where((c) => c.method == 'HapticFeedback.vibrate')
            .single
            .arguments,
        'HapticFeedbackType.lightImpact',
      );
    });
  });

  group('real wiring', () {
    test(
      'production overrides use the real storage, wakelock and haptics',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final c = ProviderContainer(overrides: productionOverrides(prefs));
        addTearDown(c.dispose);
        expect(c.read(bankStorageProvider), isA<PrefsBankStorage>());
        expect(c.read(screenAwakeProvider), isA<WakelockScreenAwake>());
        expect(c.read(hapticsProvider), isA<SystemHaptics>());
      },
    );

    test('the defaults used by tests do nothing', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(bankStorageProvider), isA<MemoryBankStorage>());
      expect(c.read(screenAwakeProvider), isA<NoScreenAwake>());
      expect(c.read(hapticsProvider), isA<NoHaptics>());
    });

    test('a game started with production storage is resumable later', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = ProviderContainer(overrides: productionOverrides(prefs));
      first
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      first.read(bankProvider.notifier).passGo('p1');
      first.dispose();

      // A new "app launch" over the same preferences.
      final second = ProviderContainer(overrides: productionOverrides(prefs));
      addTearDown(second.dispose);
      expect(
        second.read(bankStorageProvider).loadGame()!.balanceOf('p1'),
        1700,
      );
    });
  });

  group('setup remembers the last game', () {
    testWidgets('starts with two default players when nothing is saved', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank', container: containerWith());
      expect(byKey('name-p1'), findsOneWidget);
      expect(byKey('name-p2'), findsOneWidget);
      expect(byKey('name-p3'), findsNothing);
      expect(
        tester.widget<TextField>(byKey('start-cash')).controller!.text,
        '',
      );
    });

    testWidgets('fills in names, colours and money from the last game', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveSettings(sampleSettings());
      await f.pumpAt(
        tester,
        '/bank',
        container: containerWith(storage: storage),
      );

      String name(String id) =>
          tester.widget<TextField>(byKey('name-$id')).controller!.text;
      expect([name('p1'), name('p2'), name('p3')], ['ต้น', 'ใบ', 'ฟ้า']);
      Color dot(String id) =>
          (tester
                      .widget<Container>(
                        find.descendant(
                          of: byKey('color-$id'),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(dot('p1'), const Color(0xFF3D5AFE));
      expect(dot('p3'), const Color(0xFFE8920C));
      expect(
        tester.widget<TextField>(byKey('start-cash')).controller!.text,
        '1,500',
      );
      expect(
        tester.widget<TextField>(byKey('go-cash')).controller!.text,
        '200',
      );
      expect(
        tester.widget<FilledButton>(byKey('start-game')).onPressed,
        isNotNull,
      );
    });

    testWidgets('everything can still be edited before starting', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveSettings(sampleSettings());
      final c = containerWith(storage: storage);
      await f.pumpAt(tester, '/bank', container: c);
      await tester.enterText(byKey('name-p1'), 'แบงค์');
      await tester.enterText(byKey('start-cash'), '20000');
      await tester.pump();
      await tapKey(tester, 'remove-p3');
      await tapKey(tester, 'start-game');
      final game = c.read(bankProvider)!.game;
      expect(game.players.map((p) => p.name), ['แบงค์', 'ใบ']);
      expect(game.startingCash, 20000);
      expect(game.goAmount, 200);
    });

    testWidgets('starting saves the settings for next time', (tester) async {
      final storage = MemoryBankStorage();
      await f.pumpAt(
        tester,
        '/bank',
        container: containerWith(storage: storage),
      );
      await tester.enterText(byKey('name-p1'), 'ต้น');
      await tester.enterText(byKey('start-cash'), '1500');
      await tester.enterText(byKey('go-cash'), '200');
      await tester.pump();
      await tapKey(tester, 'start-game');

      final saved = storage.loadSettings()!;
      expect(saved.players.first.name, 'ต้น');
      expect(saved.players.length, 2);
      expect(saved.startingCash, 1500);
      expect(saved.goAmount, 200);
    });

    testWidgets('a blank name is saved as its default name', (tester) async {
      final storage = MemoryBankStorage();
      await f.pumpAt(
        tester,
        '/bank',
        container: containerWith(storage: storage),
      );
      await tester.enterText(byKey('name-p2'), '   ');
      await tester.enterText(byKey('start-cash'), '1000');
      await tester.enterText(byKey('go-cash'), '100');
      await tester.pump();
      await tapKey(tester, 'start-game');
      expect(storage.loadSettings()!.players[1].name, 'ผู้เล่น 2');
    });

    testWidgets('one saved player is ignored (a game needs two)', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveSettings(
        const GameSettings(
          players: [PlayerSetting(name: 'เดี่ยว', color: 0xFF3D5AFE)],
          startingCash: 1500,
          goAmount: 200,
        ),
      );
      await f.pumpAt(
        tester,
        '/bank',
        container: containerWith(storage: storage),
      );
      expect(byKey('name-p2'), findsOneWidget);
      expect(
        tester.widget<TextField>(byKey('name-p1')).controller!.text,
        'ผู้เล่น 1',
      );
    });
  });

  group('resuming after the app was closed', () {
    testWidgets('no saved game: no question', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(byKey('resume-dialog'), findsNothing);
    });

    testWidgets('a saved game is offered and continuing restores it', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveGame(sampleGame());
      final c = containerWith(storage: storage);
      await f.pumpAt(tester, '/', container: c);

      expect(byKey('resume-dialog'), findsOneWidget);
      expect(find.text('เล่นเกมต่อไหม?'), findsOneWidget);
      await tapKey(tester, 'resume-continue');

      expect(byKey('player-card-p1'), findsOneWidget);
      expect(f.balance(tester, 'p1'), '1,700');
      expect(f.balance(tester, 'p2'), '1,800');
      expect(f.balance(tester, 'p3'), '1,500');
      expect(byKey('undo-bar'), findsNothing);
      expect(storage.loadGame(), isNotNull);
    });

    testWidgets('a resumed game keeps going and stays backed up', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveGame(sampleGame());
      final c = containerWith(storage: storage);
      await f.pumpAt(tester, '/', container: c);
      await tapKey(tester, 'resume-continue');
      await tapKey(tester, 'btn-go-p3');
      expect(f.balance(tester, 'p3'), '1,700');
      expect(storage.loadGame()!.balanceOf('p3'), 1700);
    });

    testWidgets('discarding deletes the backup and nothing resumes', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveGame(sampleGame());
      final c = containerWith(storage: storage);
      await f.pumpAt(tester, '/', container: c);
      await tapKey(tester, 'resume-discard');
      expect(byKey('resume-dialog'), findsNothing);
      expect(storage.loadGame(), isNull);
      expect(c.read(bankProvider), isNull);
      expect(find.text('Hold My Dice'), findsOneWidget);
    });

    testWidgets('the dialog cannot be dismissed by tapping outside', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveGame(sampleGame());
      await f.pumpAt(tester, '/', container: containerWith(storage: storage));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(byKey('resume-dialog'), findsOneWidget);
    });

    testWidgets('a finished game in the backup is dropped quietly', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      final over = GameState.start(
        players: _players.take(2).toList(),
        startingCash: 1500,
        goAmount: 200,
      );
      final lost = ((over.payBank('p1', 1500)) as Paid).state.declareBankrupt(
        'p1',
        owed: 10,
      );
      expect(lost.isOver, isTrue);
      await storage.saveGame(lost);
      await f.pumpAt(tester, '/', container: containerWith(storage: storage));
      expect(byKey('resume-dialog'), findsNothing);
      expect(storage.loadGame(), isNull);
    });

    testWidgets('a game already open in memory is not offered again', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      await storage.saveGame(sampleGame());
      final c = containerWith(storage: storage);
      c.read(bankProvider.notifier).restore(sampleGame());
      await f.pumpAt(tester, '/', container: c);
      expect(byKey('resume-dialog'), findsNothing);
    });

    testWidgets('a corrupt backup in real storage never reaches the dialog', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PrefsBankStorage.gameKey: '{"v": 1, "players": []}',
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: productionOverrides(prefs));
      addTearDown(c.dispose);
      await f.pumpAt(tester, '/', container: c);
      expect(byKey('resume-dialog'), findsNothing);
      expect(prefs.containsKey(PrefsBankStorage.gameKey), isFalse);
    });
  });

  group('leaving a game', () {
    testWidgets('confirming the exit dialog keeps its backup', (tester) async {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      await f.pumpAt(tester, '/bank/play', container: c);
      expect(storage.loadGame(), isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tapKey(tester, 'leave-confirm');
      expect(storage.loadGame(), isNotNull);
    });

    testWidgets('staying keeps the backup', (tester) async {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tapKey(tester, 'leave-stay');
      expect(storage.loadGame(), isNotNull);
    });

    testWidgets('leaving from the summary page', (tester) async {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      expect(storage.loadGame(), isNotNull);
      await tapKey(tester, 'back-to-hub');
      expect(storage.loadGame(), isNull);
    });

    testWidgets('playing again from the summary page', (tester) async {
      final storage = MemoryBankStorage();
      final c = containerWith(storage: storage);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      await tapKey(tester, 'play-again');
      expect(storage.loadGame(), isNull);
    });
  });

  group('screen stays on while playing', () {
    testWidgets('on in the play screen, off again when leaving', (
      tester,
    ) async {
      final awake = CountingAwake();
      final c = containerWith(awake: awake);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      await f.pumpAt(tester, '/bank/play', container: c);
      expect(awake.enabled, 1);
      expect(awake.disabled, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tapKey(tester, 'leave-confirm');
      expect(awake.disabled, 1);
    });

    testWidgets('not switched on by the hub or the setup page', (tester) async {
      final awake = CountingAwake();
      await f.pumpAt(tester, '/bank', container: containerWith(awake: awake));
      expect(awake.enabled, 0);
    });

    testWidgets('the summary page lets the screen sleep again', (tester) async {
      final awake = CountingAwake();
      final c = containerWith(awake: awake);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      expect(awake.disabled, 1);
    });
  });
}
