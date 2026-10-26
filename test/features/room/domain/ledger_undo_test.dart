import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

const _seats = ['p1', 'p2', 'p3'];

RoomEntry _fromBank(EntryKind kind, String to, int amount) => RoomEntry(
  seq: 0,
  kind: kind,
  seat: to,
  from: 'bank',
  to: to,
  amount: amount,
);

RoomEntry _payBank(String from, int amount) => RoomEntry(
  seq: 0,
  kind: EntryKind.payBank,
  seat: from,
  from: from,
  to: 'bank',
  amount: amount,
);

RoomEntry _transfer(String from, String to, int amount) => RoomEntry(
  seq: 0,
  kind: EntryKind.transfer,
  seat: from,
  from: from,
  to: to,
  amount: amount,
);

LedgerState _applied(LedgerResult r) => (r as Applied).state;

LedgerRejection _why(LedgerResult r) => (r as Rejected).reason;

void main() {
  final start = Ledger.initial(_seats, 1500);
  final limited = Ledger.initial(_seats, 1500, bankLimit: 5000);

  group('Ledger.undo gives the balances back', () {
    test('a receive', () {
      final e = _fromBank(EntryKind.receive, 'p1', 300);
      final done = _applied(Ledger.apply(start, e));
      expect(_applied(Ledger.undo(done, e)).balances, start.balances);
    });

    test('a pass over GO', () {
      final e = _fromBank(EntryKind.passGo, 'p2', 200);
      final done = _applied(Ledger.apply(start, e));
      expect(_applied(Ledger.undo(done, e)).balances, start.balances);
    });

    test('a payment to the bank', () {
      final e = _payBank('p1', 500);
      final done = _applied(Ledger.apply(start, e));
      expect(_applied(Ledger.undo(done, e)).balances, start.balances);
    });

    test('a transfer, both sides', () {
      final e = _transfer('p1', 'p3', 700);
      final done = _applied(Ledger.apply(start, e));
      expect(done.balances['p1'], 800);
      expect(done.balances['p3'], 2200);
      expect(_applied(Ledger.undo(done, e)).balances, start.balances);
    });

    test('the bank of a room with a limit, both ways', () {
      for (final e in [
        _fromBank(EntryKind.receive, 'p1', 300),
        _payBank('p2', 400),
      ]) {
        final done = _applied(Ledger.apply(limited, e));
        expect(_applied(Ledger.undo(done, e)).balances, limited.balances);
      }
    });
  });

  group('Ledger.undo refuses', () {
    test('what would leave a seat below zero', () {
      final e = _fromBank(EntryKind.receive, 'p1', 300);
      final spent = _applied(
        Ledger.apply(_applied(Ledger.apply(start, e)), _payBank('p1', 1700)),
      );
      expect(_why(Ledger.undo(spent, e)), LedgerRejection.insufficient);
    });

    test('an undone transfer whose receiver spent the money', () {
      final e = _transfer('p1', 'p2', 700);
      final spent = _applied(
        Ledger.apply(_applied(Ledger.apply(start, e)), _payBank('p2', 2200)),
      );
      expect(_why(Ledger.undo(spent, e)), LedgerRejection.insufficient);
    });

    test('the bank paying back more than it holds', () {
      final e = _payBank('p1', 400);
      final drained = _applied(
        Ledger.apply(
          _applied(Ledger.apply(limited, e)),
          _fromBank(EntryKind.receive, 'p2', 5400),
        ),
      );
      expect(_why(Ledger.undo(drained, e)), LedgerRejection.bankLimit);
    });

    test('an entry that is already undone', () {
      final e = RoomEntry(
        seq: 0,
        kind: EntryKind.receive,
        seat: 'p1',
        from: 'bank',
        to: 'p1',
        amount: 10,
        voided: true,
      );
      expect(_why(Ledger.undo(start, e)), LedgerRejection.notUndoable);
    });

    test('kinds that are not undone here (mortgage, bankruptcy)', () {
      final m = _fromBank(EntryKind.mortgage, 'p1', 10);
      expect(_why(Ledger.undo(start, m)), LedgerRejection.notUndoable);
      final b = RoomEntry(
        seq: 0,
        kind: EntryKind.bankrupt,
        seat: 'p1',
        bankrupt: const BankruptInfo(seat: 'p1', cash: 1500, owed: 2000),
      );
      expect(_why(Ledger.undo(start, b)), LedgerRejection.notUndoable);
    });
  });

  test('hundreds of random games: every undo gives back the state before', () {
    final rng = Random(7);
    for (var game = 0; game < 300; game++) {
      var state = rng.nextBool() ? start : limited;
      for (var step = 0; step < 20; step++) {
        final seat = _seats[rng.nextInt(3)];
        final other = _seats[(_seats.indexOf(seat) + 1 + rng.nextInt(2)) % 3];
        final amount = 1 + rng.nextInt(900);
        final e = switch (rng.nextInt(4)) {
          0 => _fromBank(EntryKind.receive, seat, amount),
          1 => _fromBank(EntryKind.passGo, seat, amount),
          2 => _payBank(seat, amount),
          _ => _transfer(seat, other, amount),
        };
        final r = Ledger.apply(state, e);
        if (r is! Applied) continue;
        final back = Ledger.undo(r.state, e);
        expect(back, isA<Applied>());
        expect((back as Applied).state.balances, state.balances);
        state = r.state; // the do stays, the next one is tried on it
      }
    }
  });
}
