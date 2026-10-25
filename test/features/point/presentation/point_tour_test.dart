import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';

import 'point_flow_test.dart' as p;

const _sideways = Size(800, 400);

Finder byKey(String k) => p.byKey(k);

/// The tour's hand never stops moving, so the page cannot "settle".
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ProviderContainer> openBoard(
  WidgetTester tester, {
  TourStorage? tours,
  Size size = _sideways,
  bool needsManualRotation = false,
  void Function(ProviderContainer c)? prepare,
}) async {
  final c = p.containerWith(
    needsManualRotation: needsManualRotation,
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
        routerConfig: createRouter(initialLocation: '/point/play'),
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
Rect spot(WidgetTester tester) => tester.getRect(byKey('tour-spot-0'));

Future<void> next(WidgetTester tester) async {
  await tester.tap(byKey('tour-next'));
  await settle(tester);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the tour of Point Blank', () {
    testWidgets('opens the first time, five steps', (tester) async {
      await openBoard(tester);
      expect(byKey('tour-card'), findsOneWidget);
      expect(title(tester), 'แตะเพื่อเพิ่มแต้ม');
      expect(count(tester), '1/5');
    });

    testWidgets('does not open for someone who has seen it', (tester) async {
      await openBoard(
        tester,
        tours: MemoryTourStorage()..markSeen([TourIds.point]),
      );
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('each step lights up the right thing', (tester) async {
      await openBoard(tester);
      final left = tester.getCenter(byKey('half-red'));
      final right = tester.getCenter(byKey('half-blue'));
      // 1: the left half, to tap
      expect(spot(tester).contains(left), isTrue);
      expect(spot(tester).contains(right), isFalse);
      expect(byKey('tour-hand'), findsOneWidget);
      await next(tester);
      // 2: the right half, to swipe down
      expect(title(tester), 'ปัดลงเพื่อลดแต้ม');
      expect(spot(tester).contains(right), isTrue);
      expect(spot(tester).contains(left), isFalse);
      expect(byKey('tour-hand'), findsOneWidget);
      await next(tester);
      // 3: the name on the left
      expect(title(tester), 'ชื่อทีม');
      expect(
        spot(tester).contains(tester.getCenter(byKey('name-red'))),
        isTrue,
      );
      expect(spot(tester).height, lessThan(120));
      await next(tester);
      // 4: the strip of buttons in the middle
      expect(title(tester), 'ปุ่มกลางจอ');
      for (final b in ['undo-button', 'swap-button', 'end-game-button']) {
        expect(spot(tester).contains(tester.getCenter(byKey(b))), isTrue);
      }
      expect(spot(tester).width, lessThan(100));
      // The buttons are named in the order they sit.
      expect(
        tester.widget<Text>(byKey('tour-body')).data,
        contains('เรียงจากบนลงล่าง'),
      );
      expect(byKey('tour-hand'), findsNothing);
      await next(tester);
      // 5: the serve button on the left
      expect(title(tester), 'เสิร์ฟ');
      expect(
        spot(tester).contains(tester.getCenter(byKey('serve-red'))),
        isTrue,
      );
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
    });

    testWidgets('follows the teams when the sides are swapped', (tester) async {
      await openBoard(
        tester,
        prepare: (c) => c.read(pointProvider.notifier).swapSides(),
      );
      // Blue is on the left now; the first step lights the left half.
      expect(
        spot(tester).contains(tester.getCenter(byKey('half-blue'))),
        isTrue,
      );
      await next(tester);
      expect(
        spot(tester).contains(tester.getCenter(byKey('half-red'))),
        isTrue,
      );
    });

    testWidgets('the card stays clear of what is lit', (tester) async {
      await openBoard(tester);
      for (var i = 0; i < 5; i++) {
        final card = tester.getRect(byKey('tour-card'));
        expect(spot(tester).overlaps(card), isFalse, reason: 'step $i');
        expect(card.width, lessThanOrEqualTo(800 * 0.4 + 1));
        if (i < 4) await next(tester);
      }
    });

    testWidgets('finishing remembers it', (tester) async {
      final tours = MemoryTourStorage();
      await openBoard(tester, tours: tours);
      for (var i = 0; i < 5; i++) {
        await next(tester);
      }
      expect(byKey('tour-card'), findsNothing);
      expect(tours.isSeen(TourIds.point), isTrue);
    });

    testWidgets('looking at it changes nothing in the game', (tester) async {
      final c = await openBoard(tester);
      await tester.tap(byKey('half-red'), warnIfMissed: false);
      await tester.tap(byKey('name-red'), warnIfMissed: false);
      await settle(tester);
      expect(byKey('rename-dialog'), findsNothing);
      expect(p.game(c).pointsOf(Side.red), 0);
      await tester.tap(byKey('tour-skip'));
      await settle(tester);
      expect(p.game(c).pointsOf(Side.red), 0);
    });

    testWidgets('the phone back button skips and keeps the game', (
      tester,
    ) async {
      final tours = MemoryTourStorage();
      await openBoard(tester, tours: tours);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(byKey('tour-card'), findsNothing);
      expect(byKey('leave-dialog'), findsNothing);
      expect(byKey('half-red'), findsOneWidget);
      expect(tours.isSeen(TourIds.point), isTrue);
    });

    testWidgets('waits for the sideways screen on a browser held upright', (
      tester,
    ) async {
      await openBoard(
        tester,
        needsManualRotation: true,
        size: const Size(400, 800),
      );
      expect(byKey('rotate-notice'), findsOneWidget);
      expect(byKey('tour-card'), findsNothing);
      tester.view.physicalSize = _sideways;
      await settle(tester);
      expect(byKey('rotate-notice'), findsNothing);
      expect(byKey('tour-card'), findsOneWidget);
      expect(title(tester), 'แตะเพื่อเพิ่มแต้ม');
    });

    testWidgets('waits for the sideways screen on a phone still turning', (
      tester,
    ) async {
      await openBoard(tester, size: const Size(400, 800));
      expect(byKey('tour-card'), findsNothing);
      tester.view.physicalSize = _sideways;
      await settle(tester);
      expect(byKey('tour-card'), findsOneWidget);
    });

    testWidgets('waits for the question about who serves first', (
      tester,
    ) async {
      await openBoard(
        tester,
        prepare: (c) {
          final notifier = c.read(pointProvider.notifier);
          notifier.addPoint(Side.red);
          notifier.finishRound();
        },
      );
      expect(byKey('next-round-dialog'), findsOneWidget);
      expect(byKey('tour-card'), findsNothing);
      await tester.tap(byKey('serve-first-red'));
      await settle(tester);
      expect(byKey('next-round-dialog'), findsNothing);
      expect(byKey('tour-card'), findsOneWidget);
    });

    testWidgets('works in the dark look', (tester) async {
      tester.view.physicalSize = _sideways;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = p.containerWith(
        overrides: [tourStorageProvider.overrideWithValue(MemoryTourStorage())],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: buildTheme(Brightness.dark),
            routerConfig: createRouter(initialLocation: '/point/play'),
          ),
        ),
      );
      await settle(tester);
      expect(byKey('tour-card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
