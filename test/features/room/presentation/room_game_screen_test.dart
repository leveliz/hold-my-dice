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
  Future<void> payRequest(String code, String id, {required String cid}) async {
    await gate.future;
    return super.payRequest(code, id, cid: cid);
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

    testWidgets('paying more than they hold is refused in words', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await tester.tap(key('press-pay'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '2000');
      await tester.tap(key('sheet-ok'));
      await tester.pumpAndSettle();
      expect(snackText(tester), contains('เงินไม่พอ'));
      expect(balance(tester), '1,500');
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

    testWidgets('more than you have is refused in words', (tester) async {
      await openApp(tester, store, '/room/$code', uid: _owner);
      await transferTo(tester, 'p2', '2000');
      expect(snackText(tester), contains('เงินไม่พอ'));
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

    testWidgets('with too little money the card says so and cannot pay', (
      tester,
    ) async {
      await openAs(tester, _owner);
      await u2().requestMoney(code, fromSeat: 'p1', amount: 2000);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('คุณมี 1,500 · ไม่พอจ่าย'), findsOneWidget);
      expect(key('request-short'), findsOneWidget);
      expect(enabled(tester, 'request-pay'), isFalse);
      await leave(tester);
    });

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
