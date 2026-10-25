import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart' as bank;
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bank/presentation/bank_flow_test.dart' as f;

const _players = [
  Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
  Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
];

PointGame midGame() {
  var g = PointGame.start(rules: PointRules(target: 21));
  for (var i = 0; i < 3; i++) {
    g = g.addPoint(Side.red);
  }
  for (var i = 0; i < 2; i++) {
    g = g.addPoint(Side.blue);
  }
  return g;
}

ProviderContainer containerWith({
  BankStorage? bank,
  ScoreStorage? score,
  PointStorage? point,
}) {
  final c = ProviderContainer(
    overrides: [
      bankStorageProvider.overrideWithValue(bank ?? MemoryBankStorage()),
      scoreStorageProvider.overrideWithValue(score ?? MemoryScoreStorage()),
      pointStorageProvider.overrideWithValue(point ?? MemoryPointStorage()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Finder byKey(String k) => f.byKey(k);

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the hub', () {
    testWidgets('has a Point Blank card that opens its setup', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(find.text('Point Blank'), findsOneWidget);
      expect(find.text('นับแต้มกีฬา 2 ฝั่ง'), findsOneWidget);
      await tapKey(tester, 'helper-point');
      expect(byKey('red-name'), findsOneWidget);
      expect(byKey('target'), findsOneWidget);
    });
  });

  group('resuming Point Blank', () {
    testWidgets('a saved game is offered with its round and score', (
      tester,
    ) async {
      final point = MemoryPointStorage();
      await point.saveGame(midGame());
      await f.pumpAt(tester, '/', container: containerWith(point: point));
      expect(byKey('resume-dialog'), findsOneWidget);
      expect(find.textContaining('Point Blank'), findsWidgets);
      expect(find.textContaining('รอบ 1 · 3–2'), findsOneWidget);
    });

    testWidgets('continuing opens the board with the score kept', (
      tester,
    ) async {
      final point = MemoryPointStorage();
      await point.saveGame(midGame());
      final c = containerWith(point: point);
      await f.pumpAt(tester, '/', container: c, size: const Size(800, 400));
      await tapKey(tester, 'resume-continue');
      expect(tester.widget<Text>(byKey('score-red')).data, '3');
      expect(tester.widget<Text>(byKey('score-blue')).data, '2');
      expect(point.loadGame(), isNotNull, reason: 'kept while still playing');
    });

    testWidgets('a resumed game keeps being backed up', (tester) async {
      final point = MemoryPointStorage();
      await point.saveGame(midGame());
      final c = containerWith(point: point);
      await f.pumpAt(tester, '/', container: c, size: const Size(800, 400));
      await tapKey(tester, 'resume-continue');
      c.read(pointProvider.notifier).addPoint(Side.blue);
      expect(point.loadGame()!.blue, 3);
    });

    testWidgets('discarding deletes the backup', (tester) async {
      final point = MemoryPointStorage();
      await point.saveGame(midGame());
      final c = containerWith(point: point);
      await f.pumpAt(tester, '/', container: c);
      await tapKey(tester, 'resume-discard');
      expect(point.loadGame(), isNull);
      expect(c.read(pointProvider), isNull);
      expect(byKey('resume-dialog'), findsNothing);
    });

    testWidgets('a finished game in the backup is dropped quietly', (
      tester,
    ) async {
      final point = MemoryPointStorage();
      await point.saveGame(midGame().endGame());
      await f.pumpAt(tester, '/', container: containerWith(point: point));
      expect(byKey('resume-dialog'), findsNothing);
      expect(point.loadGame(), isNull);
    });

    testWidgets('a corrupt backup in real storage never reaches the dialog', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PrefsPointStorage.gameKey: '{"v": 1, "red": -4}',
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: productionOverrides(prefs));
      addTearDown(c.dispose);
      await f.pumpAt(tester, '/', container: c);
      expect(byKey('resume-dialog'), findsNothing);
      expect(prefs.containsKey(PrefsPointStorage.gameKey), isFalse);
    });

    testWidgets('a game already open is not offered again', (tester) async {
      final point = MemoryPointStorage();
      await point.saveGame(midGame());
      final c = containerWith(point: point);
      c.read(pointProvider.notifier).restore(midGame());
      await f.pumpAt(tester, '/', container: c);
      expect(byKey('resume-dialog'), findsNothing);
    });
  });

  group('all three helpers with a saved game', () {
    Future<(ProviderContainer, PointStorage)> all(WidgetTester tester) async {
      final bankStorage = MemoryBankStorage();
      final scoreStorage = MemoryScoreStorage();
      final point = MemoryPointStorage();
      await bankStorage.saveGame(
        bank.GameState.start(
          players: _players,
          startingCash: 1500,
          goAmount: 200,
        ),
      );
      await scoreStorage.saveGame(
        ScoreGame.start(players: _players, roundCount: 3),
      );
      await point.saveGame(midGame());
      final c = containerWith(
        bank: bankStorage,
        score: scoreStorage,
        point: point,
      );
      await f.pumpAt(tester, '/', container: c, size: const Size(800, 400));
      return (c, point);
    }

    testWidgets('they are asked about in turn, Point Blank last', (
      tester,
    ) async {
      await all(tester);
      expect(find.textContaining('Pocket Banker'), findsWidgets);
      await tapKey(tester, 'resume-discard');
      expect(find.textContaining('Score Snitch'), findsWidgets);
      await tapKey(tester, 'resume-discard');
      expect(find.textContaining('Point Blank'), findsWidgets);
      expect(find.textContaining('รอบ 1 · 3–2'), findsOneWidget);
    });

    testWidgets('resuming the first leaves the other backups alone', (
      tester,
    ) async {
      final (c, point) = await all(tester);
      await tapKey(tester, 'resume-continue');
      expect(c.read(bankProvider), isNotNull);
      expect(c.read(scoreProvider), isNull);
      expect(c.read(pointProvider), isNull);
      expect(point.loadGame(), isNotNull);
    });

    testWidgets('discarding the first two and continuing the third', (
      tester,
    ) async {
      final (c, _) = await all(tester);
      await tapKey(tester, 'resume-discard');
      await tapKey(tester, 'resume-discard');
      await tapKey(tester, 'resume-continue');
      expect(byKey('half-red'), findsOneWidget);
      expect(c.read(pointProvider)!.red, 3);
    });

    testWidgets('each helper keeps to its own backup', (tester) async {
      final scoreStorage = MemoryScoreStorage();
      final point = MemoryPointStorage();
      final c = containerWith(score: scoreStorage, point: point);
      c.read(pointProvider.notifier).start();
      c
          .read(scoreProvider.notifier)
          .start(players: _players, roundCount: 3, winMode: WinMode.highest);
      c.read(pointProvider.notifier).end();
      expect(point.loadGame(), isNull);
      expect(scoreStorage.loadGame(), isNotNull);
    });
  });
}
