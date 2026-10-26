import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart'
    show historyWindow;
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/presentation/room_game_screen.dart';

import 'room_test_app.dart';

const _owner = 'owner';
final _t0 = DateTime.utc(2026, 10, 26, 12);

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
      expect(snackText(tester), 'เงินไม่พอ');
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

    testWidgets('a friend who is out is marked', (tester) async {
      await show(tester, view(bankrupt: const ['p2']));
      expect(
        find.descendant(of: key('friend-p2'), matching: find.text('ออกจากเกม')),
        findsOneWidget,
      );
    });
  });
}
