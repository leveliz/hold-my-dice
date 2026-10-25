import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';

import 'bank_flow_test.dart' as f;

Finder byKey(String k) => f.byKey(k);

/// The tour's hand never stops moving, so the page cannot "settle".
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ProviderContainer> openBank(
  WidgetTester tester, {
  int players = 3,
  TourStorage? tours,
  Size size = const Size(400, 800),
  void Function(ProviderContainer c)? prepare,
}) async {
  final c = f.gameWith(
    players,
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
        routerConfig: createRouter(initialLocation: '/bank/play'),
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

Rect spot(WidgetTester tester, int i) => tester.getRect(byKey('tour-spot-$i'));

Future<void> next(WidgetTester tester) async {
  await tester.tap(byKey('tour-next'));
  await settle(tester);
}

/// A storage where the tour itself is seen but both tips still wait.
TourStorage tourSeen() => MemoryTourStorage()..markSeen([TourIds.bank]);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the tour of Pocket Banker', () {
    testWidgets('opens on the first play screen, six steps', (tester) async {
      await openBank(tester);
      expect(byKey('tour-card'), findsOneWidget);
      expect(title(tester), 'เงินของแต่ละคน');
      expect(count(tester), '1/6');
    });

    testWidgets('does not open for someone who has seen it', (tester) async {
      await openBank(tester, tours: tourSeen());
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('each step lights up the right thing', (tester) async {
      await openBank(tester);
      final card1 = tester.getRect(byKey('player-card-p1'));
      final card2 = tester.getRect(byKey('player-card-p2'));
      // 1: the first card
      expect(spot(tester, 0).contains(card1.center), isTrue);
      expect(spot(tester, 0).height, lessThan(card1.height + 20));
      await next(tester);
      // 2: the row of + − GO on that card
      expect(title(tester), 'ปุ่มรับ จ่าย และ GO');
      for (final b in ['plus', 'minus', 'go']) {
        expect(
          spot(tester, 0).contains(tester.getCenter(byKey('btn-$b-p1'))),
          isTrue,
          reason: b,
        );
      }
      expect(spot(tester, 0).height, lessThan(card1.height));
      await next(tester);
      // 3: the card itself, to tap
      expect(title(tester), 'โอนให้ผู้เล่น');
      expect(spot(tester, 0).contains(card1.center), isTrue);
      await next(tester);
      // 4: from the first card to the second
      expect(title(tester), 'ลากไปวางเพื่อโอน');
      expect(spot(tester, 0).contains(card1.center), isTrue);
      expect(spot(tester, 1).contains(card2.center), isTrue);
      await next(tester);
      // 5: from the first card to the bank
      expect(title(tester), 'ลากไปวางที่ธนาคาร');
      expect(spot(tester, 0).contains(card1.center), isTrue);
      expect(
        spot(tester, 1).contains(tester.getCenter(byKey('bank-card'))),
        isTrue,
      );
      await next(tester);
      // 6: the three icons on the bar
      expect(title(tester), 'ปุ่มบนแถบหัว');
      for (final b in [
        'hide-balances-button',
        'history-button',
        'end-game-button',
      ]) {
        expect(spot(tester, 0).contains(tester.getCenter(byKey(b))), isTrue);
      }
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
      // The icons are named in the order they sit.
      expect(
        tester.widget<Text>(byKey('tour-body')).data,
        contains('เรียงจากซ้ายไปขวา'),
      );
    });

    testWidgets('the card never covers what a step lights up', (tester) async {
      await openBank(tester);
      for (var i = 0; i < 6; i++) {
        final card = tester.getRect(byKey('tour-card'));
        for (var s = 0; byKey('tour-spot-$s').evaluate().isNotEmpty; s++) {
          expect(spot(tester, s).overlaps(card), isFalse, reason: 'step $i');
        }
        if (i < 5) await next(tester);
      }
    });

    testWidgets('finishing remembers it; the tips are still to come', (
      tester,
    ) async {
      final tours = MemoryTourStorage();
      await openBank(tester, tours: tours);
      for (var i = 0; i < 6; i++) {
        await next(tester);
      }
      expect(byKey('tour-card'), findsNothing);
      expect(tours.isSeen(TourIds.bank), isTrue);
      expect(tours.isSeen(TourIds.bankMoneyTip), isFalse);
      expect(tours.isSeen(TourIds.bankUndoTip), isFalse);
    });

    testWidgets('skipping remembers it and drops the tips', (tester) async {
      final tours = MemoryTourStorage();
      await openBank(tester, tours: tours);
      await tester.tap(byKey('tour-skip'));
      await settle(tester);
      expect(tours.isSeen(TourIds.bank), isTrue);
      expect(tours.isSeen(TourIds.bankMoneyTip), isTrue);
      expect(tours.isSeen(TourIds.bankUndoTip), isTrue);
    });

    testWidgets('the phone back button skips and leaves the game alone', (
      tester,
    ) async {
      final tours = MemoryTourStorage();
      await openBank(tester, tours: tours);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(byKey('tour-card'), findsNothing);
      expect(byKey('leave-dialog'), findsNothing);
      expect(byKey('player-card-p1'), findsOneWidget);
      expect(tours.isSeen(TourIds.bank), isTrue);
    });

    testWidgets('looking at it changes nothing in the game', (tester) async {
      final c = await openBank(tester);
      // A tap on the card that is lit up does not start a transfer.
      await tester.tap(byKey('player-card-p1'), warnIfMissed: false);
      await tester.tap(byKey('btn-plus-p1'), warnIfMissed: false);
      await settle(tester);
      expect(byKey('sheet-amount'), findsNothing);
      for (var i = 0; i < 6; i++) {
        await next(tester);
      }
      final game = c.read(bankProvider)!.game;
      expect(game.balanceOf('p1'), 1500);
      expect(game.history, isEmpty);
    });

    testWidgets('starts from the first player still in the game', (
      tester,
    ) async {
      await openBank(
        tester,
        prepare: (c) {
          c.read(bankProvider.notifier).pay('p1', 1500);
          c.read(bankProvider.notifier).declareBankrupt('p1', owed: 1);
        },
      );
      expect(byKey('bankrupt-p1'), findsOneWidget);
      final card2 = tester.getRect(byKey('player-card-p2'));
      expect(spot(tester, 0).contains(card2.center), isTrue);
      await next(tester);
      await next(tester);
      await next(tester);
      // The drag runs from p2 to p3.
      expect(title(tester), 'ลากไปวางเพื่อโอน');
      expect(
        spot(tester, 1).contains(tester.getCenter(byKey('player-card-p3'))),
        isTrue,
      );
    });

    testWidgets('works with a crowded table of compact rows', (tester) async {
      await openBank(tester, players: 8);
      expect(count(tester), '1/6');
      for (final b in ['plus', 'minus', 'go']) {
        await next(tester);
        if (title(tester) == 'ปุ่มรับ จ่าย และ GO') {
          expect(
            spot(tester, 0).contains(tester.getCenter(byKey('btn-$b-p1'))),
            isTrue,
          );
          break;
        }
      }
      for (var i = 0; i < 4; i++) {
        await next(tester);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('works on a wide window with two columns', (tester) async {
      await openBank(tester, players: 4, size: const Size(1100, 800));
      await next(tester);
      await next(tester);
      await next(tester);
      expect(title(tester), 'ลากไปวางเพื่อโอน');
      expect(
        spot(tester, 1).contains(tester.getCenter(byKey('player-card-p2'))),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('works in the dark look', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = f.gameWith(
        3,
        overrides: [tourStorageProvider.overrideWithValue(MemoryTourStorage())],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: buildTheme(Brightness.dark),
            routerConfig: createRouter(initialLocation: '/bank/play'),
          ),
        ),
      );
      await settle(tester);
      expect(byKey('tour-card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the tips of Pocket Banker', () {
    Future<void> typeAmount(WidgetTester tester) async {
      await tester.tap(byKey('key-1'));
      await tester.tap(byKey('key-000'));
      await tester.pump();
    }

    testWidgets('the amount sheet explains 000 the first time only', (
      tester,
    ) async {
      final tours = tourSeen();
      await openBank(tester, tours: tours);
      await tester.tap(byKey('btn-plus-p1'));
      await settle(tester);
      expect(title(tester), 'ใส่เงินให้เร็วขึ้น');
      expect(
        spot(tester, 0).contains(tester.getCenter(byKey('key-000'))),
        isTrue,
      );
      // No amount used yet, so only 000 is lit.
      expect(byKey('tour-spot-1'), findsNothing);
      await next(tester);
      expect(title(tester), 'จำนอง');
      expect(
        spot(tester, 0).contains(tester.getCenter(byKey('sheet-kind'))),
        isTrue,
      );
      await next(tester);
      expect(byKey('tour-card'), findsNothing);
      expect(tours.isSeen(TourIds.bankMoneyTip), isTrue);

      // Close the sheet and open it again: no tip.
      await tester.tapAt(const Offset(200, 20));
      await settle(tester);
      await tester.tap(byKey('btn-plus-p1'));
      await settle(tester);
      expect(byKey('sheet-amount'), findsOneWidget);
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('with an amount used before, the tip lights the recent row', (
      tester,
    ) async {
      await openBank(
        tester,
        tours: tourSeen(),
        prepare: (c) => c.read(bankProvider.notifier).receive('p2', 500),
      );
      await tester.tap(byKey('btn-plus-p1'));
      await settle(tester);
      expect(byKey('tour-spot-1'), findsOneWidget);
      expect(
        spot(tester, 1).contains(tester.getCenter(byKey('recent-500'))),
        isTrue,
      );
    });

    testWidgets('a transfer opens the same tip, without the mortgage step', (
      tester,
    ) async {
      await openBank(tester, tours: tourSeen());
      await tester.tap(byKey('player-card-p1'));
      await settle(tester);
      await tester.tap(byKey('recipient-p2'));
      await settle(tester);
      expect(title(tester), 'ใส่เงินให้เร็วขึ้น');
      expect(count(tester), '1/1');
    });

    testWidgets('paying has no mortgage step', (tester) async {
      await openBank(tester, tours: tourSeen());
      await tester.tap(byKey('btn-minus-p1'));
      await settle(tester);
      expect(title(tester), 'ใส่เงินให้เร็วขึ้น');
      expect(count(tester), '1/1');
    });

    testWidgets('the tip is gone for someone who skipped the tour', (
      tester,
    ) async {
      final tours = MemoryTourStorage();
      await openBank(tester, tours: tours);
      await tester.tap(byKey('tour-skip'));
      await settle(tester);
      await tester.tap(byKey('btn-plus-p1'));
      await settle(tester);
      expect(byKey('sheet-amount'), findsOneWidget);
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('undo is explained when its bar first shows up', (
      tester,
    ) async {
      final tours = tourSeen()..markSeen([TourIds.bankMoneyTip]);
      await openBank(tester, tours: tours);
      expect(byKey('tour-card'), findsNothing);
      await tester.tap(byKey('btn-go-p1'));
      await settle(tester);
      expect(byKey('undo-bar'), findsOneWidget);
      expect(title(tester), 'เลิกทำ');
      expect(
        spot(tester, 0).contains(tester.getCenter(byKey('undo-bar'))),
        isTrue,
      );
      await next(tester);
      expect(tours.isSeen(TourIds.bankUndoTip), isTrue);

      // The next move does not bring it back.
      await tester.tap(byKey('btn-go-p2'));
      await settle(tester);
      expect(byKey('tour-card'), findsNothing);
    });

    testWidgets('the undo tip waits for the result sheet to close', (
      tester,
    ) async {
      final tours = tourSeen()..markSeen([TourIds.bankMoneyTip]);
      await openBank(tester, tours: tours);
      await tester.tap(byKey('btn-plus-p1'));
      await settle(tester);
      await typeAmount(tester);
      await tester.tap(byKey('sheet-ok'));
      await settle(tester);
      expect(byKey('result-sheet'), findsOneWidget);
      expect(byKey('tour-card'), findsNothing);
      await tester.tap(byKey('result-close'));
      await settle(tester);
      expect(title(tester), 'เลิกทำ');
    });
  });
}
