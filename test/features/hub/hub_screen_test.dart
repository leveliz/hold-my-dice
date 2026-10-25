import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/app.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('every helper has a unique id and a route', () {
    final ids = helpers.map((h) => h.id).toSet();
    expect(ids.length, helpers.length);
    expect(helpers.every((h) => h.route.startsWith('/')), isTrue);
  });

  testWidgets('hub shows a square card for each helper', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HoldMyDiceApp()));
    await tester.pumpAndSettle();

    for (final h in helpers) {
      expect(find.text(h.name), findsOneWidget);
      final size = tester.getSize(find.byKey(ValueKey('helper-${h.id}')));
      expect(size.width, size.height);
    }
  });

  group('on screens of different widths', () {
    Future<void> openHubAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: buildTheme(Brightness.light),
            routerConfig: createRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    double top(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(ValueKey('helper-$id'))).dy;

    testWidgets('a phone shows two cards in a row', (tester) async {
      await openHubAt(tester, const Size(400, 800));
      expect(top(tester, 'bank'), top(tester, 'score'));
      expect(top(tester, 'point'), greaterThan(top(tester, 'bank')));
    });

    testWidgets('a wide window fits more cards in a row', (tester) async {
      await openHubAt(tester, const Size(1100, 800));
      expect(top(tester, 'bank'), top(tester, 'score'));
      expect(top(tester, 'bank'), top(tester, 'point'));
    });

    testWidgets('cards stay square and the window does not overflow', (
      tester,
    ) async {
      await openHubAt(tester, const Size(1100, 800));
      for (final h in helpers) {
        final size = tester.getSize(find.byKey(ValueKey('helper-${h.id}')));
        expect(size.width, size.height);
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('tapping a card opens that helper', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HoldMyDiceApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('helper-bank')));
    await tester.pumpAndSettle();

    expect(find.text('ตั้งค่าเกม'), findsOneWidget);
    expect(find.byKey(const ValueKey('helper-bank')), findsNothing);
  });

  testWidgets('Score Snitch has a card that opens its page', (tester) async {
    // A router of its own: the shared one keeps the page an earlier test left.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: createRouter(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Score Snitch'), findsOneWidget);
    expect(find.text('นับคะแนนรายรอบ'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('helper-score')));
    await tester.pumpAndSettle();
    expect(find.text('ตั้งค่าเกม'), findsOneWidget);
    expect(find.byKey(const ValueKey('rounds')), findsOneWidget);
  });
}
