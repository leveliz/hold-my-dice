import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';

import '../../bank/presentation/bank_flow_test.dart' as f;

Finder byKey(String k) => f.byKey(k);

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

Future<void> typeInto(WidgetTester tester, String k, String value) async {
  await tester.enterText(byKey(k), value);
  await tester.pumpAndSettle();
}

ProviderContainer containerWith({PointStorage? storage}) {
  final c = ProviderContainer(
    overrides: [
      pointStorageProvider.overrideWithValue(storage ?? MemoryPointStorage()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

PointGame played({Side? leftSide}) {
  var g = PointGame.start(rules: PointRules(target: 21));
  Side? at(int r, int b) => g.rules.winnerAt(r, b);
  PointGame round(int red, int blue) {
    for (var i = 0; i < red; i++) {
      g = g.addPoint(Side.red);
    }
    for (var i = 0; i < blue; i++) {
      g = g.addPoint(Side.blue);
    }
    expect(at(red, blue), isNotNull);
    g = g.finishRound().startNextRound();
    return g;
  }

  round(21, 15);
  round(18, 21);
  round(21, 10);
  if (leftSide == Side.blue) g = g.swapSides();
  return g.endGame();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('setup', () {
    testWidgets('starts a game with the default names and no end', (
      tester,
    ) async {
      final c = containerWith();
      await f.pumpAt(tester, '/point', container: c);
      await tapKey(tester, 'start-game');
      final game = c.read(pointProvider)!;
      expect(game.redName, 'แดง');
      expect(game.blueName, 'น้ำเงิน');
      expect(game.rules.target, isNull);
      expect(byKey('half-red'), findsOneWidget);
    });

    testWidgets('the typed names and rules reach the game', (tester) async {
      final c = containerWith();
      await f.pumpAt(tester, '/point', container: c);
      await typeInto(tester, 'red-name', '  Fox  ');
      await typeInto(tester, 'blue-name', 'Owl');
      await typeInto(tester, 'target', '21');
      await tapKey(tester, 'deuce');
      await typeInto(tester, 'cap', '30');
      await tapKey(tester, 'start-game');
      final game = c.read(pointProvider)!;
      expect(game.redName, 'Fox');
      expect(game.blueName, 'Owl');
      expect(game.rules.target, 21);
      expect(game.rules.deuce, isTrue);
      expect(game.rules.cap, 30);
    });

    testWidgets('deuce and cap are offered only when they apply', (
      tester,
    ) async {
      await f.pumpAt(tester, '/point', container: containerWith());
      expect(byKey('deuce'), findsNothing);
      expect(byKey('cap'), findsNothing);
      await typeInto(tester, 'target', '21');
      expect(byKey('deuce'), findsOneWidget);
      expect(byKey('cap'), findsNothing);
      await tapKey(tester, 'deuce');
      expect(byKey('cap'), findsOneWidget);
      await tapKey(tester, 'deuce');
      expect(byKey('cap'), findsNothing);
    });

    testWidgets('clearing the target drops deuce from the game', (
      tester,
    ) async {
      final c = containerWith();
      await f.pumpAt(tester, '/point', container: c);
      await typeInto(tester, 'target', '21');
      await tapKey(tester, 'deuce');
      await typeInto(tester, 'cap', '30');
      await typeInto(tester, 'target', '');
      await tapKey(tester, 'start-game');
      final rules = c.read(pointProvider)!.rules;
      expect(rules.target, isNull);
      expect(rules.deuce, isFalse);
      expect(rules.cap, isNull);
    });

    testWidgets('a cap at or below the target blocks the start', (
      tester,
    ) async {
      await f.pumpAt(tester, '/point', container: containerWith());
      await typeInto(tester, 'target', '21');
      await tapKey(tester, 'deuce');
      await typeInto(tester, 'cap', '21');
      expect(byKey('cap-error'), findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(byKey('start-game')).onPressed,
        isNull,
      );
      await typeInto(tester, 'cap', '30');
      expect(byKey('cap-error'), findsNothing);
      await tapKey(tester, 'start-game');
      expect(byKey('half-red'), findsOneWidget);
    });

    testWidgets('a cap is not checked while deuce is off', (tester) async {
      await f.pumpAt(tester, '/point', container: containerWith());
      await typeInto(tester, 'target', '21');
      await tapKey(tester, 'deuce');
      await typeInto(tester, 'cap', '10');
      await tapKey(tester, 'deuce');
      expect(byKey('cap-error'), findsNothing);
      await tapKey(tester, 'start-game');
      expect(byKey('half-red'), findsOneWidget);
    });

    testWidgets('the last game is filled in and starting saves the next', (
      tester,
    ) async {
      final storage = MemoryPointStorage();
      await storage.saveSettings(
        PointSettings(
          redName: 'Fox',
          blueName: 'Owl',
          rules: PointRules(target: 21, deuce: true, cap: 30),
        ),
      );
      final c = containerWith(storage: storage);
      await f.pumpAt(tester, '/point', container: c);
      expect(
        tester.widget<TextField>(byKey('red-name')).controller!.text,
        'Fox',
      );
      expect(tester.widget<TextField>(byKey('target')).controller!.text, '21');
      expect(tester.widget<TextField>(byKey('cap')).controller!.text, '30');
      await typeInto(tester, 'blue-name', 'Cat');
      await tapKey(tester, 'start-game');
      final saved = storage.loadSettings()!;
      expect(saved.blueName, 'Cat');
      expect(saved.rules.cap, 30);
    });

    testWidgets('a blank name is saved as the default', (tester) async {
      final storage = MemoryPointStorage();
      final c = containerWith(storage: storage);
      await f.pumpAt(tester, '/point', container: c);
      await tapKey(tester, 'start-game');
      expect(storage.loadSettings()!.redName, 'แดง');
    });

    testWidgets('starting backs the game up', (tester) async {
      final storage = MemoryPointStorage();
      await f.pumpAt(
        tester,
        '/point',
        container: containerWith(storage: storage),
      );
      await tapKey(tester, 'start-game');
      expect(storage.loadGame(), isNotNull);
    });
  });

  group('summary', () {
    testWidgets('shows rounds won and every round', (tester) async {
      final c = containerWith();
      c.read(pointProvider.notifier).restore(played());
      await f.pumpAt(tester, '/point/summary', container: c);
      expect(tester.widget<Text>(byKey('summary-score')).data, '2 – 1');
      expect(tester.widget<Text>(byKey('summary-headline')).data, 'แดง ชนะ');
      expect(tester.widget<Text>(byKey('round-score-1')).data, '21 – 15');
      expect(tester.widget<Text>(byKey('round-score-2')).data, '18 – 21');
      expect(tester.widget<Text>(byKey('round-score-3')).data, '21 – 10');
      expect(tester.widget<Text>(byKey('round-winner-2')).data, 'น้ำเงิน');
    });

    testWidgets('scores follow the sides the teams ended on', (tester) async {
      final c = containerWith();
      c.read(pointProvider.notifier).restore(played(leftSide: Side.blue));
      await f.pumpAt(tester, '/point/summary', container: c);
      expect(tester.widget<Text>(byKey('summary-score')).data, '1 – 2');
      expect(tester.widget<Text>(byKey('round-score-1')).data, '15 – 21');
    });

    testWidgets('level rounds say the game was a draw', (tester) async {
      final c = containerWith();
      c
          .read(pointProvider.notifier)
          .restore(
            PointGame.start()
                .addPoint(Side.red)
                .finishRound()
                .startNextRound()
                .addPoint(Side.blue)
                .finishRound()
                .endGame(),
          );
      await f.pumpAt(tester, '/point/summary', container: c);
      expect(tester.widget<Text>(byKey('summary-headline')).data, 'ผลเสมอกัน');
    });

    testWidgets('a round that ended level is marked as a draw', (tester) async {
      final c = containerWith();
      c
          .read(pointProvider.notifier)
          .restore(
            PointGame.start()
                .addPoint(Side.red)
                .addPoint(Side.blue)
                .finishRound()
                .startNextRound()
                .endGame(),
          );
      await f.pumpAt(tester, '/point/summary', container: c);
      expect(tester.widget<Text>(byKey('round-winner-1')).data, 'เสมอ');
    });

    testWidgets('an empty game says nothing was played', (tester) async {
      final c = containerWith();
      c.read(pointProvider.notifier).restore(PointGame.start().endGame());
      await f.pumpAt(tester, '/point/summary', container: c);
      expect(
        tester.widget<Text>(byKey('summary-headline')).data,
        'ยังไม่มีรอบที่จบ',
      );
    });

    testWidgets('play again clears the game and opens the setup', (
      tester,
    ) async {
      final storage = MemoryPointStorage();
      await storage.saveGame(played());
      final c = containerWith(storage: storage);
      c.read(pointProvider.notifier).restore(played());
      await f.pumpAt(tester, '/point/summary', container: c);
      await tapKey(tester, 'play-again');
      expect(c.read(pointProvider), isNull);
      expect(storage.loadGame(), isNull);
      expect(byKey('start-game'), findsOneWidget);
    });

    testWidgets('home clears the game and opens the hub', (tester) async {
      final storage = MemoryPointStorage();
      await storage.saveGame(played());
      final c = containerWith(storage: storage);
      c.read(pointProvider.notifier).restore(played());
      await f.pumpAt(tester, '/point/summary', container: c);
      await tapKey(tester, 'back-to-hub');
      expect(c.read(pointProvider), isNull);
      expect(storage.loadGame(), isNull);
      expect(byKey('helper-point'), findsOneWidget);
    });

    testWidgets('names that are long still fit', (tester) async {
      final c = containerWith();
      c
          .read(pointProvider.notifier)
          .restore(
            PointGame.start(
              redName: 'ทีมที่ยาวมากมากมากมาก',
              blueName: 'ทีมที่ยาวมากมากมากมาก',
            ).addPoint(Side.red).endGame(),
          );
      await f.pumpAt(tester, '/point/summary', container: c);
      expect(tester.takeException(), isNull);
    });
  });
}
