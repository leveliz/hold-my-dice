import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

const _settings = RoomSettings(startingCash: 1500, goAmount: 200);
const _limited = RoomSettings(
  startingCash: 1500,
  goAmount: 200,
  bankLimit: 5000,
);
final _at = DateTime.utc(2026, 10, 26);

RoomState _state(int seq, Map<String, int> balances) => RoomState(
  seq: seq,
  seats: const ['p1', 'p2'],
  balances: balances,
  bankrupt: const [],
  bankerSeat: null,
  status: RoomStatus.playing,
);

RoomEntry _receive(int seq, String seat, int amount, {DateTime? at}) =>
    RoomEntry(
      seq: seq,
      kind: EntryKind.receive,
      seat: seat,
      by: 'u',
      at: at ?? _at,
      cid: 'c$seq',
      from: 'bank',
      to: seat,
      amount: amount,
      reason: 'ค่าเช่า',
    );

RoomEntry _pay(int seq, String seat, int amount) => RoomEntry(
  seq: seq,
  kind: EntryKind.payBank,
  seat: seat,
  by: 'u',
  at: _at,
  cid: 'c$seq',
  from: seat,
  to: 'bank',
  amount: amount,
);

void main() {
  group('checkBalances', () {
    test('a game that has just started has nothing to add up', () {
      expect(
        checkBalances(
          state: _state(0, {'p1': 1500, 'p2': 1500}),
          entries: const [],
          settings: _settings,
        ),
        BalanceCheck.ok,
      );
    });

    test('the entries add up to the balances', () {
      expect(
        checkBalances(
          state: _state(2, {'p1': 1800, 'p2': 1200}),
          entries: [_receive(0, 'p1', 300), _pay(1, 'p2', 300)],
          settings: _settings,
        ),
        BalanceCheck.ok,
      );
    });

    test('a limited bank is added up too', () {
      expect(
        checkBalances(
          state: _state(2, {'p1': 1800, 'p2': 1200, 'bank': 5000}),
          entries: [_receive(0, 'p1', 300), _pay(1, 'p2', 300)],
          settings: _limited,
        ),
        BalanceCheck.ok,
      );
      expect(
        checkBalances(
          state: _state(2, {'p1': 1800, 'p2': 1200, 'bank': 4000}),
          entries: [_receive(0, 'p1', 300), _pay(1, 'p2', 300)],
          settings: _limited,
        ),
        BalanceCheck.mismatch,
      );
    });

    test('a balance that is not what the entries make is a mismatch', () {
      expect(
        checkBalances(
          state: _state(1, {'p1': 1801, 'p2': 1500}),
          entries: [_receive(0, 'p1', 300)],
          settings: _settings,
        ),
        BalanceCheck.mismatch,
      );
    });

    test('money that came from nowhere is a mismatch', () {
      expect(
        checkBalances(
          state: _state(0, {'p1': 1500, 'p2': 1600}),
          entries: const [],
          settings: _settings,
        ),
        BalanceCheck.mismatch,
      );
    });

    test('an entry the rules of the money would refuse is a mismatch', () {
      expect(
        checkBalances(
          state: _state(1, {'p1': -500, 'p2': 1500}),
          entries: [_pay(0, 'p1', 2000)],
          settings: _settings,
        ),
        BalanceCheck.mismatch,
      );
    });

    test(
      'an entry the rules would refuse is a mismatch even when the books look untouched',
      () {
        expect(
          checkBalances(
            state: _state(1, {'p1': 1500, 'p2': 1500}),
            entries: [_pay(0, 'p1', 2000)],
            settings: _settings,
          ),
          BalanceCheck.mismatch,
        );
      },
    );

    test('a balance for a seat the game does not have is a mismatch', () {
      expect(
        checkBalances(
          state: _state(0, {'p1': 1500, 'p2': 1500, 'p3': 1500}),
          entries: const [],
          settings: _settings,
        ),
        BalanceCheck.mismatch,
      );
    });

    test(
      'a bank in the balances of a room whose bank has no limit is a mismatch',
      () {
        expect(
          checkBalances(
            state: _state(0, {'p1': 1500, 'p2': 1500, 'bank': 5000}),
            entries: const [],
            settings: _settings,
          ),
          BalanceCheck.mismatch,
        );
      },
    );

    test('a balance that is missing is a mismatch', () {
      expect(
        checkBalances(
          state: _state(0, {'p1': 1500}),
          entries: const [],
          settings: _settings,
        ),
        BalanceCheck.mismatch,
      );
    });

    test('fewer entries than the state counts is still syncing', () {
      expect(
        checkBalances(
          state: _state(2, {'p1': 1800, 'p2': 1200}),
          entries: [_receive(0, 'p1', 300)],
          settings: _settings,
        ),
        BalanceCheck.syncing,
      );
    });

    test('more entries than the state counts is still syncing', () {
      expect(
        checkBalances(
          state: _state(1, {'p1': 1800, 'p2': 1500}),
          entries: [_receive(0, 'p1', 300), _pay(1, 'p2', 300)],
          settings: _settings,
        ),
        BalanceCheck.syncing,
      );
    });

    test('a gap in the numbers is still syncing', () {
      expect(
        checkBalances(
          state: _state(2, {'p1': 1800, 'p2': 1200}),
          entries: [_receive(0, 'p1', 300), _pay(2, 'p2', 300)],
          settings: _settings,
        ),
        BalanceCheck.syncing,
      );
    });

    test('entries that do not start at 0 are still syncing', () {
      expect(
        checkBalances(
          state: _state(2, {'p1': 1500, 'p2': 1500}),
          entries: [_receive(1, 'p1', 300), _pay(2, 'p2', 300)],
          settings: _settings,
        ),
        BalanceCheck.syncing,
      );
    });

    test('an entry still on its way (no server time yet) is syncing', () {
      final pending = RoomEntry(
        seq: 0,
        kind: EntryKind.receive,
        seat: 'p1',
        by: 'u',
        cid: 'c0',
        from: 'bank',
        to: 'p1',
        amount: 300,
        reason: 'ค่าเช่า',
      );
      expect(
        checkBalances(
          state: _state(1, {'p1': 1800, 'p2': 1500}),
          entries: [pending],
          settings: _settings,
        ),
        BalanceCheck.syncing,
      );
    });

    test('it is not a mismatch merely because the state is ahead', () {
      expect(
        checkBalances(
          state: _state(1, {'p1': 1800, 'p2': 1500}),
          entries: const [],
          settings: _settings,
        ),
        BalanceCheck.syncing,
      );
    });

    test('a voided entry moves no money', () {
      final voided = RoomEntry(
        seq: 0,
        kind: EntryKind.receive,
        seat: 'p1',
        by: 'u',
        at: _at,
        cid: 'c0',
        from: 'bank',
        to: 'p1',
        amount: 300,
        reason: 'ค่าเช่า',
        voided: true,
      );
      expect(
        checkBalances(
          state: _state(1, {'p1': 1500, 'p2': 1500}),
          entries: [voided],
          settings: _settings,
        ),
        BalanceCheck.ok,
      );
    });
  });
}
