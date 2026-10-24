import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart' as bank;
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bank/presentation/bank_flow_test.dart' as f;

const _players = [
  Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
  Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
];

ScoreGame midGame() {
  var g = ScoreGame.start(players: _players, roundCount: 5, targetScore: 100);
  g = g.setScore(round: 0, playerId: 'p1', score: 12);
  g = g.setScore(round: 0, playerId: 'p2', score: 7).finishRound();
  return g.setScore(round: 1, playerId: 'p1', score: 3);
}

bank.GameState bankGame() => bank.GameState.start(
  players: _players,
  startingCash: 1500,
  goAmount: 200,
).passGo('p1');

ProviderContainer containerWith({BankStorage? bank, ScoreStorage? score}) {
  final c = ProviderContainer(
    overrides: [
      bankStorageProvider.overrideWithValue(bank ?? MemoryBankStorage()),
      scoreStorageProvider.overrideWithValue(score ?? MemoryScoreStorage()),
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

  group('resuming Score Snitch', () {
    testWidgets('a saved game is offered with its helper and round', (
      tester,
    ) async {
      final score = MemoryScoreStorage();
      await score.saveGame(midGame());
      await f.pumpAt(tester, '/', container: containerWith(score: score));
      expect(byKey('resume-dialog'), findsOneWidget);
      expect(find.textContaining('Score Snitch'), findsWidgets);
      expect(find.textContaining('รอบ 2/5'), findsOneWidget);
    });

    testWidgets('continuing restores the board with its scores', (
      tester,
    ) async {
      final score = MemoryScoreStorage();
      await score.saveGame(midGame());
      final c = containerWith(score: score);
      await f.pumpAt(tester, '/', container: c);
      await tapKey(tester, 'resume-continue');
      expect(byKey('score-header-p1'), findsOneWidget);
      expect(tester.widget<Text>(byKey('score-value-0-p1')).data, '12');
      expect(tester.widget<Text>(byKey('score-value-1-p1')).data, '3');
      expect(c.read(scoreProvider)!.roundNumber, 2);
      expect(score.loadGame(), isNotNull, reason: 'kept while still playing');
    });

    testWidgets('a resumed game keeps being backed up', (tester) async {
      final score = MemoryScoreStorage();
      await score.saveGame(midGame());
      final c = containerWith(score: score);
      await f.pumpAt(tester, '/', container: c);
      await tapKey(tester, 'resume-continue');
      c
          .read(scoreProvider.notifier)
          .setScore(round: 1, playerId: 'p2', score: 9);
      expect(score.loadGame()!.scoreOf(1, 'p2'), 9);
    });

    testWidgets('discarding deletes the backup', (tester) async {
      final score = MemoryScoreStorage();
      await score.saveGame(midGame());
      final c = containerWith(score: score);
      await f.pumpAt(tester, '/', container: c);
      await tapKey(tester, 'resume-discard');
      expect(score.loadGame(), isNull);
      expect(c.read(scoreProvider), isNull);
      expect(byKey('resume-dialog'), findsNothing);
    });

    testWidgets('a finished game in the backup is dropped quietly', (
      tester,
    ) async {
      final score = MemoryScoreStorage();
      await score.saveGame(midGame().endNow());
      await f.pumpAt(tester, '/', container: containerWith(score: score));
      expect(byKey('resume-dialog'), findsNothing);
      expect(score.loadGame(), isNull);
    });

    testWidgets('a corrupt backup in real storage never reaches the dialog', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PrefsScoreStorage.gameKey: '{"v": 1, "players": []}',
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: productionOverrides(prefs));
      addTearDown(c.dispose);
      await f.pumpAt(tester, '/', container: c);
      expect(byKey('resume-dialog'), findsNothing);
      expect(prefs.containsKey(PrefsScoreStorage.gameKey), isFalse);
    });

    testWidgets('a game already open is not offered again', (tester) async {
      final score = MemoryScoreStorage();
      await score.saveGame(midGame());
      final c = containerWith(score: score);
      c.read(scoreProvider.notifier).restore(midGame());
      await f.pumpAt(tester, '/', container: c);
      expect(byKey('resume-dialog'), findsNothing);
    });
  });

  group('two helpers with a saved game', () {
    Future<(ProviderContainer, MemoryBankStorage, MemoryScoreStorage)> both(
      WidgetTester tester,
    ) async {
      final bankStorage = MemoryBankStorage();
      final scoreStorage = MemoryScoreStorage();
      await bankStorage.saveGame(bankGame());
      await scoreStorage.saveGame(midGame());
      final c = containerWith(bank: bankStorage, score: scoreStorage);
      await f.pumpAt(tester, '/', container: c);
      return (c, bankStorage, scoreStorage);
    }

    testWidgets('Pocket Banker is asked about first', (tester) async {
      await both(tester);
      expect(find.textContaining('Pocket Banker'), findsWidgets);
      expect(find.textContaining('Score Snitch: '), findsNothing);
    });

    testWidgets('resuming the first leaves the other for next time', (
      tester,
    ) async {
      final (c, bankStorage, scoreStorage) = await both(tester);
      await tapKey(tester, 'resume-continue');
      expect(byKey('player-card-p1'), findsOneWidget);
      expect(byKey('resume-dialog'), findsNothing);
      expect(c.read(bankProvider), isNotNull);
      expect(c.read(scoreProvider), isNull);
      expect(bankStorage.loadGame(), isNotNull);
      expect(scoreStorage.loadGame(), isNotNull);
    });

    testWidgets('discarding the first asks about the second', (tester) async {
      final (_, bankStorage, scoreStorage) = await both(tester);
      await tapKey(tester, 'resume-discard');
      expect(bankStorage.loadGame(), isNull);
      expect(byKey('resume-dialog'), findsOneWidget);
      expect(find.textContaining('Score Snitch'), findsWidgets);
      expect(find.textContaining('รอบ 2/5'), findsOneWidget);
      expect(scoreStorage.loadGame(), isNotNull);
    });

    testWidgets('discarding both clears both', (tester) async {
      final (c, bankStorage, scoreStorage) = await both(tester);
      await tapKey(tester, 'resume-discard');
      await tapKey(tester, 'resume-discard');
      expect(bankStorage.loadGame(), isNull);
      expect(scoreStorage.loadGame(), isNull);
      expect(byKey('resume-dialog'), findsNothing);
      expect(c.read(bankProvider), isNull);
      expect(c.read(scoreProvider), isNull);
    });

    testWidgets('discard the bank game, continue the score game', (
      tester,
    ) async {
      final (c, bankStorage, scoreStorage) = await both(tester);
      await tapKey(tester, 'resume-discard');
      await tapKey(tester, 'resume-continue');
      expect(byKey('score-header-p1'), findsOneWidget);
      expect(c.read(scoreProvider)!.roundNumber, 2);
      expect(c.read(bankProvider), isNull);
      expect(bankStorage.loadGame(), isNull);
      expect(scoreStorage.loadGame(), isNotNull);
    });

    testWidgets('each helper keeps to its own backup', (tester) async {
      final bankStorage = MemoryBankStorage();
      final scoreStorage = MemoryScoreStorage();
      final c = containerWith(bank: bankStorage, score: scoreStorage);
      c
          .read(bankProvider.notifier)
          .start(players: _players, startingCash: 1500, goAmount: 200);
      c
          .read(scoreProvider.notifier)
          .start(players: _players, roundCount: 3, winMode: WinMode.highest);
      c.read(scoreProvider.notifier).end();
      expect(scoreStorage.loadGame(), isNull);
      expect(bankStorage.loadGame(), isNotNull);
      c.read(bankProvider.notifier).end();
      expect(bankStorage.loadGame(), isNull);
    });
  });
}
