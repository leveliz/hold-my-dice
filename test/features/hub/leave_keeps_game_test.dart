import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart' as bank;
import 'package:hold_my_dice/features/hub/saved_games.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';

import '../bank/presentation/bank_flow_test.dart' as f;

const _bankPlayers = [
  bank.Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
  bank.Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
];

const _scorePlayers = [
  Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
  Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
];

ProviderContainer _container({
  MemoryBankStorage? bankStorage,
  MemoryScoreStorage? scoreStorage,
  MemoryPointStorage? pointStorage,
}) {
  final c = ProviderContainer(
    overrides: [
      bankStorageProvider.overrideWithValue(bankStorage ?? MemoryBankStorage()),
      scoreStorageProvider.overrideWithValue(
        scoreStorage ?? MemoryScoreStorage(),
      ),
      pointStorageProvider.overrideWithValue(
        pointStorage ?? MemoryPointStorage(),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void _startBank(ProviderContainer c) => c
    .read(bankProvider.notifier)
    .start(players: _bankPlayers, startingCash: 1500, goAmount: 200);

void _startScore(ProviderContainer c) => c
    .read(scoreProvider.notifier)
    .start(players: _scorePlayers, roundCount: 3, winMode: WinMode.highest);

void _startPoint(ProviderContainer c) => c
    .read(pointProvider.notifier)
    .start(redName: 'แดง', blueName: 'น้ำเงิน', rules: PointRules(target: 11));

Future<void> _leave(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await tester.tap(f.byKey('leave-confirm'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('leaving a game keeps it', () {
    testWidgets('Pocket Banker: the backup stays and the game is a saved one', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      final c = _container(bankStorage: storage);
      _startBank(c);
      await f.pumpAt(tester, '/bank/play', container: c);
      expect(find.text('ออกจากหน้าเกม?'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('ออกจากหน้าเกม?'), findsOneWidget);
      expect(find.textContaining('เมนูเกมค้าง'), findsOneWidget);
      await tester.tap(f.byKey('leave-confirm'));
      await tester.pumpAndSettle();
      expect(c.read(bankProvider), isNull);
      expect(storage.loadGame(), isNotNull);
      final saved = await loadSavedGames(c.read);
      expect([for (final g in saved) g.helperId], ['bank']);
    });

    testWidgets('Score Snitch', (tester) async {
      final storage = MemoryScoreStorage();
      final c = _container(scoreStorage: storage);
      _startScore(c);
      await f.pumpAt(tester, '/score/play', container: c);
      await _leave(tester);
      expect(c.read(scoreProvider), isNull);
      expect(storage.loadGame(), isNotNull);
      final saved = await loadSavedGames(c.read);
      expect([for (final g in saved) g.helperId], ['score']);
    });

    testWidgets('Point Blank', (tester) async {
      final storage = MemoryPointStorage();
      final c = _container(pointStorage: storage);
      _startPoint(c);
      await f.pumpAt(tester, '/point/play', container: c);
      await _leave(tester);
      expect(c.read(pointProvider), isNull);
      expect(storage.loadGame(), isNotNull);
      final saved = await loadSavedGames(c.read);
      expect([for (final g in saved) g.helperId], ['point']);
    });

    testWidgets('and staying changes nothing', (tester) async {
      final storage = MemoryBankStorage();
      final c = _container(bankStorage: storage);
      _startBank(c);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(f.byKey('leave-stay'));
      await tester.pumpAndSettle();
      expect(c.read(bankProvider), isNotNull);
      expect(storage.loadGame(), isNotNull);
    });

    testWidgets('ending the game still drops it', (tester) async {
      final storage = MemoryBankStorage();
      final c = _container(bankStorage: storage);
      _startBank(c);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tester.tap(f.byKey('end-game-button'));
      await tester.pumpAndSettle();
      await tester.tap(f.byKey('end-confirm'));
      await tester.pumpAndSettle();
      await tester.tap(f.byKey('back-to-hub'));
      await tester.pumpAndSettle();
      expect(storage.loadGame(), isNull);
      expect(await loadSavedGames(c.read), isEmpty);
    });
  });

  group('after leaving, back at the start page', () {
    testWidgets('it does not ask at once whether to play on', (tester) async {
      final c = _container();
      _startBank(c);
      await f.pumpAt(tester, '/bank/play', container: c);
      await _leave(tester);
      expect(find.text('Hold My Dice'), findsOneWidget);
      expect(find.byKey(const ValueKey('resume-dialog')), findsNothing);
    });

    testWidgets('the game is in the saved games tab, and plays on from there', (
      tester,
    ) async {
      final c = _container();
      _startBank(c);
      await f.pumpAt(tester, '/bank/play', container: c);
      await _leave(tester);
      await tester.tap(f.byKey('nav-saved'));
      await tester.pumpAndSettle();
      expect(find.text('Pocket Banker'), findsWidgets);
      await tester.tap(f.byKey('saved-continue-bank'));
      await tester.pumpAndSettle();
      expect(c.read(bankProvider), isNotNull);
      expect(find.byKey(const ValueKey('leave-dialog')), findsNothing);
    });

    testWidgets(
      'one launch asks about the games left once, not at every return',
      (tester) async {
        final bankStorage = MemoryBankStorage()
          ..saveGame(
            bank.GameState.start(
              players: _bankPlayers,
              startingCash: 1500,
              goAmount: 200,
            ),
          );
        final scoreStorage = MemoryScoreStorage();
        final c = _container(
          bankStorage: bankStorage,
          scoreStorage: scoreStorage,
        );
        scoreStorage.saveGame(
          ScoreGame.start(
            players: _scorePlayers,
            roundCount: 3,
            winMode: WinMode.highest,
          ),
        );
        await f.pumpAt(tester, '/', container: c);
        expect(find.byKey(const ValueKey('resume-dialog')), findsOneWidget);
        await tester.tap(f.byKey('resume-continue'));
        await tester.pumpAndSettle();
        await tester.tap(f.byKey('end-game-button'));
        await tester.pumpAndSettle();
        await tester.tap(f.byKey('end-confirm'));
        await tester.pumpAndSettle();
        await tester.tap(f.byKey('back-to-hub'));
        await tester.pumpAndSettle();
        expect(find.text('Hold My Dice'), findsOneWidget);
        // The other game waits in its tab instead of being asked about again,
        // also when the start page is built anew.
        expect(find.byKey(const ValueKey('resume-dialog')), findsNothing);
        await f.pumpAt(tester, '/', container: c);
        expect(find.byKey(const ValueKey('resume-dialog')), findsNothing);
        expect(scoreStorage.loadGame(), isNotNull);
      },
    );

    testWidgets('a new launch with a game in the backup asks once', (
      tester,
    ) async {
      final storage = MemoryBankStorage()
        ..saveGame(
          bank.GameState.start(
            players: _bankPlayers,
            startingCash: 1500,
            goAmount: 200,
          ),
        );
      final c = _container(bankStorage: storage);
      await f.pumpAt(tester, '/', container: c);
      expect(find.byKey(const ValueKey('resume-dialog')), findsOneWidget);
      await tester.tap(f.byKey('resume-continue'));
      await tester.pumpAndSettle();
      expect(c.read(bankProvider), isNotNull);
    });
  });

  group('starting a new game over a saved one', () {
    /// Fills in what each setup form needs (money for the bank, rounds for the
    /// score) and presses start.
    Future<void> press(WidgetTester tester, {String? helper}) async {
      if (helper == 'bank') {
        await tester.enterText(f.byKey('start-cash'), '1500');
        await tester.enterText(f.byKey('go-cash'), '200');
      } else if (helper == 'score') {
        await tester.enterText(f.byKey('rounds'), '5');
      }
      await tester.pump();
      await tester.ensureVisible(f.byKey('start-game'));
      await tester.tap(f.byKey('start-game'));
      await tester.pumpAndSettle();
    }

    testWidgets('Pocket Banker asks, and backing out keeps the old game', (
      tester,
    ) async {
      final storage = MemoryBankStorage();
      final c = _container(bankStorage: storage);
      _startBank(c);
      c.read(bankProvider.notifier).leave();
      await f.pumpAt(tester, '/bank', container: c);
      await press(tester, helper: 'bank');
      expect(find.byKey(const ValueKey('replace-dialog')), findsOneWidget);
      await tester.tap(f.byKey('replace-keep'));
      await tester.pumpAndSettle();
      expect(c.read(bankProvider), isNull);
      expect(storage.loadGame()?.activePlayers.length, 2);
    });

    testWidgets('Pocket Banker: agreeing starts the new game', (tester) async {
      final storage = MemoryBankStorage();
      final c = _container(bankStorage: storage);
      _startBank(c);
      c.read(bankProvider.notifier).leave();
      await f.pumpAt(tester, '/bank', container: c);
      await press(tester, helper: 'bank');
      await tester.tap(f.byKey('replace-confirm'));
      await tester.pumpAndSettle();
      expect(c.read(bankProvider), isNotNull);
      expect(find.byKey(const ValueKey('replace-dialog')), findsNothing);
    });

    testWidgets(
      'Pocket Banker: a game that was over is not worth asking about',
      (tester) async {
        final storage = MemoryBankStorage()
          ..saveGame(
            bank.GameState.start(
              players: _bankPlayers,
              startingCash: 1500,
              goAmount: 200,
            ).declareBankrupt('p2', owed: 5000),
          );
        expect(storage.loadGame()!.isOver, isTrue);
        final c = _container(bankStorage: storage);
        await f.pumpAt(tester, '/bank', container: c);
        await press(tester, helper: 'bank');
        expect(find.byKey(const ValueKey('replace-dialog')), findsNothing);
        expect(c.read(bankProvider), isNotNull);
      },
    );

    testWidgets('Pocket Banker: with no saved game it does not ask', (
      tester,
    ) async {
      final c = _container();
      await f.pumpAt(tester, '/bank', container: c);
      await press(tester, helper: 'bank');
      expect(find.byKey(const ValueKey('replace-dialog')), findsNothing);
      expect(c.read(bankProvider), isNotNull);
    });

    testWidgets('Score Snitch asks, and backing out keeps the old game', (
      tester,
    ) async {
      final storage = MemoryScoreStorage();
      final c = _container(scoreStorage: storage);
      _startScore(c);
      c.read(scoreProvider.notifier).leave();
      await f.pumpAt(tester, '/score', container: c);
      await press(tester, helper: 'score');
      expect(find.byKey(const ValueKey('replace-dialog')), findsOneWidget);
      await tester.tap(f.byKey('replace-keep'));
      await tester.pumpAndSettle();
      expect(c.read(scoreProvider), isNull);
      expect(storage.loadGame(), isNotNull);
    });

    testWidgets('Score Snitch: agreeing starts the new game', (tester) async {
      final c = _container();
      _startScore(c);
      c.read(scoreProvider.notifier).leave();
      await f.pumpAt(tester, '/score', container: c);
      await press(tester, helper: 'score');
      await tester.tap(f.byKey('replace-confirm'));
      await tester.pumpAndSettle();
      expect(c.read(scoreProvider), isNotNull);
    });

    testWidgets('Point Blank asks, and backing out keeps the old game', (
      tester,
    ) async {
      final storage = MemoryPointStorage();
      final c = _container(pointStorage: storage);
      _startPoint(c);
      c.read(pointProvider.notifier).leave();
      await f.pumpAt(tester, '/point', container: c);
      await press(tester);
      expect(find.byKey(const ValueKey('replace-dialog')), findsOneWidget);
      await tester.tap(f.byKey('replace-keep'));
      await tester.pumpAndSettle();
      expect(c.read(pointProvider), isNull);
      expect(storage.loadGame(), isNotNull);
    });

    testWidgets('Point Blank: agreeing starts the new game', (tester) async {
      final c = _container();
      _startPoint(c);
      c.read(pointProvider.notifier).leave();
      await f.pumpAt(tester, '/point', container: c);
      await press(tester);
      await tester.tap(f.byKey('replace-confirm'));
      await tester.pumpAndSettle();
      expect(c.read(pointProvider), isNotNull);
    });
  });
}
