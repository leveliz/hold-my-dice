import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_overlay.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';

/// Three boxes on a plain page: one near the top, one in the middle, one near
/// the bottom, and a button under where the tour is drawn.
class Stage {
  final top = GlobalKey();
  final mid = GlobalKey();
  final bottom = GlobalKey();
  final missing = GlobalKey();
  final tall = GlobalKey();
  final tall2 = GlobalKey();
  final huge = GlobalKey();
  final small = GlobalKey();
  var pressed = 0;
}

class Run {
  Run(this.session);

  final TourSession session;
  TourOutcome? outcome;
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<Run> open(
  WidgetTester tester,
  Stage stage,
  List<TourStep> steps, {
  Size size = const Size(400, 800),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 20,
              top: 100,
              width: 360,
              height: 80,
              child: SizedBox(key: stage.top),
            ),
            Positioned(
              left: 20,
              top: 350,
              width: 360,
              height: 80,
              child: SizedBox(key: stage.mid),
            ),
            Positioned(
              left: 20,
              top: 690,
              width: 360,
              height: 70,
              child: SizedBox(key: stage.bottom),
            ),
            Positioned(
              left: 20,
              top: 20,
              width: 360,
              height: 400,
              child: SizedBox(key: stage.tall),
            ),
            Positioned(
              left: 20,
              top: 430,
              width: 360,
              height: 340,
              child: SizedBox(key: stage.tall2),
            ),
            Positioned(
              left: 260,
              top: 300,
              width: 80,
              height: 40,
              child: SizedBox(key: stage.small),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: 400,
              height: 800,
              child: SizedBox(key: stage.huge),
            ),
            Positioned(
              left: 20,
              top: 220,
              child: TextButton(
                onPressed: () => stage.pressed++,
                child: const Text('under'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  final session = showTour(tester.element(find.byType(Scaffold)), steps);
  final run = Run(session);
  session.result.then((o) => run.outcome = o);
  await settle(tester);
  return run;
}

List<TourStep> three(Stage s) => [
  TourStep(title: 'หนึ่ง', body: 'ข้อความหนึ่ง', target: s.top),
  TourStep(title: 'สอง', body: 'ข้อความสอง', target: s.mid),
  TourStep(title: 'สาม', body: 'ข้อความสาม', target: s.bottom),
];

String text(WidgetTester tester, String key) =>
    tester.widget<Text>(byKey(key)).data!;

dynamic hand(WidgetTester tester) =>
    tester.widget<CustomPaint>(byKey('tour-hand')).painter;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('stepping through', () {
    testWidgets('starts on the first step with the count and no back', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, three(s));
      expect(text(tester, 'tour-title'), 'หนึ่ง');
      expect(text(tester, 'tour-body'), 'ข้อความหนึ่ง');
      expect(text(tester, 'tour-step'), '1/3');
      expect(byKey('tour-back'), findsNothing);
      expect(find.text('ถัดไป'), findsOneWidget);
    });

    testWidgets('next goes on, back comes back', (tester) async {
      final s = Stage();
      await open(tester, s, three(s));
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      expect(text(tester, 'tour-title'), 'สอง');
      expect(text(tester, 'tour-step'), '2/3');
      expect(byKey('tour-back'), findsOneWidget);
      await tester.tap(byKey('tour-back'));
      await settle(tester);
      expect(text(tester, 'tour-title'), 'หนึ่ง');
      expect(text(tester, 'tour-step'), '1/3');
    });

    testWidgets('the last step says it is understood and finishes', (
      tester,
    ) async {
      final s = Stage();
      final run = await open(tester, s, three(s));
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      expect(text(tester, 'tour-step'), '3/3');
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
      expect(find.text('ถัดไป'), findsNothing);
      expect(run.outcome, isNull);
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      expect(run.outcome, TourOutcome.finished);
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('a step whose spot cannot be found is left out', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(title: 'หนึ่ง', body: 'ก', target: s.top),
        TourStep(title: 'หาย', body: 'ข', target: s.missing),
        TourStep(title: 'สาม', body: 'ค', target: s.bottom),
      ]);
      expect(text(tester, 'tour-step'), '1/2');
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      expect(text(tester, 'tour-title'), 'สาม');
      expect(text(tester, 'tour-step'), '2/2');
    });

    testWidgets('a tour with nothing to show closes without counting', (
      tester,
    ) async {
      final s = Stage();
      final run = await open(tester, s, [
        TourStep(title: 'หาย', body: 'ก', target: s.missing),
      ]);
      await settle(tester);
      expect(run.outcome, TourOutcome.closed);
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets(
      'a step that loses its spot when the window shrinks is dropped',
      (tester) async {
        final s = Stage();
        await open(tester, s, three(s));
        expect(text(tester, 'tour-step'), '1/3');
        tester.view.physicalSize = const Size(400, 300);
        await settle(tester);
        expect(text(tester, 'tour-step'), '1/1');
      },
    );
  });

  group('leaving', () {
    testWidgets('skip ends it from any step and counts as skipped', (
      tester,
    ) async {
      final s = Stage();
      final first = await open(tester, s, three(s));
      await tester.tap(byKey('tour-skip'));
      await settle(tester);
      expect(first.outcome, TourOutcome.skipped);
      expect(byKey('tour-card'), findsNothing);

      final t = Stage();
      final later = await open(tester, t, three(t));
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      await tester.tap(byKey('tour-skip'));
      await settle(tester);
      expect(later.outcome, TourOutcome.skipped);
    });

    testWidgets('the back button of the phone skips', (tester) async {
      final s = Stage();
      final run = await open(tester, s, three(s));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(run.outcome, TourOutcome.skipped);
      expect(byKey('tour-card'), findsNothing);
      // The page under it is still there.
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('closing from outside is not a skip', (tester) async {
      final s = Stage();
      final run = await open(tester, s, three(s));
      run.session.close();
      await settle(tester);
      expect(run.outcome, TourOutcome.closed);
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('closing twice does no harm', (tester) async {
      final s = Stage();
      final run = await open(tester, s, three(s));
      run.session.close();
      await settle(tester);
      run.session.close();
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('while it is open', () {
    testWidgets('a tap on the dark area does not reach the page', (
      tester,
    ) async {
      final s = Stage();
      final run = await open(tester, s, three(s));
      await tester.tap(find.text('under'), warnIfMissed: false);
      await settle(tester);
      expect(s.pressed, 0);
      expect(run.outcome, isNull);
      expect(byKey('tour-card'), findsOneWidget);
    });

    testWidgets('keys: Escape skips, arrows and Enter move', (tester) async {
      final s = Stage();
      final run = await open(tester, s, three(s));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(text(tester, 'tour-title'), 'สอง');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(text(tester, 'tour-title'), 'สาม');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(text(tester, 'tour-title'), 'สอง');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(run.outcome, TourOutcome.skipped);
    });

    testWidgets('the card is read out with its step', (tester) async {
      final handle = tester.ensureSemantics();
      final s = Stage();
      await open(tester, s, three(s));
      expect(
        find.bySemanticsLabel(RegExp('หนึ่ง.*ข้อความหนึ่ง.*ขั้น 1 จาก 3')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('what is lit and where the card goes', () {
    testWidgets('the spot is the target with a little room around it', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, three(s));
      expect(byKey('tour-spot-0'), findsOneWidget);
      expect(byKey('tour-spot-1'), findsNothing);
      expect(
        tester.getRect(byKey('tour-spot-0')),
        const Rect.fromLTWH(16, 96, 368, 88),
      );
    });

    testWidgets('the dark layer is cut out where the spots are', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(
          title: 'ลาก',
          body: 'ก',
          target: s.top,
          destination: s.bottom,
          gesture: TourGesture.drag,
        ),
      ]);
      final dim =
          tester.widget<CustomPaint>(byKey('tour-dim')).painter as dynamic;
      expect(dim.spots, [
        tester.getRect(find.byKey(s.top)),
        tester.getRect(find.byKey(s.bottom)),
      ]);
    });

    testWidgets('a spot near the top leaves the card at the bottom', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, three(s));
      final card = tester.getRect(byKey('tour-card'));
      expect(
        card.top,
        greaterThan(tester.getRect(byKey('tour-spot-0')).bottom),
      );
      expect(card.bottom, lessThanOrEqualTo(800));
    });

    testWidgets('a spot near the bottom moves the card to the top', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(title: 'ล่าง', body: 'ก', target: s.bottom),
      ]);
      final card = tester.getRect(byKey('tour-card'));
      expect(card.bottom, lessThan(tester.getRect(byKey('tour-spot-0')).top));
    });

    testWidgets('a drag lights both ends and the card fits between them', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(
          title: 'ลาก',
          body: 'ก',
          target: s.top,
          destination: s.bottom,
          gesture: TourGesture.drag,
        ),
      ]);
      final a = tester.getRect(byKey('tour-spot-0'));
      final b = tester.getRect(byKey('tour-spot-1'));
      final card = tester.getRect(byKey('tour-card'));
      expect(a.overlaps(card), isFalse);
      expect(b.overlaps(card), isFalse);
      expect(card.top, greaterThan(a.bottom));
      expect(card.bottom, lessThan(b.top));
      expect(byKey('tour-hand'), findsOneWidget);
    });

    testWidgets('with no room for the card a drag shows only where it ends', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(
          title: 'ลาก',
          body: 'ก',
          target: s.tall,
          destination: s.tall2,
          gesture: TourGesture.drag,
        ),
      ]);
      await settle(tester);
      expect(byKey('tour-spot-0'), findsOneWidget);
      expect(byKey('tour-spot-1'), findsNothing);
      expect(byKey('tour-hand'), findsNothing);
      final card = tester.getRect(byKey('tour-card'));
      final spot = tester.getRect(byKey('tour-spot-0'));
      expect(spot.top, tester.getRect(find.byKey(s.tall2)).top - 4);
      expect(card.overlaps(spot), isFalse);
    });

    testWidgets('the step after one without room has its hand back', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(
          title: 'ลาก',
          body: 'ก',
          target: s.tall,
          destination: s.tall2,
          gesture: TourGesture.drag,
        ),
        TourStep(
          title: 'ปัด',
          body: 'ข',
          target: s.top,
          gesture: TourGesture.swipeDown,
        ),
      ]);
      await settle(tester);
      expect(byKey('tour-hand'), findsNothing);
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      expect(text(tester, 'tour-title'), 'ปัด');
      expect(byKey('tour-hand'), findsOneWidget);
    });

    testWidgets('a spot that fills the screen still gets a readable card', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(title: 'ทั้งจอ', body: 'ก', target: s.huge),
      ]);
      final card = tester.getRect(byKey('tour-card'));
      expect(card.bottom, 800 - 12);
      final fade = find.ancestor(
        of: byKey('tour-card'),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(fade.first).opacity, 1);
    });

    testWidgets('a small spot gets a dashed outline', (tester) async {
      final s = Stage();
      await open(tester, s, three(s));
      expect(
        find.descendant(
          of: byKey('tour-spot-0'),
          matching: find.byType(DashedBorder),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a spot that fills much of the screen has none', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(title: 'ทั้งจอ', body: 'ก', target: s.huge),
      ]);
      expect(byKey('tour-spot-0'), findsOneWidget);
      expect(
        find.descendant(
          of: byKey('tour-spot-0'),
          matching: find.byType(DashedBorder),
        ),
        findsNothing,
      );
    });

    testWidgets('the buttons are big enough to tap with a thumb', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, three(s));
      await tester.tap(byKey('tour-next'));
      await settle(tester);
      for (final k in ['tour-skip', 'tour-back', 'tour-next']) {
        final size = tester.getSize(byKey(k));
        expect(size.height, greaterThanOrEqualTo(48), reason: k);
        expect(size.width, greaterThanOrEqualTo(64), reason: k);
      }
    });

    testWidgets('both looks draw it', (tester) async {
      for (final b in Brightness.values) {
        final s = Stage();
        await open(tester, s, three(s), brightness: b);
        expect(byKey('tour-card'), findsOneWidget, reason: '$b');
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('the hand', () {
    Future<void> openWith(
      WidgetTester tester,
      TourGesture gesture, {
      bool withDestination = false,
    }) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(
          title: 'ท่า',
          body: 'ก',
          target: s.top,
          gesture: gesture,
          destination: withDestination ? s.bottom : null,
        ),
      ]);
    }

    testWidgets('is there for a tap, a swipe and a drag', (tester) async {
      for (final g in [
        TourGesture.tap,
        TourGesture.swipeDown,
        TourGesture.drag,
      ]) {
        await openWith(tester, g, withDestination: g == TourGesture.drag);
        expect(byKey('tour-hand'), findsOneWidget, reason: '$g');
      }
    });

    testWidgets('is not there when the step has no gesture', (tester) async {
      await openWith(tester, TourGesture.none);
      expect(byKey('tour-hand'), findsNothing);
    });

    testWidgets('a drag with no end point shows no hand', (tester) async {
      await openWith(tester, TourGesture.drag);
      expect(byKey('tour-hand'), findsNothing);
    });

    testWidgets('touches the middle of a large spot', (tester) async {
      await openWith(tester, TourGesture.tap);
      final start = hand(tester).start as Offset;
      expect(start, const Offset(200, 140));
    });

    testWidgets('touches a corner of a small spot so it stays readable', (
      tester,
    ) async {
      final s = Stage();
      await open(tester, s, [
        TourStep(
          title: 'เล็ก',
          body: 'ก',
          target: s.small,
          gesture: TourGesture.tap,
        ),
      ]);
      // The small box is 80 x 40 at (260, 300).
      final start = hand(tester).start as Offset;
      expect(start.dx, greaterThan(260 + 40));
      expect(start.dx, lessThan(260 + 80));
      expect(start.dy, greaterThan(300 + 20));
      expect(start.dy, lessThan(300 + 40));
    });

    testWidgets('moves over time', (tester) async {
      await openWith(tester, TourGesture.swipeDown);
      expect(hand(tester).t, isNotNull);
      final before = hand(tester).t as double;
      await tester.pump(const Duration(milliseconds: 400));
      expect(hand(tester).t as double, isNot(before));
    });

    testWidgets('stands still when the phone asks for less motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openWith(tester, TourGesture.swipeDown);
      expect(byKey('tour-hand'), findsOneWidget);
      expect(hand(tester).t, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      expect(hand(tester).t, isNull);
      // Nothing keeps running, so the screen can settle.
      await tester.pumpAndSettle();
    });
  });
}
