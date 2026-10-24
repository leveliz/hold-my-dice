import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'bank_flow_test.dart' as f;

Finder byKey(String k) => f.byKey(k);

GameState gameOf(ProviderContainer c) => c.read(bankProvider)!.game;

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await settle(tester);
}

/// Long-press [from], drag it over [to] and release.
Future<void> dragTo(WidgetTester tester, Finder from, Finder to) async {
  final g = await tester.startGesture(tester.getCenter(from));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await g.moveTo(tester.getCenter(to));
  await tester.pump();
  await g.up();
  await settle(tester);
}

bool highlighted(WidgetTester tester, String id) {
  final box = tester.widget<DecoratedBox>(byKey('drop-zone-$id'));
  return (box.decoration as BoxDecoration).border != null;
}

/// p1 tries to pay [amount] to the bank with the "−" button.
Future<void> payBankFromP1(WidgetTester tester, List<String> keys) async {
  await tapKey(tester, 'btn-minus-p1');
  await f.typeKeys(tester, keys);
  await tapKey(tester, 'sheet-ok');
}

/// p1 transfers [keys] to p2 by tapping the card.
Future<void> transferP1ToP2(WidgetTester tester, List<String> keys) async {
  await tapKey(tester, 'player-card-p1');
  await tapKey(tester, 'recipient-p2');
  await f.typeKeys(tester, keys);
  await tapKey(tester, 'sheet-ok');
}

Future<void> addMortgage(WidgetTester tester, String amount) async {
  await tester.enterText(byKey('mortgage-input'), amount);
  await tester.pump();
  await tester.tap(byKey('mortgage-add'));
  await tester.pump();
}

/// The transfer header: "● from  [โอนให้ + icon]  ● to" on a single row.
void expectTransferHeader(
  WidgetTester tester, {
  required String from,
  required String to,
  String pairKey = 'transfer-pair',
}) {
  final pair = byKey(pairKey);
  expect(pair, findsOneWidget);
  Finder inPair(Finder f) => find.descendant(of: pair, matching: f);
  final fromFinder = inPair(find.text(from));
  final toFinder = inPair(find.text(to));
  final iconFinder = inPair(find.byIcon(LucideIcons.arrowRightLeft));
  expect(fromFinder, findsOneWidget);
  expect(toFinder, findsOneWidget);
  expect(iconFinder, findsOneWidget);
  expect(inPair(find.text('โอนให้')), findsOneWidget);
  expect(
    tester.getCenter(fromFinder).dy,
    closeTo(tester.getCenter(toFinder).dy, 1),
  );
  final iconX = tester.getCenter(iconFinder).dx;
  expect(tester.getCenter(fromFinder).dx, lessThan(iconX));
  expect(iconX, lessThan(tester.getCenter(toFinder).dx));
}

bool hasIcon(String buttonKey, IconData icon) => find
    .descendant(of: byKey(buttonKey), matching: find.byIcon(icon))
    .evaluate()
    .isNotEmpty;

String remainingText(WidgetTester tester) =>
    tester.widget<Text>(byKey('mortgage-remaining')).data!;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('transfer by tapping a card', () {
    testWidgets('lists the other players, not the payer', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'player-card-p1');
      expect(byKey('recipient-sheet'), findsOneWidget);
      expect(byKey('recipient-p2'), findsOneWidget);
      expect(byKey('recipient-p3'), findsOneWidget);
      expect(byKey('recipient-p1'), findsNothing);
    });

    testWidgets('does not offer a bankrupt player', (tester) async {
      final c = f.gameWith(3);
      c.read(bankProvider.notifier).pay('p3', 1500);
      c.read(bankProvider.notifier).declareBankrupt('p3', owed: 1);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'player-card-p1');
      expect(byKey('recipient-p2'), findsOneWidget);
      expect(byKey('recipient-p3'), findsNothing);
    });

    testWidgets('amount sheet names the recipient and has no mortgage', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'player-card-p1');
      await tapKey(tester, 'recipient-p2');
      expectTransferHeader(tester, from: 'ผู้เล่น 1', to: 'ผู้เล่น 2');
      expect(byKey('sheet-kind'), findsNothing);
      expect(f.chipText(tester, 'sheet-balance-chip'), '1,500');
    });

    testWidgets('confirming shows both balances', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await transferP1ToP2(tester, ['5', '0', '0']);
      expect(f.chipText(tester, 'result-balance-p1'), '1,000');
      expect(f.chipText(tester, 'result-balance-p2'), '2,000');
      expect(byKey('result-balance-p3'), findsNothing);
      await f.closeResult(tester);
      expect(f.balance(tester, 'p1'), '1,000');
      expect(f.balance(tester, 'p2'), '2,000');
      expect(find.text('โอน 500 ผู้เล่น 1 → ผู้เล่น 2'), findsOneWidget);
    });

    testWidgets('the transfer is one undo step', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await transferP1ToP2(tester, ['5', '0', '0']);
      await f.closeResult(tester);
      await tapKey(tester, 'undo-button');
      expect(gameOf(c).balanceOf('p1'), 1500);
      expect(gameOf(c).balanceOf('p2'), 1500);
    });
  });

  group('drag and drop', () {
    testWidgets('a player dropped on another opens a transfer', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await dragTo(tester, byKey('player-card-p1'), byKey('player-card-p2'));
      expectTransferHeader(tester, from: 'ผู้เล่น 1', to: 'ผู้เล่น 2');
    });

    testWidgets('the bank dropped on a player is a receive, no mortgage', (
      tester,
    ) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await dragTo(tester, byKey('bank-card'), byKey('player-card-p2'));
      expect(byKey('sheet-amount'), findsOneWidget);
      expect(byKey('sheet-kind'), findsNothing);
      await f.typeKeys(tester, ['1', '0', '0']);
      await tapKey(tester, 'sheet-ok');
      expect(f.chipText(tester, 'result-balance-p2'), '1,600');
      await f.closeResult(tester);
      expect(find.text('รับจากธนาคาร ผู้เล่น 2 +100'), findsOneWidget);
    });

    testWidgets('a player dropped on the bank is a payment', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await dragTo(tester, byKey('player-card-p3'), byKey('bank-card'));
      expect(find.text('จ่ายธนาคาร'), findsOneWidget);
      await f.typeKeys(tester, ['2', '0', '0']);
      await tapKey(tester, 'sheet-ok');
      expect(f.chipText(tester, 'result-balance-p3'), '1,300');
      await f.closeResult(tester);
    });

    testWidgets('valid targets are outlined only while dragging', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      expect(highlighted(tester, 'p2'), isFalse);

      final g = await tester.startGesture(
        tester.getCenter(byKey('player-card-p1')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(highlighted(tester, 'p2'), isTrue);
      expect(highlighted(tester, 'p3'), isTrue);
      expect(highlighted(tester, 'bank'), isTrue);
      // The dragged card is shown dimmed in place and is not a target.
      expect(byKey('drop-zone-p1'), findsNothing);

      await g.up();
      await settle(tester);
      expect(highlighted(tester, 'p2'), isFalse);
      expect(highlighted(tester, 'bank'), isFalse);
    });

    testWidgets('a bankrupt player cannot be dragged or dropped on', (
      tester,
    ) async {
      final c = f.gameWith(3);
      c.read(bankProvider.notifier).pay('p3', 1500);
      c.read(bankProvider.notifier).declareBankrupt('p3', owed: 1);
      await f.pumpAt(tester, '/bank/play', container: c);
      expect(byKey('bankrupt-p3'), findsOneWidget);
      expect(byKey('drop-zone-p3'), findsNothing);

      // Dragging p1 never highlights the bankrupt p3.
      final g = await tester.startGesture(
        tester.getCenter(byKey('player-card-p1')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(highlighted(tester, 'p2'), isTrue);
      expect(byKey('drop-zone-p3'), findsNothing);
      await g.up();
      await settle(tester);
    });
  });

  group('not enough money', () {
    testWidgets('paying the bank shows what is owed and the shortfall', (
      tester,
    ) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await payBankFromP1(tester, ['2', '000']);
      expect(find.text('ต้องจ่าย 2,000 ให้ธนาคาร'), findsOneWidget);
      expect(f.chipText(tester, 'shortfall-cash'), '1,500');
      expect(f.chipText(tester, 'shortfall-amount'), '500');
      expect(gameOf(c).history, isEmpty);
    });

    testWidgets('the live total decides when payment is possible', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await payBankFromP1(tester, ['2', '000']);
      expect(remainingText(tester), 'ยังขาดอีก 500');
      expect(
        tester.widget<FilledButton>(byKey('mortgage-confirm')).onPressed,
        isNull,
      );

      await addMortgage(tester, '200');
      expect(remainingText(tester), 'ยังขาดอีก 300');
      expect(find.text('แปลงที่ 1'), findsOneWidget);

      await addMortgage(tester, '300');
      expect(remainingText(tester), 'พอจ่ายแล้ว');
      expect(
        tester.widget<FilledButton>(byKey('mortgage-confirm')).onPressed,
        isNotNull,
      );

      await tester.tap(byKey('mortgage-remove-0'));
      await tester.pump();
      expect(remainingText(tester), 'ยังขาดอีก 200');
      expect(find.text('แปลงที่ 2'), findsNothing);
    });

    testWidgets('mortgage amounts show thousands separators', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await payBankFromP1(tester, ['2', '000']);
      await tester.enterText(byKey('mortgage-input'), '1200');
      await tester.pump();
      expect(
        tester.widget<TextField>(byKey('mortgage-input')).controller!.text,
        '1,200',
      );
      await tester.tap(byKey('mortgage-add'));
      await tester.pump();
      expect(tester.widget<Text>(byKey('mortgage-amount-0')).data, '+1,200');
    });

    testWidgets('mortgage and pay is saved as one undoable step', (
      tester,
    ) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await payBankFromP1(tester, ['2', '000']);
      await addMortgage(tester, '200');
      await addMortgage(tester, '300');
      await tapKey(tester, 'mortgage-confirm');

      expect(byKey('result-sheet'), findsOneWidget);
      expect(f.chipText(tester, 'result-balance-p1'), '0');
      await f.closeResult(tester);
      expect(gameOf(c).history.length, 1);

      await tapKey(tester, 'undo-button');
      expect(gameOf(c).balanceOf('p1'), 1500);
      expect(gameOf(c).history, isEmpty);
    });

    testWidgets('a transfer short of money pays the player after mortgage', (
      tester,
    ) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await transferP1ToP2(tester, ['2', '000']);
      expect(find.text('ต้องจ่าย 2,000 ให้ผู้เล่น 2'), findsOneWidget);
      await addMortgage(tester, '500');
      await tapKey(tester, 'mortgage-confirm');
      expect(f.chipText(tester, 'result-balance-p1'), '0');
      expect(f.chipText(tester, 'result-balance-p2'), '3,500');
      await f.closeResult(tester);
    });

    testWidgets('going back changes nothing', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await payBankFromP1(tester, ['2', '000']);
      await addMortgage(tester, '100');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(byKey('shortfall-summary'), findsNothing);
      expect(byKey('player-card-p1'), findsOneWidget);
      expect(gameOf(c).history, isEmpty);
    });

    testWidgets('bankrupt to the bank returns the cash to the bank', (
      tester,
    ) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await payBankFromP1(tester, ['2', '000']);
      await tapKey(tester, 'bankrupt-button');
      expect(
        find.text('ออกจากเกม เงินที่เหลือ 1,500 คืนธนาคาร'),
        findsOneWidget,
      );
      await tapKey(tester, 'bankrupt-confirm');

      expect(byKey('result-sheet'), findsNothing);
      expect(byKey('bankrupt-p1'), findsOneWidget);
      expect(gameOf(c).isBankrupt('p1'), isTrue);
      expect(gameOf(c).balanceOf('p1'), 0);
      expect(gameOf(c).balanceOf('p2'), 1500);
    });

    testWidgets('bankrupt to a player pays them in full', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await transferP1ToP2(tester, ['2', '000']);
      await tapKey(tester, 'bankrupt-button');
      expect(
        find.text('ออกจากเกม ผู้เล่น 2 ได้รับ 2,000 ครบ ธนาคารจ่ายส่วนต่าง'),
        findsOneWidget,
      );
      await tapKey(tester, 'bankrupt-confirm');

      expect(byKey('result-sheet'), findsOneWidget);
      expect(f.chipText(tester, 'result-balance-p2'), '3,500');
      // Once in the sheet title and once in the undo bar behind it.
      expect(find.text('ผู้เล่น 1 ล้มละลาย'), findsWidgets);
      await f.closeResult(tester);
      expect(byKey('bankrupt-p1'), findsOneWidget);
    });

    testWidgets('cancelling the bankruptcy stays on the page', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await payBankFromP1(tester, ['2', '000']);
      await tapKey(tester, 'bankrupt-button');
      await tapKey(tester, 'bankrupt-cancel');
      expect(byKey('shortfall-summary'), findsOneWidget);
      expect(gameOf(c).isBankrupt('p1'), isFalse);
    });

    testWidgets('the last player standing ends the game', (tester) async {
      final c = f.gameWith(2);
      await f.pumpAt(tester, '/bank/play', container: c);
      await payBankFromP1(tester, ['2', '000']);
      await tapKey(tester, 'bankrupt-button');
      await tapKey(tester, 'bankrupt-confirm');
      expect(find.text('ผู้ชนะคือ ผู้เล่น 2'), findsOneWidget);
      expect(byKey('rank-p2'), findsOneWidget);
    });

    testWidgets('bankruptcy can be undone from the undo bar', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await payBankFromP1(tester, ['2', '000']);
      await tapKey(tester, 'bankrupt-button');
      await tapKey(tester, 'bankrupt-confirm');
      expect(find.text('ผู้เล่น 1 ล้มละลาย'), findsOneWidget);
      await tapKey(tester, 'undo-button');
      expect(gameOf(c).isBankrupt('p1'), isFalse);
      expect(gameOf(c).balanceOf('p1'), 1500);
    });
  });

  group('history', () {
    testWidgets('is empty before any transaction', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'history-button');
      expect(byKey('history-empty'), findsOneWidget);
      expect(find.text('ยังไม่มีรายการ'), findsOneWidget);
    });

    testWidgets('lists transactions newest first with notes', (tester) async {
      final c = f.gameWith(3);
      final n = c.read(bankProvider.notifier);
      n.passGo('p1');
      n.payWithMortgage(
        payerId: 'p2',
        payeeId: 'p3',
        amount: 1800,
        mortgages: [200, 150],
      );
      n.receive('p3', 100);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'history-button');

      String title(int i) =>
          tester.widget<Text>(byKey('history-title-$i')).data!;
      expect(title(0), 'รับจากธนาคาร ผู้เล่น 3 +100');
      expect(title(1), 'โอน 1,800 ผู้เล่น 2 → ผู้เล่น 3');
      expect(title(2), 'ผ่านจุดเริ่ม ผู้เล่น 1 +200');
      expect(
        tester.widget<Text>(byKey('history-subtitle-1')).data,
        'จำนอง +200 +150',
      );
      expect(byKey('history-subtitle-0'), findsNothing);
    });

    testWidgets('undone transactions are gone', (tester) async {
      final c = f.gameWith(3);
      c.read(bankProvider.notifier).passGo('p1');
      c.read(bankProvider.notifier).undo();
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'history-button');
      expect(byKey('history-empty'), findsOneWidget);
    });

    testWidgets('going back returns to the game', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'history-button');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(byKey('player-card-p1'), findsOneWidget);
    });
  });

  group('ending the game', () {
    testWidgets('asks first and staying keeps playing', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'end-game-button');
      expect(byKey('end-dialog'), findsOneWidget);
      await tapKey(tester, 'end-stay');
      expect(byKey('end-dialog'), findsNothing);
      expect(byKey('player-card-p1'), findsOneWidget);
    });

    testWidgets('ranks by money with bankrupt players last', (tester) async {
      final c = f.gameWith(4);
      final n = c.read(bankProvider.notifier);
      n.receive('p3', 1000);
      n.receive('p2', 300);
      n.pay('p4', 1500);
      n.declareBankrupt('p4', owed: 1);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');

      expect(find.text('จบเกมแล้ว เรียงตามเงินที่เหลือ'), findsOneWidget);
      double top(String id) => tester.getTopLeft(byKey('rank-$id')).dy;
      expect(top('p3'), lessThan(top('p2')));
      expect(top('p2'), lessThan(top('p1')));
      expect(top('p1'), lessThan(top('p4')));
      expect(f.chipText(tester, 'rank-balance-p3'), '2,500');
      expect(byKey('rank-out-p4'), findsOneWidget);
      expect(byKey('rank-balance-p4'), findsNothing);
      expect(tester.widget<Text>(byKey('rank-number-p2')).data, '2');
    });

    testWidgets('play again clears the game and opens the setup', (
      tester,
    ) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      await tapKey(tester, 'play-again');
      expect(find.text('ตั้งค่าเกม'), findsOneWidget);
      expect(c.read(bankProvider), isNull);
    });

    testWidgets('back to hub clears the game', (tester) async {
      final c = f.gameWith(3);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      await tapKey(tester, 'back-to-hub');
      expect(find.text('Hold My Dice'), findsOneWidget);
      expect(c.read(bankProvider), isNull);
    });
  });

  group('transfer header layout', () {
    testWidgets('"โอนเงิน" is on the left, on its own line above the names', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'player-card-p1');
      await tapKey(tester, 'recipient-p2');
      final title = byKey('sheet-transfer-title');
      expect(find.text('โอนเงิน'), findsOneWidget);
      expect(tester.getTopLeft(title).dx, lessThan(60));
      expect(
        tester.getBottomLeft(title).dy,
        lessThanOrEqualTo(tester.getTopLeft(byKey('transfer-pair')).dy),
      );
    });

    testWidgets('the pair of names is centred under the title', (tester) async {
      // Short names, so the pair is clearly narrower than the sheet.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(bankProvider.notifier)
          .start(
            players: const [
              Player(id: 'p1', name: 'A', color: 0xFF3D5AFE),
              Player(id: 'p2', name: 'B', color: 0xFF2E9E57),
            ],
            startingCash: 1500,
            goAmount: 200,
          );
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'player-card-p1');
      await tapKey(tester, 'recipient-p2');

      Finder inPair(String name) => find.descendant(
        of: byKey('transfer-pair'),
        matching: find.text(name),
      );
      // Content spans from the first dot (14 + 8 before the name) to the end
      // of the second name; its midpoint is the middle of the sheet.
      final left = tester.getTopLeft(inPair('A')).dx - 22;
      final right = tester.getTopRight(inPair('B')).dx;
      final middle = tester.getCenter(byKey('transfer-pair')).dx;
      expect(right - left, lessThan(300));
      expect((left + right) / 2, closeTo(middle, 4));
      // The title stays on the left.
      expect(tester.getTopLeft(byKey('sheet-transfer-title')).dx, lessThan(60));
    });

    testWidgets('the "โอนให้" caption is smaller and grey', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'player-card-p1');
      await tapKey(tester, 'recipient-p2');
      Text textIn(String value) => tester.widget<Text>(
        find.descendant(of: byKey('transfer-pair'), matching: find.text(value)),
      );
      final caption = textIn('โอนให้').style!;
      final name = textIn('ผู้เล่น 1').style!;
      expect(caption.fontSize!, lessThan(name.fontSize!));
      expect(caption.color!.a, lessThan(1));
    });

    testWidgets('a payment to the bank keeps the plain header', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'btn-minus-p1');
      expect(byKey('transfer-pair'), findsNothing);
      expect(find.text('จ่ายธนาคาร'), findsOneWidget);
    });

    testWidgets('the result sheet shows the pair and the amount sent', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await transferP1ToP2(tester, ['1', '0', '0']);
      expectTransferHeader(
        tester,
        from: 'ผู้เล่น 1',
        to: 'ผู้เล่น 2',
        pairKey: 'result-transfer',
      );
      expect(
        tester.widget<Text>(byKey('result-transfer-amount')).data,
        'ยอดโอน 100',
      );
      // Order: pair, transfer amount, "ยอดคงเหลือ", then the balances.
      final pairY = tester.getTopLeft(byKey('result-transfer')).dy;
      final amountY = tester.getTopLeft(byKey('result-transfer-amount')).dy;
      final labelY = tester.getTopLeft(find.text('ยอดคงเหลือ')).dy;
      final chipY = tester.getTopLeft(byKey('result-balance-p1')).dy;
      expect(pairY, lessThan(amountY));
      expect(amountY, lessThan(labelY));
      expect(labelY, lessThan(chipY));
      // The one-line summary is not repeated inside the sheet.
      expect(
        find.descendant(
          of: byKey('result-sheet'),
          matching: find.text('โอน 100 ผู้เล่น 1 → ผู้เล่น 2'),
        ),
        findsNothing,
      );
      await f.closeResult(tester);
    });

    testWidgets('a transfer paid after mortgaging uses the same header', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await transferP1ToP2(tester, ['2', '000']);
      await addMortgage(tester, '500');
      await tapKey(tester, 'mortgage-confirm');
      expectTransferHeader(
        tester,
        from: 'ผู้เล่น 1',
        to: 'ผู้เล่น 2',
        pairKey: 'result-transfer',
      );
      expect(
        tester.widget<Text>(byKey('result-transfer-amount')).data,
        'ยอดโอน 2,000',
      );
    });

    testWidgets('other results keep the one-line title', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'btn-plus-p2');
      await f.typeKeys(tester, ['1', '0', '0']);
      await tapKey(tester, 'sheet-ok');
      expect(byKey('result-transfer'), findsNothing);
      expect(
        find.descendant(
          of: byKey('result-sheet'),
          matching: find.text('รับจากธนาคาร ผู้เล่น 2 +100'),
        ),
        findsOneWidget,
      );
    });
  });

  group('amount sheet header for the bank', () {
    // Short names, so a left-aligned and a right-aligned player differ clearly.
    ProviderContainer shortNames() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(bankProvider.notifier)
          .start(
            players: const [
              Player(id: 'p1', name: 'A', color: 0xFF3D5AFE),
              Player(id: 'p2', name: 'B', color: 0xFF2E9E57),
            ],
            startingCash: 1500,
            goAmount: 200,
          );
      return c;
    }

    Future<void> expectLabelLeftNameRight(
      WidgetTester tester,
      String buttonKey,
      String label,
    ) async {
      await tapKey(tester, buttonKey);
      final labelFinder = byKey('sheet-kind-label');
      expect(tester.widget<Text>(labelFinder).data, label);
      final name = find.descendant(
        of: byKey('sheet-player'),
        matching: find.text('A'),
      );
      expect(name, findsOneWidget);
      // The label sits at the left edge and the player at the right edge.
      expect(tester.getTopLeft(labelFinder).dx, lessThan(60));
      expect(tester.getTopRight(name).dx, greaterThan(340));
      expect(
        tester.getTopLeft(labelFinder).dx,
        lessThan(tester.getTopLeft(name).dx),
      );
    }

    testWidgets('paying the bank: "จ่ายธนาคาร" left, player right', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: shortNames());
      await expectLabelLeftNameRight(tester, 'btn-minus-p1', 'จ่ายธนาคาร');
    });

    testWidgets('receiving: "รับเงิน" left, player right', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: shortNames());
      await expectLabelLeftNameRight(tester, 'btn-plus-p1', 'รับเงิน');
    });

    testWidgets('a long player name is shortened, not pushed off', (
      tester,
    ) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(bankProvider.notifier)
          .start(
            players: const [
              Player(
                id: 'p1',
                name: 'ผู้เล่นที่มีชื่อยาวมากๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆ',
                color: 0xFF3D5AFE,
              ),
              Player(id: 'p2', name: 'B', color: 0xFF2E9E57),
            ],
            startingCash: 1500,
            goAmount: 200,
          );
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'btn-plus-p1');
      expect(tester.takeException(), isNull);
      expect(find.text('รับเงิน'), findsOneWidget);
    });
  });

  group('button icons', () {
    testWidgets('amount sheet: confirm, recent amounts and kinds', (
      tester,
    ) async {
      final c = f.gameWith(3);
      c.read(bankProvider.notifier).receive('p1', 100);
      await f.pumpAt(tester, '/bank/play', container: c);
      await tapKey(tester, 'btn-plus-p1');
      expect(hasIcon('sheet-ok', LucideIcons.check), isTrue);
      expect(hasIcon('recent-100', LucideIcons.history), isTrue);
      expect(
        find.descendant(
          of: byKey('sheet-kind'),
          matching: find.byIcon(LucideIcons.landmark),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byKey('sheet-kind'),
          matching: find.byIcon(LucideIcons.handCoins),
        ),
        findsOneWidget,
      );
    });

    testWidgets('result sheet close button', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'btn-plus-p1');
      await f.typeKeys(tester, ['5']);
      await tapKey(tester, 'sheet-ok');
      expect(hasIcon('result-close', LucideIcons.x), isTrue);
    });

    testWidgets('setup start button', (tester) async {
      await f.pumpAt(tester, '/bank');
      expect(hasIcon('start-game', LucideIcons.play), isTrue);
    });

    testWidgets('shortfall page buttons and dialog', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await payBankFromP1(tester, ['2', '000']);
      expect(hasIcon('mortgage-add', LucideIcons.plus), isTrue);
      expect(hasIcon('mortgage-confirm', LucideIcons.handCoins), isTrue);
      expect(hasIcon('bankrupt-button', LucideIcons.logOut), isTrue);
      await tapKey(tester, 'bankrupt-button');
      expect(hasIcon('bankrupt-cancel', LucideIcons.x), isTrue);
      expect(hasIcon('bankrupt-confirm', LucideIcons.logOut), isTrue);
    });

    testWidgets('game dialogs', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(hasIcon('leave-stay', LucideIcons.play), isTrue);
      expect(hasIcon('leave-confirm', LucideIcons.logOut), isTrue);
      await tapKey(tester, 'leave-stay');
      await tapKey(tester, 'end-game-button');
      expect(hasIcon('end-stay', LucideIcons.play), isTrue);
      expect(hasIcon('end-confirm', LucideIcons.flag), isTrue);
    });

    testWidgets('summary buttons', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'end-game-button');
      await tapKey(tester, 'end-confirm');
      expect(hasIcon('play-again', LucideIcons.rotateCcw), isTrue);
      expect(hasIcon('back-to-hub', LucideIcons.house), isTrue);
    });

    testWidgets('the dashed add-player slot stays icon-free', (tester) async {
      await f.pumpAt(tester, '/bank');
      expect(find.byIcon(LucideIcons.userPlus), findsNothing);
      expect(find.text('+ เพิ่มผู้เล่น'), findsOneWidget);
    });
  });
}
