import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/application/requests_control.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart'
    show historyWindow;
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';
import 'package:hold_my_dice/features/room/presentation/room_game_screen.dart';

import 'room_test_app.dart';

const _owner = 'owner';
final _t0 = DateTime.utc(2026, 10, 26, 12);

/// A repository whose payment of a request waits until it is told to go on.
class _HoldPay extends FakeRoomRepository {
  _HoldPay(super.store, super.auth, this.gate);

  final Completer<void> gate;

  @override
  Future<void> payRequest(
    String code,
    String id, {
    required String cid,
    int? mortgage,
  }) async {
    await gate.future;
    return super.payRequest(code, id, cid: cid, mortgage: mortgage);
  }
}

/// A repository whose taking back waits until it is told to go on.
class _HoldUndo extends FakeRoomRepository {
  _HoldUndo(super.store, super.auth, this.gate);

  final Completer<void> gate;

  @override
  Future<void> undoEntry(String code, int seq) async {
    await gate.future;
    return super.undoEntry(code, seq);
  }
}

/// A requests controller that shows what it is told to.
class _StubRequests extends RequestsController {
  _StubRequests(this.shown) : super('K7M2QX');

  final RequestsState shown;

  @override
  RequestsState build() => shown;
}

PendingRequest _pending({Duration left = const Duration(minutes: 1)}) =>
    PendingRequest(
      const RoomRequest(
        id: 'p2_p1',
        fromSeat: 'p1',
        toSeat: 'p2',
        amount: 300,
        status: RequestStatus.open,
      ),
      DateTime.now().add(left),
    );

void main() {
  late DateTime clock;
  late FakeRoomStore store;
  late String code;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    clock = _t0;
    store = FakeRoomStore(now: () => clock);
    code = await makeRoom(store);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await repoOn(store, _owner).startGame(code);
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// Lets the rest after a press pass.
  Future<void> rest(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  Future<void> typeAmount(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(key('key-$d'));
    }
    await tester.pump();
  }

  String balance(WidgetTester tester) =>
      tester.widget<Text>(key('my-balance')).data!;

  bool enabled(WidgetTester tester, String k) =>
      tester.widget<ButtonStyleButton>(key(k)).onPressed != null;

  group('the sheet for not enough money', () {
    Future<void> payBankSheet(WidgetTester tester, String digits) async {
      await tester.tap(key('press-pay'));
      await tester.pumpAndSettle();
      await typeAmount(tester, digits);
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
    }

    Future<void> mortgage(WidgetTester tester, String value) async {
      await tester.enterText(key('mortgage-input'), value);
      await tester.pump();
      await tester.tap(key('mortgage-add'));
      await tester.pump();
    }

    String status(WidgetTester tester) =>
        tester.widget<Text>(key('mortgage-total')).data!;

    testWidgets(
      'tells what is missing, and pays only when the mortgage is enough',
      (tester) async {
        await openApp(tester, store, '/room/$code', uid: _owner);
        await payBankSheet(tester, '2000');
        expect(find.text('ขาด 500'), findsOneWidget);
        expect(find.text('เหลือหลังจ่ายได้ไม่เกิน 300'), findsOneWidget);
        expect(find.text('จ่ายธนาคาร 2,000 · มีอยู่ 1,500'), findsOneWidget);
        expect(enabled(tester, 'mortgage-confirm'), isFalse);
        expect(status(tester), contains('ยังขาดอีก 500'));
        await mortgage(tester, '499');
        expect(status(tester), 'รวมจำนอง 499 · ยังขาดอีก 1');
        expect(enabled(tester, 'mortgage-confirm'), isFalse);
        await tester.tap(key('mortgage-remove-0'));
        await tester.pump();
        await mortgage(tester, '200');
        expect(status(tester), 'รวมจำนอง 200 · ยังขาดอีก 300');
        expect(enabled(tester, 'mortgage-confirm'), isFalse);
        await mortgage(tester, '300');
        expect(status(tester), 'รวมจำนอง 500 · พอจ่ายแล้ว เหลือ 0');
        expect(enabled(tester, 'mortgage-confirm'), isTrue);
        await tester.tap(key('mortgage-remove-0'));
        await tester.pump();
        expect(enabled(tester, 'mortgage-confirm'), isFalse);
        await leave(tester);
      },
    );

    testWidgets(
      'a mortgage that leaves more than a fifth of the start is refused',
      (tester) async {
        await openApp(tester, store, '/room/$code', uid: _owner);
        await payBankSheet(tester, '2000');
        await mortgage(tester, '800');
        expect(status(tester), 'รวมจำนอง 800 · พอจ่ายแล้ว เหลือ 300');
        expect(
          enabled(tester, 'mortgage-confirm'),
          isTrue,
          reason: 'exactly 300',
        );
        await mortgage(tester, '1');
        expect(status(tester), contains('จำนองเกินไป'));
        expect(enabled(tester, 'mortgage-confirm'), isFalse);
        await leave(tester);
      },
    );

    testWidgets('paying exactly what they hold needs no sheet', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await payBankSheet(tester, '1500');
      expect(key('shortfall-sheet'), findsNothing);
      expect(balance(tester), '0');
      await rest(tester);
      await leave(tester);
    });

    testWidgets('a bank that holds less than the mortgage stops the payment', (
      tester,
    ) async {
      final small = await makeRoom(
        store,
        settings: const RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          maxPlayers: 4,
          bankLimit: 100,
        ),
      );
      await repoOn(
        store,
        'u2',
      ).joinAsPlayer(code: small, name: 'แพร', color: 0xFFE11D48);
      await repoOn(store, _owner).startGame(small);
      await openApp(tester, store, '/room/$small', uid: _owner);
      await payBankSheet(tester, '1700');
      await mortgage(tester, '200');
      expect(status(tester), 'รวมจำนอง 200 · ธนาคารมีเงินไม่พอให้จำนองยอดนี้');
      expect(enabled(tester, 'mortgage-confirm'), isFalse);
      await leave(tester);
    });

    testWidgets('pays the bank in one press and the history says so', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await payBankSheet(tester, '2000');
      await mortgage(tester, '600');
      await tester.tap(key('mortgage-confirm'));
      await tester.pumpAndSettle();
      expect(key('shortfall-sheet'), findsNothing);
      expect(balance(tester), '100');
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'จ่ายธนาคาร ต้น -2,000 · จำนอง 600',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('pays a friend in full from a transfer with a mortgage', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-give'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '2000');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      await mortgage(tester, '500');
      await tester.tap(key('mortgage-confirm'));
      await tester.pumpAndSettle();
      expect(balance(tester), '0');
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('3,500')),
        findsOneWidget,
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('money that arrives meanwhile makes the mortgage unnecessary', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await payBankSheet(tester, '1600');
      await mortgage(tester, '100');
      await repoOn(
        store,
        'u2',
      ).submitEntry(code, EntryDraft.transfer('p1', 200));
      await tester.pumpAndSettle();
      expect(status(tester), 'ตอนนี้เงินพอจ่ายแล้ว ไม่ต้องจำนอง');
      expect(key('mortgage-input'), findsNothing);
      expect(enabled(tester, 'bankrupt-button'), isFalse);
      await tester.tap(key('mortgage-confirm'));
      await tester.pumpAndSettle();
      expect(balance(tester), '100');
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'จ่ายธนาคาร ต้น -1,600',
        reason: 'no mortgage was written',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('going bankrupt asks first; backing out writes nothing', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await payBankSheet(tester, '2000');
      await tester.tap(key('bankrupt-button'));
      await tester.pumpAndSettle();
      expect(key('bankrupt-dialog'), findsOneWidget);
      await tester.tap(key('bankrupt-cancel'));
      await tester.pumpAndSettle();
      expect(key('shortfall-sheet'), findsOneWidget);
      expect(balance(tester), '1,500');
      expect(find.text('ยังไม่มีรายการ'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('going bankrupt puts the person out, owing the bank', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await payBankSheet(tester, '2000');
      await tester.tap(key('bankrupt-button'));
      await tester.pumpAndSettle();
      await tester.tap(key('bankrupt-confirm'));
      await tester.pumpAndSettle();
      expect(balance(tester), '0');
      expect(key('band-banker'), findsOneWidget);
      expect(
        key('press-pay'),
        findsNothing,
        reason: 'the banker has no seat to press for',
      );
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'ล้มละลาย ต้น · หนี้ 2,000 ให้ธนาคาร',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('going bankrupt owing a friend pays the friend in full', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-give'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '2000');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      await tester.tap(key('bankrupt-button'));
      await tester.pumpAndSettle();
      expect(find.textContaining('แพร ได้รับ 2,000 ครบ'), findsOneWidget);
      expect(find.textContaining('ต้องจ่าย 2,000 · มี 1,500'), findsOneWidget);
      expect(find.textContaining('ดูเกมต่อได้'), findsOneWidget);
      await tester.tap(key('bankrupt-confirm'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('3,500')),
        findsOneWidget,
      );
      expect(key('band-banker'), findsOneWidget);
      await rest(tester);
      await leave(tester);
    });

    testWidgets(
      'a debt over ten times the starting cash cannot be bankrupted',
      (tester) async {
        await openApp(tester, store, '/room/$code', uid: _owner);
        await payBankSheet(tester, '999999999');
        expect(enabled(tester, 'bankrupt-button'), isFalse);
        expect(key('bankrupt-too-big'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets('fits a narrow screen with a long name and many mortgages', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      await payBankSheet(tester, '999999999');
      for (var i = 0; i < 6; i++) {
        await mortgage(tester, '100');
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(key('mortgage-confirm'), findsOneWidget);
      await leave(tester);
    });
  });

  group('the banker', () {
    // p2 (u2, แพร) goes out first and is the banker; p1 (owner, ต้น) plays on.
    Future<void> banked() =>
        repoOn(store, 'u2').submitEntry(code, EntryDraft.bankrupt(2000));

    testWidgets(
      'a player has no bank buttons: the banner says the banker presses them',
      (tester) async {
        await banked();
        await openApp(tester, store, '/room/$code', uid: _owner);
        for (final k in ['press-pay', 'press-go', 'press-receive']) {
          expect(key(k), findsNothing, reason: k);
        }
        expect(
          find.textContaining(
            'นายธนาคาร แพร เป็นคนกดรับเงิน จ่ายธนาคาร และ GO ให้คุณ',
          ),
          findsOneWidget,
        );
        expect(key('band-banker-presses'), findsOneWidget);
        expect(key('banker-pass'), findsNothing);
        expect(key('banker-receive-p2'), findsNothing);
        await leave(tester);
      },
    );

    testWidgets(
      'the banker who is out sees who they are and has no buttons of their own',
      (tester) async {
        await banked();
        await openApp(tester, store, '/room/$code', uid: 'u2');
        expect(key('band-banker'), findsOneWidget);
        expect(
          find.textContaining(
            'คุณออกจากเกมแล้ว กดรับ จ่าย และ GO ให้เพื่อนได้',
          ),
          findsOneWidget,
        );
        expect(key('band-out'), findsNothing);
        expect(key('press-pay'), findsNothing);
        expect(key('banker-pass'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets(
      'each friend in the game has a receive, a pay and a GO button',
      (tester) async {
        await banked();
        await openApp(tester, store, '/room/$code', uid: 'u2');
        for (final k in [
          'banker-receive-p1',
          'banker-pay-p1',
          'banker-go-p1',
        ]) {
          expect(key(k), findsOneWidget, reason: k);
        }
        expect(
          key('banker-go-p2'),
          findsNothing,
          reason: 'nothing for a seat that is out',
        );
        await leave(tester);
      },
    );

    testWidgets(
      'GO for a friend: their balance, the history and the bar to take it back',
      (tester) async {
        await banked();
        await openApp(tester, store, '/room/$code', uid: 'u2');
        await tester.tap(key('banker-go-p1'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: key('friend-p1'), matching: find.text('1,700')),
          findsOneWidget,
        );
        expect(
          tester.widget<Text>(key('history-latest')).data,
          'ผ่านจุดเริ่ม ต้น +200 · โดยนายธนาคาร แพร',
        );
        expect(key('undo-bar'), findsOneWidget);
        expect(find.text('GO ให้ต้น +200 แล้ว'), findsOneWidget);
        for (final k in [
          'banker-receive-p1',
          'banker-pay-p1',
          'banker-go-p1',
        ]) {
          expect(key(k), findsOneWidget, reason: '$k stays in its place');
          expect(enabled(tester, k), isFalse, reason: '$k rests after a press');
        }
        await tester.tap(key('undo-button'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: key('friend-p1'), matching: find.text('1,500')),
          findsOneWidget,
        );
        await rest(tester);
        await leave(tester);
      },
    );

    testWidgets('receive for a friend asks for no reason', (tester) async {
      await banked();
      await openApp(tester, store, '/room/$code', uid: 'u2');
      await tester.tap(key('banker-receive-p1'));
      await tester.pumpAndSettle();
      expect(key('sheet-reason'), findsNothing);
      await typeAmount(tester, '300');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: key('friend-p1'), matching: find.text('1,800')),
        findsOneWidget,
      );
      expect(find.text('รับเงิน 300 ให้ต้นแล้ว'), findsOneWidget);
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'รับจากธนาคาร ต้น +300 · โดยนายธนาคาร แพร',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('pay for a friend takes the money from them', (tester) async {
      await banked();
      await openApp(tester, store, '/room/$code', uid: 'u2');
      await tester.tap(key('banker-pay-p1'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '500');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: key('friend-p1'), matching: find.text('1,000')),
        findsOneWidget,
      );
      expect(find.text('จ่ายธนาคาร 500 จากต้นแล้ว'), findsOneWidget);
      await rest(tester);
      await leave(tester);
    });

    testWidgets('paying exactly what a friend holds needs no sheet', (
      tester,
    ) async {
      await banked();
      await openApp(tester, store, '/room/$code', uid: 'u2');
      await tester.tap(key('banker-pay-p1'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '1500');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(key('shortfall-sheet'), findsNothing);
      expect(
        find.descendant(of: key('friend-p1'), matching: find.text('0')),
        findsOneWidget,
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets(
      'a banker who is out cannot give from a seat they do not have',
      (tester) async {
        await banked();
        await openApp(tester, store, '/room/$code', uid: 'u2');
        await tester.tap(
          find.descendant(of: key('friend-p1'), matching: find.text('ต้น')),
        );
        await tester.pumpAndSettle();
        expect(key('friend-action-give'), findsNothing);
        await leave(tester);
      },
    );

    testWidgets('a watcher is not told who the banker is', (tester) async {
      await banked();
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      await openApp(tester, store, '/room/$code', uid: 's1');
      expect(key('band-spectator'), findsOneWidget);
      expect(key('band-banker-presses'), findsNothing);
      expect(key('banker-takeover'), findsNothing);
      await leave(tester);
    });

    testWidgets(
      'a payment a friend cannot cover opens the sheet about them, with a mortgage',
      (tester) async {
        await banked();
        await openApp(tester, store, '/room/$code', uid: 'u2');
        await tester.tap(key('banker-pay-p1'));
        await tester.pumpAndSettle();
        await typeAmount(tester, '2000');
        await tester.tap(key('sheet-ok'));
        await tester.pumpAndSettle();
        expect(
          find.text('ต้น จ่ายธนาคาร 2,000 · มีอยู่ 1,500'),
          findsOneWidget,
        );
        await tester.enterText(key('mortgage-input'), '600');
        await tester.pump();
        await tester.tap(key('mortgage-add'));
        await tester.pump();
        await tester.tap(key('mortgage-confirm'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: key('friend-p1'), matching: find.text('100')),
          findsOneWidget,
        );
        await rest(tester);
        await leave(tester);
      },
    );

    testWidgets('and the banker can declare that friend bankrupt', (
      tester,
    ) async {
      await banked();
      await openApp(tester, store, '/room/$code', uid: 'u2');
      await tester.tap(key('banker-pay-p1'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '2000');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      await tester.tap(key('bankrupt-button'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ต้องจ่าย 2,000 · มี 1,500'), findsOneWidget);
      await tester.tap(key('bankrupt-confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text('ออกจากเกม'),
        findsOneWidget,
        reason: 'the friend; my own seat is no row',
      );
      expect(key('banker-go-p1'), findsNothing);
      await rest(tester);
      await leave(tester);
    });

    testWidgets(
      'the banker hands the seat to a friend, who gets the banker\'s bar',
      (tester) async {
        await banked();
        await openApp(tester, store, '/room/$code', uid: 'u2');
        await tester.tap(key('banker-pass'));
        await tester.pumpAndSettle();
        await tester.tap(key('banker-pass-p1'));
        await tester.pumpAndSettle();
        expect(key('band-banker'), findsNothing);
        expect(key('band-banker-presses'), findsOneWidget);
        await leave(tester);
        await openApp(tester, store, '/room/$code', uid: _owner);
        expect(key('band-banker'), findsOneWidget);
        expect(find.textContaining('คุณเป็นนายธนาคาร'), findsOneWidget);
        expect(
          key('press-pay'),
          findsOneWidget,
          reason: 'a banker who still plays has their own buttons',
        );
        expect(key('banker-go-p2'), findsNothing);
        await leave(tester);
      },
    );

    testWidgets(
      'a player is always offered the banker seat, and the room says if it is too soon',
      (tester) async {
        await banked();
        await openApp(
          tester,
          store,
          '/room/$code',
          uid: _owner,
          overrides: [roomClockProvider.overrideWithValue(() => clock)],
        );
        expect(key('banker-takeover'), findsOneWidget);
        await tester.tap(key('banker-takeover'));
        await tester.pumpAndSettle();
        expect(snackText(tester), 'นายธนาคารยังออนไลน์อยู่');
        await leave(tester);
      },
    );

    testWidgets(
      'taking it over is refused in words while the banker is there',
      (tester) async {
        await banked();
        clock = clock.add(const Duration(minutes: 3));
        await repoOn(store, 'u2').heartbeat(code);
        await openApp(
          tester,
          store,
          '/room/$code',
          uid: _owner,
          overrides: [roomClockProvider.overrideWithValue(() => clock)],
        );
        await tester.tap(key('banker-takeover'));
        await tester.pumpAndSettle();
        expect(snackText(tester), 'นายธนาคารยังออนไลน์อยู่');
        expect(key('band-banker-presses'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets(
      'a banker who is gone is replaced by the one who takes the seat',
      (tester) async {
        await banked();
        clock = clock.add(const Duration(minutes: 3));
        await openApp(
          tester,
          store,
          '/room/$code',
          uid: _owner,
          overrides: [roomClockProvider.overrideWithValue(() => clock)],
        );
        await tester.tap(key('banker-takeover'));
        await tester.pumpAndSettle();
        expect(key('band-banker'), findsOneWidget);
        expect(key('press-pay'), findsOneWidget);
        expect(key('banker-takeover'), findsNothing);
        await leave(tester);
      },
    );

    testWidgets('a friend of the banker is told what the banker did for them', (
      tester,
    ) async {
      await banked();
      await openApp(tester, store, '/room/$code', uid: _owner);
      await repoOn(
        store,
        'u2',
      ).submitEntry(code, EntryDraft.passGo().onBehalfOf('p1'));
      await tester.pumpAndSettle();
      expect(snackText(tester), 'นายธนาคาร แพร กด GO ให้คุณ +200');
      expect(balance(tester), '1,700');
      await rest(tester);
      await leave(tester);
    });
  });

  group('the not-enough-money sheet when there is a banker', () {
    // Three players; p3 went out first and is the banker.
    Future<String> threeWithBanker() async {
      final room = await makeRoom(store);
      for (final u in ['u2', 'u3']) {
        await repoOn(store, u).joinAsPlayer(code: room, name: u, color: 1);
      }
      await repoOn(store, _owner).startGame(room);
      await repoOn(store, 'u3').submitEntry(room, EntryDraft.bankrupt(2000));
      return room;
    }

    Future<void> payFriend(WidgetTester tester, String digits) async {
      await tester.tap(
        find.descendant(of: key('friend-p2'), matching: find.text('u2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-give'));
      await tester.pumpAndSettle();
      await typeAmount(tester, digits);
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a player cannot mortgage: the sheet says to ask the banker, or go bankrupt',
      (tester) async {
        final room = await threeWithBanker();
        await openApp(tester, store, '/room/$room', uid: _owner);
        await payFriend(tester, '2000');
        expect(key('shortfall-sheet'), findsOneWidget);
        expect(key('mortgage-input'), findsNothing);
        expect(key('mortgage-blocked'), findsOneWidget);
        expect(enabled(tester, 'mortgage-confirm'), isFalse);
        expect(enabled(tester, 'bankrupt-button'), isTrue);
        await leave(tester);
      },
    );

    testWidgets('a banker who still plays can mortgage for their own payment', (
      tester,
    ) async {
      final room = await threeWithBanker();
      await repoOn(store, 'u3').passBanker(room, 'p1');
      await openApp(tester, store, '/room/$room', uid: _owner);
      await payFriend(tester, '2000');
      expect(key('mortgage-input'), findsOneWidget);
      expect(key('mortgage-blocked'), findsNothing);
      await leave(tester);
    });

    testWidgets(
      'money that arrives meanwhile makes the payment possible again',
      (tester) async {
        final room = await threeWithBanker();
        await openApp(tester, store, '/room/$room', uid: _owner);
        await payFriend(tester, '2000');
        expect(key('mortgage-blocked'), findsOneWidget);
        await repoOn(
          store,
          'u2',
        ).submitEntry(room, EntryDraft.transfer('p1', 600));
        await tester.pumpAndSettle();
        expect(key('mortgage-blocked'), findsNothing);
        expect(
          tester.widget<Text>(key('mortgage-total')).data,
          'ตอนนี้เงินพอจ่ายแล้ว ไม่ต้องจำนอง',
        );
        expect(enabled(tester, 'mortgage-confirm'), isTrue);
        await leave(tester);
      },
    );

    testWidgets('the same when a request is paid', (tester) async {
      final room = await threeWithBanker();
      await repoOn(
        store,
        'u2',
      ).requestMoney(room, fromSeat: 'p1', amount: 2000);
      await openApp(tester, store, '/room/$room', uid: _owner);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(key('request-pay'));
      await tester.pumpAndSettle();
      expect(key('mortgage-blocked'), findsOneWidget);
      expect(key('mortgage-input'), findsNothing);
      await leave(tester);
    });
  });

  group('a player', () {
    testWidgets('sees their balance, the others and a quiet history', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      expect(balance(tester), '1,500');
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('แพร')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('1,500')),
        findsOneWidget,
      );
      expect(key('friend-p1'), findsNothing, reason: 'I am not my own friend');
      expect(find.text('ยังไม่มีรายการ'), findsOneWidget);
      for (final k in ['press-pay', 'press-go', 'press-receive']) {
        expect(enabled(tester, k), isTrue, reason: k);
      }
      expect(key('band-spectator'), findsNothing);
      await leave(tester);
    });

    testWidgets('GO adds the room\'s GO amount at once', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-go'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,700');
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('1,500')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'ผ่านจุดเริ่ม ต้น +200',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('a double tap on GO is one press', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-go'));
      await tester.tap(key('press-go'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(balance(tester), '1,700');
      await rest(tester);
      await leave(tester);
    });

    testWidgets('receiving needs a reason; a chip gives one', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-receive'));
      await tester.pumpAndSettle();
      expect(key('sheet-kind'), findsNothing, reason: 'no mortgage in a room');
      await typeAmount(tester, '300');
      expect(enabled(tester, 'sheet-ok'), isFalse);
      await tester.tap(key('reason-chip-ค่าเช่า'));
      await tester.pump();
      expect(enabled(tester, 'sheet-ok'), isTrue);
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,800');
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'รับจากธนาคาร ต้น +300 · ค่าเช่า',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('a reason stops at 60 characters, not at the 20 of a name', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-receive'));
      await tester.pumpAndSettle();
      await tester.enterText(key('sheet-reason'), 'ก' * 70);
      await tester.pump();
      expect(
        tester.widget<TextField>(key('sheet-reason')).controller!.text,
        'ก' * 60,
      );
    });

    testWidgets('paying the bank asks for no reason', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-pay'));
      await tester.pumpAndSettle();
      expect(key('sheet-reason'), findsNothing);
      await typeAmount(tester, '500');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,000');
      await rest(tester);
      await leave(tester);
    });

    testWidgets('paying more than they hold opens the not-enough sheet', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-pay'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '2000');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(key('shortfall-sheet'), findsOneWidget);
      expect(balance(tester), '1,500');
      expect(find.text('ยังไม่มีรายการ'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('the largest amount fits on the screen', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-receive'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '999999999');
      await tester.tap(key('reason-chip-ภาษี'));
      await tester.pump();
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,000,001,499');
      expect(tester.takeException(), isNull);
      await rest(tester);
      await leave(tester);
    });

    testWidgets('sees what a friend does as it happens', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await repoOn(store, 'u2').submitEntry(code, EntryDraft.passGo());
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('1,700')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'ผ่านจุดเริ่ม แพร +200',
      );
      expect(balance(tester), '1,500');
      await leave(tester);
    });

    testWidgets('loses the buttons offline and gets them back', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      expect(find.text('สด'), findsOneWidget);
      store.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.text('สด'), findsNothing);
      expect(key('band-offline'), findsOneWidget);
      for (final k in ['press-pay', 'press-go', 'press-receive']) {
        expect(enabled(tester, k), isFalse, reason: k);
      }
      store.setOnline(true);
      await tester.pumpAndSettle();
      expect(key('band-offline'), findsNothing);
      expect(enabled(tester, 'press-go'), isTrue);
      await leave(tester);
    });

    testWidgets(
      'the buttons keep their labels on one line on a narrow screen',
      (tester) async {
        await openApp(tester, store, '/room/$code', uid: _owner);
        tester.view.physicalSize = const Size(300, 900);
        await tester.pumpAndSettle();
        for (final label in ['จ่ายธนาคาร', 'GO', 'รับเงิน']) {
          final height = tester.getSize(find.text(label)).height;
          expect(height, lessThan(30), reason: label);
        }
        await leave(tester);
      },
    );

    testWidgets('a sheet confirmed after the signal was lost sends nothing', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-pay'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '500');
      store.setOnline(false);
      await tester.pump();
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      store.setOnline(true);
      await tester.pumpAndSettle();
      expect(balance(tester), '1,500');
      expect(find.text('ยังไม่มีรายการ'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('falls back to the join form when the seat is taken over', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: 'u2');
      expect(key('room-playing'), findsOneWidget);
      clock = clock.add(const Duration(minutes: 3));
      await repoOn(store, 'u9').claimSeat(code: code, seatId: 'p2');
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(key('room-playing'), findsNothing);
      expect(key('join-name'), findsOneWidget);
      await leave(tester);
    });
  });

  group('the history', () {
    testWidgets('opens in full, newest first, with reason and age', (
      tester,
    ) async {
      await openApp(
        tester,
        store,
        '/room/$code',
        uid: _owner,
        overrides: [roomClockProvider.overrideWithValue(() => clock)],
      );
      await tester.tap(key('press-go'));
      await tester.pumpAndSettle();
      await rest(tester);
      clock = clock.add(const Duration(minutes: 3));
      await repoOn(store, 'u2').submitEntry(code, EntryDraft.payBank(120));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'จ่ายธนาคาร แพร -120',
        reason: 'the strip shows the newest line',
      );
      await tester.tap(key('history-strip'));
      await tester.pumpAndSettle();
      expect(find.text('ประวัติทั้งหมด'), findsOneWidget);
      expect(
        find.descendant(
          of: key('history-row-0'),
          matching: find.text('ผ่านจุดเริ่ม ต้น'),
        ),
        findsOneWidget,
        reason: 'the amount is shown once, on its own',
      );
      final newer = tester.getTopLeft(key('history-row-1')).dy;
      final older = tester.getTopLeft(key('history-row-0')).dy;
      expect(newer, lessThan(older));
      expect(
        find.descendant(
          of: key('history-row-0'),
          matching: find.text('3 นาที'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('history-row-0'), matching: find.text('+200')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: key('history-row-1'), matching: find.text('−120')),
        findsOneWidget,
      );
      await leave(tester);
    });
  });

  group('transfers and taking back', () {
    String friendBalance(WidgetTester tester, String seat) => tester
        .widgetList<Text>(
          find.descendant(of: key('friend-$seat'), matching: find.byType(Text)),
        )
        .map((t) => t.data!)
        .last;

    Future<void> transferTo(
      WidgetTester tester,
      String seat,
      String digits,
    ) async {
      await tester.tap(key('friend-$seat'));
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-give'));
      await tester.pumpAndSettle();
      await typeAmount(tester, digits);
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a friend offers to give or to ask', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      expect(key('friends-hint'), findsOneWidget);
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      expect(find.text('โอนให้ แพร'), findsOneWidget);
      expect(find.text('เรียกเก็บจาก แพร'), findsOneWidget);
      expect(find.text('มี 1,500'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('giving opens the transfer sheet for that friend', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-give'));
      await tester.pumpAndSettle();
      expect(find.text('โอนเงิน'), findsOneWidget);
      expect(key('transfer-pair'), findsOneWidget);
      expect(
        find.descendant(of: key('transfer-pair'), matching: find.text('แพร')),
        findsOneWidget,
      );
      expect(
        key('sheet-reason'),
        findsNothing,
        reason: 'no reason for a transfer',
      );
      await leave(tester);
    });

    testWidgets('the money goes to the friend and the history says so', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await transferTo(tester, 'p2', '700');
      expect(balance(tester), '800');
      expect(friendBalance(tester, 'p2'), '2,200');
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'โอน ต้น → แพร 700',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('more than you have opens the not-enough sheet', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await transferTo(tester, 'p2', '2000');
      expect(key('shortfall-sheet'), findsOneWidget);
      expect(find.text('จ่ายแพร 2,000 · มีอยู่ 1,500'), findsOneWidget);
      expect(balance(tester), '1,500');
      await leave(tester);
    });

    testWidgets('right after a press there is a bar to take it back', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      expect(key('undo-bar'), findsNothing);
      await transferTo(tester, 'p2', '700');
      expect(key('undo-bar'), findsOneWidget);
      expect(find.text('โอน 700 ให้แพรแล้ว'), findsOneWidget);
      expect(find.text('เลิกทำ 4'), findsOneWidget);
      await rest(tester);
      await leave(tester);
    });

    testWidgets('taking it back gives the money back on both sides', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await transferTo(tester, 'p2', '700');
      await tester.tap(key('undo-button'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,500');
      expect(friendBalance(tester, 'p2'), '1,500');
      expect(key('undo-bar'), findsNothing);
      expect(
        tester.widget<Text>(key('history-latest')).data,
        'โอน ต้น → แพร 700 · ยกเลิกแล้ว',
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets('an undo that fails after its bar is gone still says why', (
      tester,
    ) async {
      final gate = Completer<void>();
      await openApp(
        tester,
        store,
        '/room/$code',
        uid: _owner,
        repo: _HoldUndo(store, FakeAuthService(_owner), gate),
      );
      await tester.tap(key('press-go'));
      await tester.pumpAndSettle();
      await tester.tap(key('undo-button'));
      await tester.pump();
      // Somebody else presses while the undo is on its way: the bar goes.
      await repoOn(store, 'u2').submitEntry(code, EntryDraft.passGo());
      await tester.pumpAndSettle();
      expect(key('undo-bar'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(snackText(tester), 'ไม่ทันแล้ว มีรายการใหม่หรือหมดเวลา');
      expect(balance(tester), '1,700', reason: 'the press stays');
      await rest(tester);
      await leave(tester);
    });

    testWidgets('a receive from the bank can be taken back too', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-go'));
      await tester.pumpAndSettle();
      expect(find.text('ผ่านจุดเริ่ม +200 แล้ว'), findsOneWidget);
      await tester.tap(key('undo-button'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,500');
      await rest(tester);
      await leave(tester);
    });

    testWidgets('the bar goes away when its time is up', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-go'));
      await tester.pumpAndSettle();
      expect(key('undo-bar'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('เลิกทำ 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(key('undo-bar'), findsNothing);
      expect(balance(tester), '1,700', reason: 'the press stays');
      await leave(tester);
    });

    testWidgets('the bar goes away when somebody else presses after you', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-go'));
      await tester.pumpAndSettle();
      await repoOn(store, 'u2').submitEntry(code, EntryDraft.passGo());
      await tester.pumpAndSettle();
      expect(key('undo-bar'), findsNothing);
      await rest(tester);
      await leave(tester);
    });

    testWidgets('a press from before the screen opened has no bar', (
      tester,
    ) async {
      await repoOn(store, _owner).submitEntry(code, EntryDraft.passGo());
      await openApp(tester, store, '/room/$code', uid: _owner);
      expect(key('undo-bar'), findsNothing);
      await leave(tester);
    });

    testWidgets(
      'a friend who gives you money is announced, and taking it back too',
      (tester) async {
        await openApp(tester, store, '/room/$code', uid: _owner);
        await repoOn(
          store,
          'u2',
        ).submitEntry(code, EntryDraft.transfer('p1', 250));
        await tester.pumpAndSettle();
        expect(snackText(tester), 'แพร โอนให้คุณ +250');
        expect(balance(tester), '1,750');
        await repoOn(store, 'u2').undoEntry(code, 0);
        await tester.pumpAndSettle();
        expect(snackText(tester), 'แพร ยกเลิกการโอน 250');
        expect(balance(tester), '1,500');
        await leave(tester);
      },
    );

    testWidgets(
      'a transfer that was there when the screen opened is not announced',
      (tester) async {
        await repoOn(
          store,
          'u2',
        ).submitEntry(code, EntryDraft.transfer('p1', 250));
        await openApp(tester, store, '/room/$code', uid: _owner);
        expect(snackText(tester), isNull);
        await leave(tester);
      },
    );

    testWidgets(
      'a transfer in the history shows the amount, plus for what I got',
      (tester) async {
        await repoOn(
          store,
          'u2',
        ).submitEntry(code, EntryDraft.transfer('p1', 250));
        await openApp(tester, store, '/room/$code', uid: _owner);
        await tester.tap(key('history-strip'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: key('history-row-0'),
            matching: find.text('+250'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: key('history-row-0'),
            matching: find.text('โอน แพร → ต้น'),
          ),
          findsOneWidget,
        );
        await leave(tester);
      },
    );

    testWidgets('friends cannot be tapped offline', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      store.setOnline(false);
      await tester.pumpAndSettle();
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      expect(find.text('โอนเงิน'), findsNothing);
      await leave(tester);
    });

    testWidgets('a spectator cannot start a transfer and sees no hint', (
      tester,
    ) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 0xFF2E9E57);
      await openApp(tester, store, '/room/$code', uid: 's1');
      expect(key('friends-hint'), findsNothing);
      await tester.tap(key('friend-p1'));
      await tester.pumpAndSettle();
      expect(find.text('โอนเงิน'), findsNothing);
      await leave(tester);
    });
  });

  group('requests to pay', () {
    FakeRoomRepository u2() => repoOn(store, 'u2');

    Future<void> openAs(WidgetTester tester, String uid) => openApp(
      tester,
      store,
      '/room/$code',
      uid: uid,
      overrides: [roomClockProvider.overrideWithValue(() => clock)],
    );

    String ownBalance(WidgetTester tester) => balance(tester);

    Future<void> ask(WidgetTester tester, String seat, String digits) async {
      await tester.tap(key('friend-$seat'));
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-ask'));
      await tester.pumpAndSettle();
      await typeAmount(tester, digits);
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
    }

    testWidgets('asking opens a sheet that is about asking', (tester) async {
      await openAs(tester, _owner);
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-ask'));
      await tester.pumpAndSettle();
      expect(find.text('เรียกเก็บเงิน'), findsOneWidget);
      expect(key('collect-pair'), findsOneWidget);
      expect(find.text('แพร มีเวลา 2 นาทีในการตอบ'), findsOneWidget);
      expect(key('sheet-balance-chip'), findsNothing);
      await typeAmount(tester, '300');
      expect(find.text('ส่งคำขอ 300'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a request I send waits on top, and can be taken back', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await ask(tester, 'p2', '300');
      expect(key('request-waiting'), findsOneWidget);
      expect(find.textContaining('รอแพรจ่าย 300'), findsOneWidget);
      await tester.tap(key('request-cancel'));
      await tester.pumpAndSettle();
      expect(key('request-waiting'), findsNothing);
      expect(snackText(tester), 'คำขอถูกยกเลิก');
      await leave(tester);
    });

    testWidgets('asking again while the first is open is refused in words', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await ask(tester, 'p2', '300');
      await ask(tester, 'p2', '50');
      expect(snackText(tester), 'มีคำขอถึงคนนี้รออยู่แล้ว');
      expect(find.textContaining('รอแพรจ่าย 300'), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
      'a request made of me shows on a card with what I would have left',
      (tester) async {
        await openAs(tester, _owner);
        await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
        await tester.pumpAndSettle();
        expect(key('request-card'), findsOneWidget);
        expect(find.text('แพร เรียกเก็บ'), findsOneWidget);
        expect(tester.widget<Text>(key('request-amount')).data, '300');
        expect(find.text('คุณมี 1,500 · จะเหลือ 1,200'), findsOneWidget);
        expect(
          tester.widget<Text>(key('request-timer')).data,
          'หมดอายุใน 2:00',
        );
        await leave(tester);
      },
    );

    testWidgets('paying a request leaves no bar to take it back', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(key('request-pay'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,200');
      expect(key('undo-bar'), findsNothing);
      await rest(tester);
      await leave(tester);
    });

    testWidgets('the pay button waits a moment, then pays', (tester) async {
      await openAs(tester, _owner);
      await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
      await tester.pumpAndSettle();
      expect(enabled(tester, 'request-pay'), isFalse);
      await tester.tap(key('request-pay'), warnIfMissed: false);
      await tester.pump();
      expect(balance(tester), '1,500', reason: 'too early to count');
      await tester.pump(const Duration(milliseconds: 700));
      expect(enabled(tester, 'request-pay'), isTrue);
      await tester.tap(key('request-pay'));
      await tester.pumpAndSettle();
      expect(balance(tester), '1,200');
      expect(key('request-card'), findsNothing);
      await rest(tester);
      await leave(tester);
    });

    testWidgets('saying no closes it', (tester) async {
      await openAs(tester, _owner);
      await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
      await tester.pumpAndSettle();
      await tester.tap(key('request-decline'));
      await tester.pumpAndSettle();
      expect(key('request-card'), findsNothing);
      expect(balance(tester), '1,500');
      await leave(tester);
    });

    testWidgets(
      'with too little money the card says so; paying opens the sheet',
      (tester) async {
        await openAs(tester, _owner);
        await u2().requestMoney(code, fromSeat: 'p1', amount: 2000);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('คุณมี 1,500 · ไม่พอจ่าย'), findsOneWidget);
        expect(key('request-short'), findsOneWidget);
        expect(enabled(tester, 'request-pay'), isTrue);
        await tester.tap(key('request-pay'));
        await tester.pumpAndSettle();
        expect(key('shortfall-sheet'), findsOneWidget);
        expect(balance(tester), '1,500');
        await leave(tester);
      },
    );

    testWidgets('a request is paid with a mortgage from the sheet', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await u2().requestMoney(code, fromSeat: 'p1', amount: 2000);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(key('request-pay'));
      await tester.pumpAndSettle();
      await tester.enterText(key('mortgage-input'), '600');
      await tester.pump();
      await tester.tap(key('mortgage-add'));
      await tester.pump();
      await tester.tap(key('mortgage-confirm'));
      await tester.pumpAndSettle();
      expect(balance(tester), '100');
      expect(key('request-card'), findsNothing);
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('3,500')),
        findsOneWidget,
      );
      await rest(tester);
      await leave(tester);
    });

    testWidgets(
      'going bankrupt from the card pays the asker and ends the request',
      (tester) async {
        await openAs(tester, _owner);
        await u2().requestMoney(code, fromSeat: 'p1', amount: 2000);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 800));
        await tester.tap(key('request-pay'));
        await tester.pumpAndSettle();
        await tester.tap(key('bankrupt-button'));
        await tester.pumpAndSettle();
        await tester.tap(key('bankrupt-confirm'));
        await tester.pumpAndSettle();
        expect(balance(tester), '0');
        expect(key('band-banker'), findsOneWidget);
        expect(key('request-card'), findsNothing);
        expect(
          find.descendant(of: key('friend-p2'), matching: find.text('3,500')),
          findsOneWidget,
        );
        await leave(tester);
      },
    );

    testWidgets('several requests come one at a time, with a count', (
      tester,
    ) async {
      final three = await makeRoom(store);
      await repoOn(
        store,
        'u2',
      ).joinAsPlayer(code: three, name: 'แพร', color: 0xFFE11D48);
      await repoOn(
        store,
        'u3',
      ).joinAsPlayer(code: three, name: 'โอ๊ต', color: 0xFF10B981);
      await repoOn(store, _owner).startGame(three);
      await repoOn(store, 'u3').requestMoney(three, fromSeat: 'p1', amount: 30);
      await openApp(
        tester,
        store,
        '/room/$three',
        uid: _owner,
        overrides: [roomClockProvider.overrideWithValue(() => clock)],
      );
      await repoOn(store, 'u2').requestMoney(three, fromSeat: 'p1', amount: 20);
      await tester.pumpAndSettle();
      expect(key('request-card'), findsOneWidget);
      expect(tester.widget<Text>(key('request-amount')).data, '30');
      expect(find.text('ยังมีอีก 1 คำขอ'), findsOneWidget);
      await tester.tap(key('request-decline'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('request-amount')).data, '20');
      expect(key('request-more'), findsNothing);
      await leave(tester);
    });

    testWidgets('a request the room says is closed leaves the card', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      // The room's clock moves on; this screen's timer has not run out yet.
      clock = clock.add(const Duration(minutes: 3));
      await tester.tap(key('request-pay'));
      await tester.pumpAndSettle();
      expect(snackText(tester), 'คำขอนี้ปิดแล้ว');
      expect(key('request-card'), findsNothing);
      expect(balance(tester), '1,500');
      await leave(tester);
    });

    testWidgets('a request confirmed after the signal was lost is not sent', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      await tester.tap(key('friend-action-ask'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '300');
      store.setOnline(false);
      await tester.pump();
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      store.setOnline(true);
      await tester.pumpAndSettle();
      expect(key('request-waiting'), findsNothing);
      await leave(tester);
    });

    testWidgets('a payment that ends after its card is gone does not blow up', (
      tester,
    ) async {
      final gate = Completer<void>();
      await openApp(
        tester,
        store,
        '/room/$code',
        uid: _owner,
        overrides: [roomClockProvider.overrideWithValue(() => clock)],
        repo: _HoldPay(store, FakeAuthService(_owner), gate),
      );
      await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(key('request-pay'));
      await tester.pump();
      // The asker takes the request back while the payment is on its way.
      await u2().cancelRequest(code, 'p2_p1');
      await tester.pumpAndSettle();
      expect(key('request-card'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(snackText(tester), 'คำขอนี้ปิดแล้ว', reason: 'it is still told');
      await leave(tester);
    });

    testWidgets('a request that runs out goes away by itself', (tester) async {
      await openAs(tester, _owner);
      await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
      await tester.pumpAndSettle();
      expect(key('request-card'), findsOneWidget);
      clock = clock.add(const Duration(minutes: 2, seconds: 1));
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      await tester.pumpAndSettle();
      expect(key('request-card'), findsNothing);
      await leave(tester);
    });

    testWidgets('the one who asked is told when it was paid, by the money', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await ask(tester, 'p2', '300');
      expect(key('request-waiting'), findsOneWidget);
      await u2().payRequest(code, 'p1_p2', cid: 'cidcidcid1234');
      await tester.pumpAndSettle();
      expect(key('request-waiting'), findsNothing);
      expect(snackText(tester), 'แพร จ่ายตามที่เรียกเก็บ +300');
      expect(ownBalance(tester), '1,800');
      await leave(tester);
    });

    testWidgets('the one who asked is told when it was said no to', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await ask(tester, 'p2', '300');
      await u2().cancelRequest(code, 'p1_p2');
      await tester.pumpAndSettle();
      expect(snackText(tester), 'คำขอถูกยกเลิก');
      await leave(tester);
    });

    testWidgets('a spectator sees no card and no waiting bar', (tester) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 0xFF2E9E57);
      await openAs(tester, 's1');
      await u2().requestMoney(code, fromSeat: 'p1', amount: 300);
      await tester.pumpAndSettle();
      expect(key('request-card'), findsNothing);
      expect(key('request-waiting'), findsNothing);
      await leave(tester);
    });

    testWidgets(
      'the card holds a long name and the largest amount on a narrow screen',
      (tester) async {
        await openAs(tester, _owner);
        tester.view.physicalSize = const Size(300, 900);
        await u2().requestMoney(code, fromSeat: 'p1', amount: 999999999);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('999,999,999'), findsOneWidget);
        await leave(tester);
      },
    );
  });

  group('a long game', () {
    testWidgets('shows the newest entries only, and still plays', (
      tester,
    ) async {
      final other = repoOn(store, 'u2');
      for (var i = 0; i < historyWindow + 5; i++) {
        await other.submitEntry(code, EntryDraft.passGo());
      }
      await openApp(tester, store, '/room/$code', uid: _owner);
      expect(key('band-mismatch'), findsNothing);
      expect(enabled(tester, 'press-go'), isTrue);
      await tester.tap(key('history-strip'));
      await tester.pumpAndSettle();
      expect(key('history-window'), findsOneWidget);
      expect(find.text('แสดง 30 รายการล่าสุด'), findsOneWidget);
      expect(key('history-row-34'), findsOneWidget);
      expect(key('history-row-4'), findsNothing);
      await leave(tester);
    });

    testWidgets('says nothing about a window while the game is short', (
      tester,
    ) async {
      await repoOn(store, 'u2').submitEntry(code, EntryDraft.passGo());
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('history-strip'));
      await tester.pumpAndSettle();
      expect(key('history-window'), findsNothing);
      await leave(tester);
    });
  });

  group('a spectator', () {
    testWidgets('sees everyone and cannot press', (tester) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 0xFF2E9E57);
      await openApp(tester, store, '/room/$code', uid: 's1');
      expect(key('band-spectator'), findsOneWidget);
      expect(key('my-balance-card'), findsNothing);
      expect(key('friend-p1'), findsOneWidget);
      expect(key('friend-p2'), findsOneWidget);
      for (final k in ['press-pay', 'press-go', 'press-receive']) {
        expect(key(k), findsNothing, reason: k);
      }
      expect(key('history-strip'), findsOneWidget);
      await leave(tester);
    });
  });

  group('the bands', () {
    RoomGameView view({
      String? mySeat = 'p1',
      BalanceCheck check = BalanceCheck.ok,
      PressState press = const PressState(),
      List<String> bankrupt = const [],
      bool online = true,
    }) {
      const settings = RoomSettings(startingCash: 1500, goAmount: 200);
      final state = RoomState(
        seq: 0,
        seats: const ['p1', 'p2'],
        balances: const {'p1': 1500, 'p2': 1500},
        bankrupt: bankrupt,
        bankerSeat: null,
        status: RoomStatus.playing,
      );
      return RoomGameView(
        state: state,
        entries: const [],
        settings: settings,
        mySeat: mySeat,
        names: const {'p1': 'ต้น', 'p2': 'แพร'},
        colors: const {'p1': 0xFF3D5AFE, 'p2': 0xFFE11D48},
        online: online,
        check: check,
        press: press,
        block: pressBlock(
          mySeat: mySeat,
          seatActive: mySeat != null && !bankrupt.contains(mySeat),
          online: online,
          check: check,
          press: press,
        ),
      );
    }

    Future<void> show(WidgetTester tester, RoomGameView v) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roomGameProvider('K7M2QX').overrideWithValue(AsyncData(v)),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const RoomGameScreen(code: 'K7M2QX'),
          ),
        ),
      );
      await tester.pump();
    }

    void expectBand(WidgetTester tester, String band, {required bool on}) {
      for (final b in [
        'band-offline',
        'band-mismatch',
        'band-unsure',
        'band-syncing',
        'band-out',
        'band-spectator',
      ]) {
        expect(key(b), b == band ? findsOneWidget : findsNothing, reason: b);
      }
      for (final k in ['press-pay', 'press-go', 'press-receive']) {
        if (band == 'band-spectator') {
          expect(key(k), findsNothing);
        } else {
          expect(enabled(tester, k), on, reason: k);
        }
      }
    }

    testWidgets('a balance that does not match the history shuts the buttons', (
      tester,
    ) async {
      await show(tester, view(check: BalanceCheck.mismatch));
      expectBand(tester, 'band-mismatch', on: false);
    });

    testWidgets('a press of unknown fate shuts the buttons', (tester) async {
      await show(tester, view(press: const PressState(unsureCid: 'c')));
      expectBand(tester, 'band-unsure', on: false);
    });

    testWidgets('catching up leaves the buttons on', (tester) async {
      await show(tester, view(check: BalanceCheck.syncing));
      expectBand(tester, 'band-syncing', on: true);
    });

    testWidgets('someone who is out of the game cannot press', (tester) async {
      await show(tester, view(bankrupt: const ['p1']));
      expectBand(tester, 'band-out', on: false);
      expect(
        find.text('ออกจากเกม'),
        findsNothing,
        reason: 'my own card is not a friend row',
      );
    });

    testWidgets('a press on its way rests the buttons without a band', (
      tester,
    ) async {
      await show(tester, view(press: const PressState(sending: true)));
      for (final k in ['press-pay', 'press-go', 'press-receive']) {
        expect(enabled(tester, k), isFalse, reason: k);
      }
      expect(key('band-offline'), findsNothing);
    });

    Future<void> showWithRequest(
      WidgetTester tester,
      RoomGameView v,
      PendingRequest p,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roomGameProvider('K7M2QX').overrideWithValue(AsyncData(v)),
            requestsControllerProvider(
              'K7M2QX',
            ).overrideWith(() => _StubRequests(RequestsState(incoming: [p]))),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const RoomGameScreen(code: 'K7M2QX'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a request is offered to a player who is in the game', (
      tester,
    ) async {
      await showWithRequest(tester, view(), _pending());
      expect(key('request-card'), findsOneWidget);
      expect(enabled(tester, 'request-pay'), isTrue);
    });

    testWidgets('a player who is out is not offered requests', (tester) async {
      await showWithRequest(tester, view(bankrupt: const ['p1']), _pending());
      expect(key('request-card'), findsNothing);
    });

    testWidgets('a request whose time is up says so and cannot be paid', (
      tester,
    ) async {
      await showWithRequest(
        tester,
        view(),
        _pending(left: const Duration(seconds: -5)),
      );
      expect(tester.widget<Text>(key('request-timer')).data, 'หมดอายุ');
      expect(enabled(tester, 'request-pay'), isFalse);
    });

    testWidgets('a request cannot be paid while the buttons are off', (
      tester,
    ) async {
      await showWithRequest(
        tester,
        view(check: BalanceCheck.mismatch),
        _pending(),
      );
      expect(enabled(tester, 'request-pay'), isFalse);
    });

    testWidgets('a friend who is out cannot be given money', (tester) async {
      await show(tester, view(bankrupt: const ['p2']));
      await tester.tap(key('friend-p2'));
      await tester.pumpAndSettle();
      expect(find.text('โอนเงิน'), findsNothing);
    });

    testWidgets('a friend who is out is marked', (tester) async {
      await show(tester, view(bankrupt: const ['p2']));
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('ออกจากเกม')),
        findsOneWidget,
      );
    });
  });
}
