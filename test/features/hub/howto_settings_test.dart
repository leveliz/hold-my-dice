import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';

Finder byKey(String k) => find.byKey(ValueKey(k));

/// The tour's hand never stops moving, so the page cannot "settle".
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A storage where every tour and tip has been seen.
TourStorage allSeen() => MemoryTourStorage()
  ..markSeen([TourIds.bank, ...TourIds.bankTips, TourIds.score, TourIds.point]);

Future<ProviderContainer> openSettings(
  WidgetTester tester,
  TourStorage tours, {
  Brightness brightness = Brightness.light,
}) async {
  final c = ProviderContainer(
    overrides: [tourStorageProvider.overrideWithValue(tours)],
  );
  addTearDown(c.dispose);
  c
      .read(bankProvider.notifier)
      .start(
        players: const [
          Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
          Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
        ],
        startingCash: 1500,
        goAmount: 200,
      );
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: buildTheme(brightness),
        routerConfig: createRouter(initialLocation: '/settings'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('lists the three helpers under "วิธีใช้"', (tester) async {
    await openSettings(tester, allSeen());
    expect(byKey('howto-card'), findsOneWidget);
    expect(find.text('วิธีใช้'), findsOneWidget);
    for (final name in ['Pocket Banker', 'Score Snitch', 'Point Blank']) {
      expect(
        find.descendant(of: byKey('howto-card'), matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
    expect(find.text('ดูอีกครั้ง'), findsNWidgets(3));
  });

  testWidgets('sits under the look card and is in both looks', (tester) async {
    for (final b in Brightness.values) {
      await openSettings(tester, allSeen(), brightness: b);
      expect(
        tester.getTopLeft(byKey('howto-card')).dy,
        greaterThan(tester.getBottomLeft(byKey('theme-mode')).dy),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('"ดูอีกครั้ง" brings back that helper, with its tips only', (
    tester,
  ) async {
    final tours = allSeen();
    await openSettings(tester, tours);
    await tester.tap(byKey('howto-bank'));
    await tester.pump();
    expect(tours.isSeen(TourIds.bank), isFalse);
    for (final tip in TourIds.bankTips) {
      expect(tours.isSeen(tip), isFalse, reason: tip);
    }
    expect(tours.isSeen(TourIds.score), isTrue);
    expect(tours.isSeen(TourIds.point), isTrue);
  });

  testWidgets('each row brings back its own helper', (tester) async {
    final tours = allSeen();
    await openSettings(tester, tours);
    await tester.tap(byKey('howto-point'));
    await tester.pump();
    expect(tours.isSeen(TourIds.point), isFalse);
    expect(tours.isSeen(TourIds.bank), isTrue);
    expect(tours.isSeen(TourIds.score), isTrue);
    await tester.tap(byKey('howto-score'));
    await tester.pump();
    expect(tours.isSeen(TourIds.score), isFalse);
  });

  testWidgets('says when it will show, naming the helper', (tester) async {
    await openSettings(tester, allSeen());
    await tester.tap(byKey('howto-score'));
    await tester.pump();
    expect(
      find.text('จะแนะนำ Score Snitch อีกครั้งตอนเข้าหน้าเล่นถัดไป'),
      findsOneWidget,
    );
    await tester.tap(byKey('howto-point'));
    await tester.pump();
    expect(
      find.text('จะแนะนำ Point Blank อีกครั้งตอนเข้าหน้าเล่นถัดไป'),
      findsOneWidget,
    );
    expect(
      find.text('จะแนะนำ Score Snitch อีกครั้งตอนเข้าหน้าเล่นถัดไป'),
      findsNothing,
    );
  });

  testWidgets('pressing it for a tour never seen does no harm', (tester) async {
    final tours = MemoryTourStorage();
    await openSettings(tester, tours);
    await tester.tap(byKey('howto-bank'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tours.isSeen(TourIds.bank), isFalse);
  });

  testWidgets('the tour then shows when the play screen opens', (tester) async {
    final tours = allSeen();
    await openSettings(tester, tours);
    await tester.tap(byKey('howto-bank'));
    await tester.pump();
    GoRouter.of(tester.element(byKey('howto-card'))).go('/bank/play');
    await settle(tester);
    expect(byKey('tour-card'), findsOneWidget);
    expect(tester.widget<Text>(byKey('tour-title')).data, 'เงินของแต่ละคน');
  });

  testWidgets('a helper not asked for stays quiet', (tester) async {
    final tours = allSeen();
    await openSettings(tester, tours);
    await tester.tap(byKey('howto-score'));
    await tester.pump();
    GoRouter.of(tester.element(byKey('howto-card'))).go('/bank/play');
    await settle(tester);
    expect(byKey('tour-card'), findsNothing);
  });
}
