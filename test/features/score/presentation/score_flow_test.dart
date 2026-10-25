import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/players/player.dart' show PlayerSetting;
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../bank/presentation/bank_flow_test.dart' as f;

class CountingAwake implements ScreenAwake {
  int enabled = 0;
  int disabled = 0;

  @override
  void enable() => enabled++;

  @override
  void disable() => disabled++;
}

Finder byKey(String k) => f.byKey(k);

ProviderContainer containerWith({
  ScoreStorage? storage,
  ScreenAwake? awake,
  List<Override> overrides = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      ...overrides,
      scoreStorageProvider.overrideWithValue(storage ?? MemoryScoreStorage()),
      if (awake != null) screenAwakeProvider.overrideWithValue(awake),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

List<Player> seats(int n, {bool short = false}) => [
  for (var i = 1; i <= n; i++)
    Player(
      id: 'p$i',
      name: short ? String.fromCharCode(64 + i) : 'ผู้เล่น $i',
      color: 0xFF000000 + i * 0x1111,
    ),
];

ProviderContainer started({
  int players = 3,
  int rounds = 5,
  WinMode mode = WinMode.highest,
  int? target,
  bool short = false,
  ScoreStorage? storage,
  ScreenAwake? awake,
  List<Override> overrides = const [],
}) {
  final c = containerWith(storage: storage, awake: awake, overrides: overrides);
  c
      .read(scoreProvider.notifier)
      .start(
        players: seats(players, short: short),
        roundCount: rounds,
        winMode: mode,
        targetScore: target,
      );
  return c;
}

/// Enters the given scores for the current round through the notifier.
void fillRound(ProviderContainer c, List<int> scores) {
  final n = c.read(scoreProvider.notifier);
  final round = c.read(scoreProvider)!.currentRound;
  for (final (i, s) in scores.indexed) {
    n.setScore(round: round, playerId: 'p${i + 1}', score: s);
  }
}

ScoreGame gameOf(ProviderContainer c) => c.read(scoreProvider)!;

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await settle(tester);
}

/// Types characters on the score keypad (digits, + and -).
Future<void> typeExpr(WidgetTester tester, String chars) async {
  for (final ch in chars.split('')) {
    final id = switch (ch) {
      '+' => 'plus',
      '-' => 'minus',
      _ => ch,
    };
    await tester.tap(byKey('score-key-$id'));
    await tester.pump();
  }
}

String? valueAt(WidgetTester tester, int round, String id) {
  final finder = byKey('score-value-$round-$id');
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

String totalText(WidgetTester tester, String id) => tester
    .widget<Text>(
      find.descendant(
        of: byKey('score-total-$id'),
        matching: find.byType(Text),
      ),
    )
    .data!;

String exprText(WidgetTester tester) =>
    tester.widget<Text>(byKey('score-expr')).data!;

String resultText(WidgetTester tester) =>
    tester.widget<Text>(byKey('score-result')).data!;

bool enabled(WidgetTester tester, String key) =>
    tester.widget<FilledButton>(byKey(key)).onPressed != null;

Future<void> openBoard(
  WidgetTester tester,
  ProviderContainer c, {
  Size size = const Size(400, 800),
}) => f.pumpAt(tester, '/score/play', container: c, size: size);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('setup', () {
    testWidgets('two default players, and rounds are required', (tester) async {
      await f.pumpAt(tester, '/score', container: containerWith());
      expect(byKey('name-p1'), findsOneWidget);
      expect(byKey('name-p2'), findsOneWidget);
      expect(enabled(tester, 'start-game'), isFalse);
      await tester.enterText(byKey('rounds'), '10');
      await tester.pump();
      expect(enabled(tester, 'start-game'), isTrue);
    });

    testWidgets('the target is optional and the winner defaults to highest', (
      tester,
    ) async {
      final c = containerWith();
      await f.pumpAt(tester, '/score', container: c);
      await tester.enterText(byKey('rounds'), '4');
      await tester.pump();
      await tapKey(tester, 'start-game');
      final game = gameOf(c);
      expect(game.roundCount, 4);
      expect(game.targetScore, isNull);
      expect(game.winMode, WinMode.highest);
    });

    testWidgets('rules from the form reach the game', (tester) async {
      final c = containerWith();
      await f.pumpAt(tester, '/score', container: c);
      await tester.enterText(byKey('rounds'), '6');
      await tester.enterText(byKey('target'), '100');
      await tester.tap(find.text('น้อยสุดชนะ'));
      await tester.pump();
      await tapKey(tester, 'start-game');
      final game = gameOf(c);
      expect(game.roundCount, 6);
      expect(game.targetScore, 100);
      expect(game.winMode, WinMode.lowest);
      expect(game.players.length, 2);
    });

    testWidgets('fills everything in from the last game', (tester) async {
      final storage = MemoryScoreStorage();
      await storage.saveSettings(
        const ScoreSettings(
          players: [
            PlayerSetting(name: 'ต้น', color: 0xFF3D5AFE),
            PlayerSetting(name: 'ใบ', color: 0xFF2E9E57),
            PlayerSetting(name: 'ฟ้า', color: 0xFFE8920C),
          ],
          roundCount: 12,
          winMode: WinMode.lowest,
          targetScore: 1500,
        ),
      );
      await f.pumpAt(
        tester,
        '/score',
        container: containerWith(storage: storage),
      );
      String field(String key) =>
          tester.widget<TextField>(byKey(key)).controller!.text;
      expect(field('name-p1'), 'ต้น');
      expect(field('name-p3'), 'ฟ้า');
      expect(field('rounds'), '12');
      expect(field('target'), '1,500');
      final seg = tester.widget<SegmentedButton<WinMode>>(byKey('win-mode'));
      expect(seg.selected, {WinMode.lowest});
      expect(enabled(tester, 'start-game'), isTrue);
    });

    testWidgets('starting saves the settings for next time', (tester) async {
      final storage = MemoryScoreStorage();
      await f.pumpAt(
        tester,
        '/score',
        container: containerWith(storage: storage),
      );
      await tester.enterText(byKey('name-p1'), 'ต้น');
      await tester.enterText(byKey('rounds'), '8');
      await tester.enterText(byKey('target'), '50');
      await tester.pump();
      await tapKey(tester, 'start-game');
      final saved = storage.loadSettings()!;
      expect(saved.players.first.name, 'ต้น');
      expect(saved.roundCount, 8);
      expect(saved.targetScore, 50);
      expect(saved.winMode, WinMode.highest);
    });

    testWidgets('a cleared target is remembered as no target', (tester) async {
      final storage = MemoryScoreStorage();
      await storage.saveSettings(
        const ScoreSettings(
          players: [
            PlayerSetting(name: 'ก', color: 0xFF3D5AFE),
            PlayerSetting(name: 'ข', color: 0xFF2E9E57),
          ],
          roundCount: 5,
          winMode: WinMode.highest,
          targetScore: 100,
        ),
      );
      final c = containerWith(storage: storage);
      await f.pumpAt(tester, '/score', container: c);
      await tester.enterText(byKey('target'), '');
      await tester.pump();
      await tapKey(tester, 'start-game');
      expect(gameOf(c).targetScore, isNull);
      expect(storage.loadSettings()!.targetScore, isNull);
    });

    testWidgets('starting opens the board on round 1', (tester) async {
      final c = containerWith();
      await f.pumpAt(tester, '/score', container: c);
      await tester.enterText(byKey('rounds'), '10');
      await tester.pump();
      await tapKey(tester, 'start-game');
      expect(byKey('score-header-p1'), findsOneWidget);
      expect(find.text('รอบ 1/10'), findsOneWidget);
    });
  });

  group('board', () {
    testWidgets('shows a header per player and empty cells', (tester) async {
      final c = started();
      await openBoard(tester, c);
      for (final id in ['p1', 'p2', 'p3']) {
        expect(byKey('score-header-$id'), findsOneWidget);
        expect(byKey('score-empty-0-$id'), findsOneWidget);
        expect(totalText(tester, id), '0');
      }
      expect(find.text('รอบ 1/5'), findsOneWidget);
      expect(byKey('score-leader-p1'), findsNothing, reason: 'no score yet');
    });

    testWidgets('scores from the game fill the cells and totals', (
      tester,
    ) async {
      final c = started();
      fillRound(c, [12, 8, 15]);
      c.read(scoreProvider.notifier).finishRound();
      fillRound(c, [9, 14, -3]);
      await openBoard(tester, c);
      expect(valueAt(tester, 0, 'p3'), '15');
      expect(valueAt(tester, 1, 'p3'), '-3');
      expect(totalText(tester, 'p1'), '21');
      expect(totalText(tester, 'p2'), '22');
      expect(totalText(tester, 'p3'), '12');
      expect(find.text('รอบ 2/5'), findsOneWidget);
    });

    testWidgets('the leader is named, ties included', (tester) async {
      final c = started();
      fillRound(c, [9, 9, 1]);
      await openBoard(tester, c);
      expect(byKey('score-leader-p1'), findsOneWidget);
      expect(byKey('score-leader-p2'), findsOneWidget);
      expect(byKey('score-leader-p3'), findsNothing);
    });

    testWidgets('lowest-wins names the lowest', (tester) async {
      final c = started(mode: WinMode.lowest);
      fillRound(c, [9, 3, 6]);
      await openBoard(tester, c);
      expect(byKey('score-leader-p2'), findsOneWidget);
      expect(byKey('score-leader-p1'), findsNothing);
    });

    testWidgets('the finish button waits for everyone and starts a new round', (
      tester,
    ) async {
      final c = started();
      await openBoard(tester, c);
      expect(enabled(tester, 'finish-round'), isFalse);
      fillRound(c, [1, 2]);
      await tester.pump();
      expect(enabled(tester, 'finish-round'), isFalse);
      c
          .read(scoreProvider.notifier)
          .setScore(round: 0, playerId: 'p3', score: 0);
      await tester.pump();
      expect(enabled(tester, 'finish-round'), isTrue);
      await tapKey(tester, 'finish-round');
      expect(gameOf(c).roundNumber, 2);
      expect(find.text('รอบ 2/5'), findsOneWidget);
      expect(byKey('score-empty-1-p1'), findsOneWidget);
      expect(enabled(tester, 'finish-round'), isFalse);
    });
  });

  group('entering a score', () {
    testWidgets('tapping a cell opens the keypad for that player and round', (
      tester,
    ) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p2');
      expect(byKey('score-sheet'), findsOneWidget);
      expect(
        tester.widget<Text>(byKey('score-sheet-player')).data,
        'ผู้เล่น 2',
      );
      expect(tester.widget<Text>(byKey('score-sheet-round')).data, 'รอบ 1');
      expect(resultText(tester), '0');
      expect(enabled(tester, 'score-ok'), isFalse);
    });

    testWidgets('a number is saved to its cell and the next player comes up', (
      tester,
    ) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      await typeExpr(tester, '12');
      expect(resultText(tester), '12');
      await tapKey(tester, 'score-ok');
      expect(gameOf(c).scoreOf(0, 'p1'), 12);
      expect(
        tester.widget<Text>(byKey('score-sheet-player')).data,
        'ผู้เล่น 2',
      );
      expect(exprText(tester), '', reason: 'a fresh entry for the next player');
    });

    testWidgets('after the last player the keypad closes', (tester) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      for (final s in ['5', '6', '7']) {
        await typeExpr(tester, s);
        await tapKey(tester, 'score-ok');
      }
      expect(byKey('score-sheet'), findsNothing);
      expect(valueAt(tester, 0, 'p1'), '5');
      expect(valueAt(tester, 0, 'p2'), '6');
      expect(valueAt(tester, 0, 'p3'), '7');
      expect(enabled(tester, 'finish-round'), isTrue);
    });

    testWidgets('starting on a later player only advances from there', (
      tester,
    ) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p3');
      await typeExpr(tester, '4');
      await tapKey(tester, 'score-ok');
      expect(byKey('score-sheet'), findsNothing);
      expect(gameOf(c).scoreOf(0, 'p3'), 4);
    });

    testWidgets('a sum shows its result before confirming', (tester) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      await typeExpr(tester, '3+5+2');
      expect(exprText(tester), '3+5+2');
      expect(resultText(tester), '10');
      expect(enabled(tester, 'score-ok'), isTrue);
      await tapKey(tester, 'score-ok');
      expect(gameOf(c).scoreOf(0, 'p1'), 10);
    });

    testWidgets(
      'an unfinished sum shows what it is so far but cannot be saved',
      (tester) async {
        final c = started();
        await openBoard(tester, c);
        await tapKey(tester, 'score-cell-0-p1');
        await typeExpr(tester, '3+');
        expect(resultText(tester), '3');
        expect(enabled(tester, 'score-ok'), isFalse);
        await typeExpr(tester, '4');
        expect(resultText(tester), '7');
        expect(enabled(tester, 'score-ok'), isTrue);
      },
    );

    testWidgets('negative numbers and subtraction work', (tester) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      await typeExpr(tester, '-4');
      expect(resultText(tester), '-4');
      await tapKey(tester, 'score-ok');
      await typeExpr(tester, '10-3-1');
      expect(resultText(tester), '6');
      await tapKey(tester, 'score-ok');
      expect(gameOf(c).scoreOf(0, 'p1'), -4);
      expect(gameOf(c).scoreOf(0, 'p2'), 6);
      expect(totalText(tester, 'p1'), '-4');
    });

    testWidgets('backspace and clear edit the entry', (tester) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      await typeExpr(tester, '123');
      await tapKey(tester, 'score-key-back');
      expect(exprText(tester), '12');
      await tapKey(tester, 'score-key-clear');
      expect(exprText(tester), '');
      expect(enabled(tester, 'score-ok'), isFalse);
      await tapKey(tester, 'score-key-back');
      expect(exprText(tester), '', reason: 'nothing left to delete');
    });

    testWidgets('a number cannot get longer than 9 digits', (tester) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      await typeExpr(tester, '12345678901234');
      expect(exprText(tester), '123456789');
      await typeExpr(tester, '+7');
      expect(exprText(tester), '123456789+7');
    });

    testWidgets('the button names the next player', (tester) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      expect(find.textContaining('ต่อไป ผู้เล่น 2'), findsOneWidget);
      await tapKey(tester, 'score-cell-0-p3');
    });

    testWidgets('the sheet shows the current total of the player', (
      tester,
    ) async {
      final c = started();
      fillRound(c, [5, 5, 5]);
      c.read(scoreProvider.notifier).finishRound();
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-1-p2');
      final total = tester
          .widget<Text>(
            find.descendant(
              of: byKey('score-sheet-total'),
              matching: find.byType(Text),
            ),
          )
          .data;
      expect(total, '5');
    });
  });

  group('correcting a score', () {
    testWidgets('an earlier round can be changed and totals follow', (
      tester,
    ) async {
      final c = started();
      fillRound(c, [10, 5, 1]);
      c.read(scoreProvider.notifier).finishRound();
      fillRound(c, [0, 0, 0]);
      c.read(scoreProvider.notifier).finishRound();
      await openBoard(tester, c);
      expect(byKey('score-leader-p1'), findsOneWidget);

      await tapKey(tester, 'score-cell-0-p3');
      expect(
        tester.widget<Text>(byKey('score-sheet-existing')).data,
        'ค่าเดิมของรอบนี้ 1',
      );
      expect(tester.widget<Text>(byKey('score-sheet-round')).data, 'รอบ 1');
      await typeExpr(tester, '50');
      await tapKey(tester, 'score-ok');
      expect(totalText(tester, 'p3'), '50');
      expect(byKey('score-leader-p3'), findsOneWidget);
      expect(byKey('score-leader-p1'), findsNothing);
      expect(gameOf(c).roundNumber, 3, reason: 'still on the same round');
    });

    testWidgets('a score in the current round can be replaced', (tester) async {
      final c = started();
      fillRound(c, [1, 2, 3]);
      await openBoard(tester, c);
      await tapKey(tester, 'score-cell-0-p1');
      await typeExpr(tester, '9');
      await tapKey(tester, 'score-ok');
      expect(gameOf(c).scoreOf(0, 'p1'), 9);
      await tapKey(tester, 'score-key-back');
    });
  });

  group('target score', () {
    testWidgets(
      'shows how far the leader is, then that the target is reached',
      (tester) async {
        final c = started(target: 100);
        fillRound(c, [30, 45, 10]);
        await openBoard(tester, c);
        expect(
          tester.widget<Text>(byKey('score-target-info')).data,
          'ห่างเป้า 55',
        );
        c
            .read(scoreProvider.notifier)
            .setScore(round: 0, playerId: 'p2', score: 120);
        await tester.pump();
        expect(
          tester.widget<Text>(byKey('score-target-info')).data,
          contains('ถึงเป้า 100 แล้ว'),
        );
        expect(find.text('จบรอบและจบเกม'), findsOneWidget);
      },
    );

    testWidgets('no target means no distance line', (tester) async {
      final c = started();
      fillRound(c, [30, 45, 10]);
      await openBoard(tester, c);
      expect(byKey('score-target-info'), findsNothing);
    });

    testWidgets('finishing a round that reached it ends the game', (
      tester,
    ) async {
      final c = started(target: 50);
      fillRound(c, [60, 10, 20]);
      await openBoard(tester, c);
      await tapKey(tester, 'finish-round');
      expect(byKey('summary-headline'), findsOneWidget);
      expect(find.textContaining('มีคนถึงเป้า 50'), findsOneWidget);
    });
  });

  group('ending the game', () {
    testWidgets('finishing the last round shows the summary', (tester) async {
      final c = started(rounds: 1);
      fillRound(c, [3, 9, 6]);
      await openBoard(tester, c);
      await tapKey(tester, 'finish-round');
      expect(find.textContaining('ครบ 1 รอบแล้ว'), findsOneWidget);
      expect(gameOf(c).endReason, EndReason.allRoundsPlayed);
    });

    testWidgets('the flag asks first and staying keeps playing', (
      tester,
    ) async {
      final c = started();
      await openBoard(tester, c);
      await tapKey(tester, 'end-game-button');
      expect(byKey('end-dialog'), findsOneWidget);
      await tapKey(tester, 'end-stay');
      expect(byKey('end-dialog'), findsNothing);
      expect(gameOf(c).isOver, isFalse);
      expect(byKey('score-header-p1'), findsOneWidget);
    });

    testWidgets('confirming ends it early with what was entered', (
      tester,
    ) async {
      final c = started();
      fillRound(c, [3, 9]);
      await openBoard(tester, c);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      expect(gameOf(c).endReason, EndReason.endedManually);
      expect(find.textContaining('จบเกมก่อนกำหนด'), findsOneWidget);
      expect(find.textContaining('ผู้เล่น 2'), findsWidgets);
    });

    testWidgets('back asks before leaving, and leaving drops the game', (
      tester,
    ) async {
      final storage = MemoryScoreStorage();
      final c = started(storage: storage);
      await openBoard(tester, c);
      expect(storage.loadGame(), isNotNull);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(byKey('leave-dialog'), findsOneWidget);
      await tapKey(tester, 'leave-stay');
      expect(storage.loadGame(), isNotNull);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tapKey(tester, 'leave-confirm');
      expect(find.text('Hold My Dice'), findsOneWidget);
      expect(c.read(scoreProvider), isNull);
      expect(storage.loadGame(), isNull);
    });

    testWidgets('the screen stays on only while the board is open', (
      tester,
    ) async {
      final awake = CountingAwake();
      final c = started(awake: awake);
      await openBoard(tester, c);
      expect(awake.enabled, 1);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tapKey(tester, 'leave-confirm');
      expect(awake.disabled, 1);
    });
  });

  group('summary', () {
    ProviderContainer finished(
      List<int> scores, {
      WinMode mode = WinMode.highest,
    }) {
      final c = started(players: scores.length, rounds: 1, mode: mode);
      fillRound(c, scores);
      c.read(scoreProvider.notifier).finishRound();
      return c;
    }

    testWidgets('ranks by score with the winner first', (tester) async {
      final c = finished([3, 9, 6]);
      await f.pumpAt(tester, '/score/summary', container: c);
      double top(String id) => tester.getTopLeft(byKey('rank-$id')).dy;
      expect(top('p2'), lessThan(top('p3')));
      expect(top('p3'), lessThan(top('p1')));
      expect(find.byIcon(LucideIcons.trophy), findsOneWidget);
      expect(tester.widget<Text>(byKey('rank-number-p3')).data, '2');
      expect(tester.widget<Text>(byKey('rank-number-p1')).data, '3');
      expect(find.textContaining('ผู้ชนะ ผู้เล่น 2'), findsOneWidget);
    });

    testWidgets('equal scores share a rank and the next one is skipped', (
      tester,
    ) async {
      final c = finished([9, 9, 5, 1]);
      await f.pumpAt(tester, '/score/summary', container: c);
      expect(find.byIcon(LucideIcons.trophy), findsNWidgets(2));
      expect(tester.widget<Text>(byKey('rank-number-p3')).data, '3');
      expect(tester.widget<Text>(byKey('rank-number-p4')).data, '4');
      expect(
        find.textContaining('ผู้ชนะร่วม ผู้เล่น 1, ผู้เล่น 2'),
        findsOneWidget,
      );
    });

    testWidgets('a tie in the middle shares that rank, not its position', (
      tester,
    ) async {
      final c = finished([9, 5, 5, 1]);
      await f.pumpAt(tester, '/score/summary', container: c);
      String rank(String id) =>
          tester.widget<Text>(byKey('rank-number-$id')).data!;
      expect(rank('p2'), '2');
      expect(rank('p3'), '2');
      expect(rank('p4'), '4');
      expect(find.byIcon(LucideIcons.trophy), findsOneWidget);
    });

    testWidgets('lowest wins puts the lowest score first', (tester) async {
      final c = finished([9, 2, 5], mode: WinMode.lowest);
      await f.pumpAt(tester, '/score/summary', container: c);
      double top(String id) => tester.getTopLeft(byKey('rank-$id')).dy;
      expect(top('p2'), lessThan(top('p3')));
      expect(top('p3'), lessThan(top('p1')));
    });

    testWidgets('scores are shown with their sign', (tester) async {
      final c = finished([-5, 3]);
      await f.pumpAt(tester, '/score/summary', container: c);
      final chip = tester.widget<Text>(
        find.descendant(
          of: byKey('rank-score-p1'),
          matching: find.byType(Text),
        ),
      );
      expect(chip.data, '-5');
    });

    testWidgets('play again clears the game and opens the setup', (
      tester,
    ) async {
      final storage = MemoryScoreStorage();
      final c = started(players: 2, rounds: 1, storage: storage);
      fillRound(c, [1, 2]);
      c.read(scoreProvider.notifier).finishRound();
      await f.pumpAt(tester, '/score/summary', container: c);
      await tapKey(tester, 'play-again');
      expect(find.text('ตั้งค่าเกม'), findsOneWidget);
      expect(c.read(scoreProvider), isNull);
      expect(storage.loadGame(), isNull);
    });

    testWidgets('back to the hub clears the game', (tester) async {
      final storage = MemoryScoreStorage();
      final c = started(players: 2, rounds: 1, storage: storage);
      fillRound(c, [1, 2]);
      c.read(scoreProvider.notifier).finishRound();
      await f.pumpAt(tester, '/score/summary', container: c);
      await tapKey(tester, 'back-to-hub');
      expect(find.text('Hold My Dice'), findsOneWidget);
      expect(storage.loadGame(), isNull);
    });

    testWidgets('the whole table can be read, but not edited', (tester) async {
      final c = finished([3, 9, 6]);
      await f.pumpAt(tester, '/score/summary', container: c);
      await tapKey(tester, 'view-table');
      expect(find.text('ตารางคะแนน'), findsOneWidget);
      expect(valueAt(tester, 0, 'p2'), '9');
      expect(totalText(tester, 'p2'), '9');
      await tester.tap(byKey('score-cell-0-p2'), warnIfMissed: false);
      await settle(tester);
      expect(byKey('score-sheet'), findsNothing);
    });
  });

  group('wide and long scoreboards', () {
    testWidgets('many players scroll sideways and every name is reachable', (
      tester,
    ) async {
      final c = started(players: 9, short: true);
      fillRound(c, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      await openBoard(tester, c);
      expect(tester.takeException(), isNull);
      await tester.drag(byKey('score-columns-scroll'), const Offset(-1000, 0));
      await tester.pump();
      expect(byKey('score-header-p9'), findsOneWidget);
      expect(tester.getTopLeft(byKey('score-header-p9')).dx, lessThan(400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the round column stays put while the columns scroll', (
      tester,
    ) async {
      final c = started(players: 9, short: true);
      await openBoard(tester, c);
      final before = tester.getTopLeft(byKey('score-round-0')).dx;
      await tester.drag(byKey('score-columns-scroll'), const Offset(-600, 0));
      await tester.pump();
      expect(tester.getTopLeft(byKey('score-round-0')).dx, before);
    });

    testWidgets('few players share the width', (tester) async {
      final c = started(players: 2, short: true);
      await openBoard(tester, c);
      final a = tester.getSize(byKey('score-header-p1')).width;
      expect(a, greaterThan(150), reason: 'columns grow to fill the screen');
    });

    testWidgets('many rounds scroll and the labels stay aligned with rows', (
      tester,
    ) async {
      final c = started(rounds: 30, short: true);
      for (var r = 0; r < 14; r++) {
        fillRound(c, [r, r + 1, r + 2]);
        c.read(scoreProvider.notifier).finishRound();
      }
      await openBoard(tester, c, size: const Size(400, 600));
      expect(tester.takeException(), isNull);
      // Scrolling the rows moves the round numbers with them.
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump();
      final label = tester.getCenter(byKey('score-round-12')).dy;
      final cell = tester.getCenter(byKey('score-cell-12-p1')).dy;
      expect(label, closeTo(cell, 1));
    });

    testWidgets('a new round scrolls into view', (tester) async {
      final c = started(rounds: 30, short: true);
      for (var r = 0; r < 14; r++) {
        fillRound(c, [r, r, r]);
        c.read(scoreProvider.notifier).finishRound();
      }
      await openBoard(tester, c, size: const Size(400, 600));
      fillRound(c, [1, 1, 1]);
      await tester.pump();
      await tapKey(tester, 'finish-round');
      expect(byKey('score-round-15'), findsOneWidget);
      expect(
        tester.getTopLeft(byKey('score-round-15')).dy,
        lessThan(tester.view.physicalSize.height),
      );
    });
  });
}
