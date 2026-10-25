import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';

import '../../bank/presentation/bank_flow_test.dart' as f;

const _landscape = Size(800, 400);

class RecordingMode implements ScreenMode {
  final calls = <String>[];

  @override
  void enterLandscapeImmersive() => calls.add('enter');

  @override
  void restore() => calls.add('restore');
}

class CountingAwake implements ScreenAwake {
  final calls = <String>[];

  @override
  void enable() => calls.add('on');

  @override
  void disable() => calls.add('off');
}

class CountingHaptics implements Haptics {
  int taps = 0;

  @override
  void transaction() => taps++;
}

ProviderContainer containerWith({
  PointStorage? storage,
  ScreenMode? mode,
  ScreenAwake? awake,
  Haptics? haptics,
  PointRules? rules,
  bool started = true,
}) {
  final c = ProviderContainer(
    overrides: [
      pointStorageProvider.overrideWithValue(storage ?? MemoryPointStorage()),
      if (mode != null) screenModeProvider.overrideWithValue(mode),
      if (awake != null) screenAwakeProvider.overrideWithValue(awake),
      if (haptics != null) hapticsProvider.overrideWithValue(haptics),
    ],
  );
  addTearDown(c.dispose);
  if (started) c.read(pointProvider.notifier).start(rules: rules);
  return c;
}

PointGame game(ProviderContainer c) => c.read(pointProvider)!;

Finder byKey(String k) => f.byKey(k);

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

Future<void> openBoard(WidgetTester tester, ProviderContainer c) =>
    f.pumpAt(tester, '/point/play', container: c, size: _landscape);

String scoreText(WidgetTester tester, String side) =>
    tester.widget<Text>(byKey('score-$side')).data!;

Future<void> score(WidgetTester tester, String side, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(byKey('half-$side'));
    await tester.pump();
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the board', () {
    testWidgets('a tap on a half adds a point and gives that side the serve', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tapKey(tester, 'half-blue');
      expect(scoreText(tester, 'blue'), '1');
      expect(scoreText(tester, 'red'), '0');
      expect(game(c).serving, Side.blue);
    });

    testWidgets('a swipe down takes a point off, never below zero', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 2);
      await tester.fling(byKey('half-red'), const Offset(0, 250), 1000);
      await tester.pumpAndSettle();
      expect(scoreText(tester, 'red'), '1');
      await tester.fling(byKey('half-blue'), const Offset(0, 250), 1000);
      await tester.pumpAndSettle();
      expect(scoreText(tester, 'blue'), '0');
    });

    testWidgets('a swipe up or a slow drag changes nothing', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 2);
      await tester.fling(byKey('half-red'), const Offset(0, -250), 1000);
      await tester.pumpAndSettle();
      await tester.drag(byKey('half-red'), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(scoreText(tester, 'red'), '2');
    });

    testWidgets('points are felt', (tester) async {
      final haptics = CountingHaptics();
      final c = containerWith(haptics: haptics);
      await openBoard(tester, c);
      await score(tester, 'red', 3);
      expect(haptics.taps, 3);
    });

    testWidgets('tapping the serve badge chooses who serves', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tapKey(tester, 'serve-blue');
      expect(game(c).serving, Side.blue);
      expect(scoreText(tester, 'blue'), '0', reason: 'not a point');
    });

    testWidgets('undo takes back the last change and the serve', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tapKey(tester, 'serve-red');
      await score(tester, 'blue', 1);
      await tapKey(tester, 'undo-button');
      expect(scoreText(tester, 'blue'), '0');
      expect(game(c).serving, Side.red);
    });

    testWidgets('undo is off until there is something to take back', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tester.tap(byKey('undo-button'));
      await tester.pump();
      expect(scoreText(tester, 'red'), '0');
      await score(tester, 'red', 1);
      await tapKey(tester, 'undo-button');
      expect(scoreText(tester, 'red'), '0');
    });

    testWidgets('swapping sides moves the teams with their points', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 3);
      expect(
        tester.getCenter(byKey('half-red')).dx,
        lessThan(tester.getCenter(byKey('half-blue')).dx),
      );
      await tapKey(tester, 'swap-button');
      expect(
        tester.getCenter(byKey('half-red')).dx,
        greaterThan(tester.getCenter(byKey('half-blue')).dx),
      );
      expect(scoreText(tester, 'red'), '3');
    });

    testWidgets('tapping a name renames the team', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tapKey(tester, 'name-red');
      expect(byKey('rename-dialog'), findsOneWidget);
      await tester.enterText(byKey('rename-field'), 'Fox');
      await tapKey(tester, 'rename-confirm');
      expect(game(c).redName, 'Fox');
      expect(find.text('Fox'), findsOneWidget);
      expect(scoreText(tester, 'red'), '0', reason: 'the tap was not a point');
    });

    testWidgets('an empty name goes back to the default', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tapKey(tester, 'name-blue');
      await tester.enterText(byKey('rename-field'), '   ');
      await tapKey(tester, 'rename-confirm');
      expect(game(c).blueName, 'น้ำเงิน');
    });

    testWidgets('a long press resets the round, a tap does not', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 4);
      await tester.tap(byKey('reset-button'));
      await tester.pump();
      expect(scoreText(tester, 'red'), '4');
      await tester.longPress(byKey('reset-button'));
      await tester.pumpAndSettle();
      expect(scoreText(tester, 'red'), '0');
      expect(game(c).rounds, isEmpty);
    });

    testWidgets('the round chip says the round and the rules', (tester) async {
      final c = containerWith(rules: PointRules(target: 21, deuce: true));
      await openBoard(tester, c);
      expect(
        find.descendant(
          of: byKey('round-chip'),
          matching: find.text('รอบ 1 · เป้า 21 ดิวส์'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a camera cut-out on one side does not move the chips', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(left: 60, top: 24);
      tester.view.viewPadding = const FakeViewPadding(left: 60, top: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await openBoard(tester, containerWith());
      expect(tester.getCenter(byKey('round-chip')).dx, closeTo(400, 1));
      expect(tester.getTopLeft(byKey('round-chip')).dy, greaterThan(24));
    });

    testWidgets('with no target the chip says the count is open', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      expect(find.text('รอบ 1 · ไม่จำกัดแต้ม'), findsOneWidget);
    });

    testWidgets('rounds won are shown for each side', (tester) async {
      final c = containerWith();
      c.read(pointProvider.notifier)
        ..addPoint(Side.red)
        ..finishRound()
        ..startNextRound();
      await openBoard(tester, c);
      expect(find.text('ชนะ 1 รอบ'), findsOneWidget);
      expect(find.text('ชนะ 0 รอบ'), findsOneWidget);
    });

    testWidgets('a long name is shortened, not pushed off', (tester) async {
      final c = containerWith();
      c.read(pointProvider.notifier).rename(Side.red, 'ทีมที่ยาวมากมากมาก');
      await openBoard(tester, c);
      expect(tester.takeException(), isNull);
    });

    testWidgets('big scores still fit', (tester) async {
      final c = containerWith();
      for (var i = 0; i < 188; i++) {
        c.read(pointProvider.notifier).addPoint(Side.blue);
      }
      await openBoard(tester, c);
      expect(tester.takeException(), isNull);
      expect(scoreText(tester, 'blue'), '188');
    });
  });

  group('finishing a round', () {
    testWidgets('is not possible at 0-0', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tester.tap(byKey('finish-round'));
      await tester.pumpAndSettle();
      expect(byKey('next-round-dialog'), findsNothing);
      expect(game(c).rounds, isEmpty);
    });

    testWidgets('the banner names the winner once the rules decide', (
      tester,
    ) async {
      final c = containerWith(rules: PointRules(target: 3));
      await openBoard(tester, c);
      await score(tester, 'blue', 2);
      expect(byKey('round-winner-banner'), findsNothing);
      await score(tester, 'blue', 1);
      expect(
        find.descendant(
          of: byKey('round-winner-banner'),
          matching: find.text('น้ำเงิน ชนะรอบนี้ · กดจบรอบ'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the round does not end by itself', (tester) async {
      final c = containerWith(rules: PointRules(target: 2));
      await openBoard(tester, c);
      await score(tester, 'red', 3);
      expect(game(c).rounds, isEmpty);
      expect(scoreText(tester, 'red'), '3');
    });

    testWidgets('the banner goes when an undo takes the win away', (
      tester,
    ) async {
      final c = containerWith(rules: PointRules(target: 2));
      await openBoard(tester, c);
      await score(tester, 'red', 2);
      expect(byKey('round-winner-banner'), findsOneWidget);
      await tapKey(tester, 'undo-button');
      expect(byKey('round-winner-banner'), findsNothing);
    });

    testWidgets('the check button is lit only once the rules have a winner', (
      tester,
    ) async {
      final c = containerWith(rules: PointRules(target: 2));
      await openBoard(tester, c);
      Color? fill() {
        final box = tester.widget<Container>(
          find
              .descendant(
                of: byKey('finish-round'),
                matching: find.byType(Container),
              )
              .first,
        );
        return (box.decoration! as BoxDecoration).color;
      }

      await score(tester, 'red', 1);
      expect(fill(), Colors.transparent);
      await score(tester, 'red', 1);
      expect(fill(), isNot(Colors.transparent));
    });

    testWidgets('it records the round and asks who serves first', (
      tester,
    ) async {
      final c = containerWith(rules: PointRules(target: 2));
      await openBoard(tester, c);
      await score(tester, 'red', 2);
      await tapKey(tester, 'finish-round');
      expect(byKey('next-round-dialog'), findsOneWidget);
      expect(find.textContaining('เริ่มรอบที่ 2'), findsOneWidget);
      expect(game(c).rounds.single.red, 2);
    });

    testWidgets('the dialog cannot be dismissed by tapping outside', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 1);
      await tapKey(tester, 'finish-round');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(byKey('next-round-dialog'), findsOneWidget);
    });

    testWidgets('choosing a server starts the next round at 0-0', (
      tester,
    ) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 5);
      await tapKey(tester, 'finish-round');
      await tapKey(tester, 'serve-first-blue');
      expect(byKey('next-round-dialog'), findsNothing);
      expect(scoreText(tester, 'red'), '0');
      expect(game(c).serving, Side.blue);
      expect(game(c).roundNumber, 2);
      expect(find.text('ชนะ 1 รอบ'), findsOneWidget);
    });

    testWidgets('the serve buttons follow the sides on screen', (tester) async {
      final c = containerWith();
      c.read(pointProvider.notifier).swapSides();
      await openBoard(tester, c);
      await score(tester, 'red', 1);
      await tapKey(tester, 'finish-round');
      expect(
        tester.getCenter(byKey('serve-first-blue')).dx,
        lessThan(tester.getCenter(byKey('serve-first-red')).dx),
      );
    });

    testWidgets('the dialog can end the game instead', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 4);
      await tapKey(tester, 'finish-round');
      await tapKey(tester, 'end-after-round');
      expect(byKey('summary-score'), findsOneWidget);
      expect(game(c).isOver, isTrue);
      expect(game(c).rounds.length, 1);
    });

    testWidgets('a game saved between rounds asks again when resumed', (
      tester,
    ) async {
      final c = containerWith(started: false);
      c
          .read(pointProvider.notifier)
          .restore(PointGame.start().addPoint(Side.red).finishRound());
      await openBoard(tester, c);
      expect(byKey('next-round-dialog'), findsOneWidget);
    });
  });

  group('ending and leaving', () {
    testWidgets('ending asks first and can be called off', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await tapKey(tester, 'end-game-button');
      expect(byKey('end-dialog'), findsOneWidget);
      await tapKey(tester, 'end-stay');
      expect(byKey('end-dialog'), findsNothing);
      expect(game(c).isOver, isFalse);
    });

    testWidgets('confirming shows the summary', (tester) async {
      final c = containerWith(rules: PointRules(target: 1));
      await openBoard(tester, c);
      await score(tester, 'red', 1);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      expect(byKey('summary-score'), findsOneWidget);
      expect(game(c).rounds.length, 1, reason: 'the rules had decided it');
    });

    testWidgets('back asks before the game is lost', (tester) async {
      final c = containerWith();
      await openBoard(tester, c);
      await score(tester, 'red', 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(byKey('leave-dialog'), findsOneWidget);
      await tapKey(tester, 'leave-stay');
      expect(c.read(pointProvider), isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tapKey(tester, 'leave-confirm');
      expect(c.read(pointProvider), isNull);
    });
  });

  group('the screen', () {
    testWidgets('goes sideways and full screen, then is given back', (
      tester,
    ) async {
      final mode = RecordingMode();
      final c = containerWith(mode: mode);
      await openBoard(tester, c);
      expect(mode.calls, ['enter']);
      await tester.pumpWidget(const SizedBox());
      expect(mode.calls, ['enter', 'restore']);
    });

    testWidgets('stays awake while playing', (tester) async {
      final awake = CountingAwake();
      final c = containerWith(awake: awake);
      await openBoard(tester, c);
      expect(awake.calls, ['on']);
      await tester.pumpWidget(const SizedBox());
      expect(awake.calls, ['on', 'off']);
    });

    testWidgets('the summary gives the screen back before it shows', (
      tester,
    ) async {
      final mode = RecordingMode();
      final c = containerWith(mode: mode);
      await openBoard(tester, c);
      await score(tester, 'red', 1);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      expect(mode.calls, ['enter', 'restore']);
    });
  });
}
