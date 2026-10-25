import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';

import 'score_flow_test.dart' as s;

Finder byKey(String k) => s.byKey(k);

/// The tour's hand never stops moving, so the page cannot "settle".
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ProviderContainer> openScore(
  WidgetTester tester, {
  int players = 3,
  TourStorage? tours,
  Size size = const Size(400, 800),
  void Function(ProviderContainer c)? prepare,
}) async {
  final c = s.started(
    players: players,
    overrides: [
      tourStorageProvider.overrideWithValue(tours ?? MemoryTourStorage()),
    ],
  );
  prepare?.call(c);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light),
        routerConfig: createRouter(initialLocation: '/score/play'),
      ),
    ),
  );
  await settle(tester);
  return c;
}

String title(WidgetTester tester) =>
    tester.widget<Text>(byKey('tour-title')).data!;
String count(WidgetTester tester) =>
    tester.widget<Text>(byKey('tour-step')).data!;
Rect spot(WidgetTester tester, [int i = 0]) =>
    tester.getRect(byKey('tour-spot-$i'));

Future<void> next(WidgetTester tester) async {
  await tester.tap(byKey('tour-next'));
  await settle(tester);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the tour of Score Snitch', () {
    testWidgets('opens the first time, five steps', (tester) async {
      await openScore(tester);
      expect(byKey('tour-card'), findsOneWidget);
      expect(title(tester), 'รอบและคนนำ');
      expect(count(tester), '1/5');
    });

    testWidgets('does not open for someone who has seen it', (tester) async {
      await openScore(
        tester,
        tours: MemoryTourStorage()..markSeen([TourIds.score]),
      );
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('each step lights up the right thing', (tester) async {
      await openScore(tester);
      // 1: the round and leader line
      expect(
        spot(tester).contains(tester.getCenter(byKey('score-round-pill'))),
        isTrue,
      );
      await next(tester);
      // 2: the whole table
      expect(title(tester), 'ตารางคะแนน');
      expect(
        spot(tester).contains(tester.getCenter(byKey('score-header-p1'))),
        isTrue,
      );
      expect(
        spot(tester).contains(tester.getCenter(byKey('score-total-p3'))),
        isTrue,
      );
      await next(tester);
      // 3: the first empty cell of the round, and only that one
      expect(title(tester), 'กรอกคะแนน');
      final cell = tester.getCenter(byKey('score-cell-0-p1'));
      expect(spot(tester).contains(cell), isTrue);
      expect(
        spot(tester).contains(tester.getCenter(byKey('score-cell-0-p2'))),
        isFalse,
      );
      await next(tester);
      // 4: finish the round
      expect(title(tester), 'จบรอบ');
      expect(
        spot(tester).contains(tester.getCenter(byKey('finish-round'))),
        isTrue,
      );
      await next(tester);
      // 5: back to the table
      expect(title(tester), 'แก้คะแนนที่ผิด');
      expect(
        spot(tester).contains(tester.getCenter(byKey('score-header-p1'))),
        isTrue,
      );
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
    });

    testWidgets('the cell step lights the first empty cell after a resume', (
      tester,
    ) async {
      await openScore(
        tester,
        prepare: (c) => c
            .read(scoreProvider.notifier)
            .setScore(round: 0, playerId: 'p1', score: 5),
      );
      await next(tester);
      await next(tester);
      expect(title(tester), 'กรอกคะแนน');
      expect(
        spot(tester).contains(tester.getCenter(byKey('score-cell-0-p2'))),
        isTrue,
      );
      expect(
        spot(tester).contains(tester.getCenter(byKey('score-cell-0-p1'))),
        isFalse,
      );
    });

    testWidgets('the cell step is left out when the round is filled in', (
      tester,
    ) async {
      await openScore(tester, prepare: (c) => s.fillRound(c, [1, 2, 3]));
      expect(count(tester), '1/4');
      await next(tester);
      await next(tester);
      expect(title(tester), 'จบรอบ');
    });

    testWidgets('the card stays clear of what is lit, except over the table', (
      tester,
    ) async {
      await openScore(tester);
      for (var i = 0; i < 5; i++) {
        final card = tester.getRect(byKey('tour-card'));
        expect(card.bottom, lessThanOrEqualTo(800), reason: 'step $i');
        // The table fills most of the screen, so its two steps have no free
        // place for the card: it sits over the empty rows.
        final overTable = i == 1 || i == 4;
        if (!overTable) {
          expect(spot(tester).overlaps(card), isFalse, reason: 'step $i');
        }
        if (i < 4) await next(tester);
      }
    });

    testWidgets('finishing and skipping both count as seen', (tester) async {
      final finished = MemoryTourStorage();
      await openScore(tester, tours: finished);
      for (var i = 0; i < 5; i++) {
        await next(tester);
      }
      expect(finished.isSeen(TourIds.score), isTrue);
    });

    testWidgets('skip leaves the game as it was', (tester) async {
      final tours = MemoryTourStorage();
      final c = await openScore(tester, tours: tours);
      await tester.tap(byKey('tour-skip'));
      await settle(tester);
      expect(tours.isSeen(TourIds.score), isTrue);
      expect(byKey('tour-card'), findsNothing);
      expect(s.gameOf(c).currentRound, 0);
    });

    testWidgets('a tap on the lit cell during the tour opens nothing', (
      tester,
    ) async {
      await openScore(tester);
      await next(tester);
      await next(tester);
      await tester.tap(byKey('score-cell-0-p1'), warnIfMissed: false);
      await settle(tester);
      expect(byKey('score-sheet'), findsNothing);
    });

    testWidgets('many players and a long table do not break it', (
      tester,
    ) async {
      await openScore(tester, players: 9);
      for (var i = 0; i < 5; i++) {
        if (byKey('tour-card').evaluate().isEmpty) break;
        await next(tester);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('works in the dark look', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = s.started(
        overrides: [tourStorageProvider.overrideWithValue(MemoryTourStorage())],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: buildTheme(Brightness.dark),
            routerConfig: createRouter(initialLocation: '/score/play'),
          ),
        ),
      );
      await settle(tester);
      expect(byKey('tour-card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
