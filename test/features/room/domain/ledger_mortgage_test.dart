import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

const _seats = ['p1', 'p2', 'p3'];

RoomEntry _payBank(String from, int amount, {int? mortgage}) => RoomEntry(
  seq: 0,
  kind: EntryKind.payBank,
  seat: from,
  from: from,
  to: 'bank',
  amount: amount,
  mortgage: mortgage,
);

RoomEntry _transfer(String from, String to, int amount, {int? mortgage}) =>
    RoomEntry(
      seq: 0,
      kind: EntryKind.transfer,
      seat: from,
      from: from,
      to: to,
      amount: amount,
      mortgage: mortgage,
    );

LedgerState _applied(LedgerResult r) => (r as Applied).state;

LedgerRejection _why(LedgerResult r) => (r as Rejected).reason;

/// [seat] holds [cash] and nobody else changes: a room of three.
LedgerState _with(LedgerState s, String seat, int cash) => LedgerState(
  balances: {...s.balances, seat: cash},
  bankrupt: s.bankrupt,
  bankerSeat: s.bankerSeat,
  startingCash: s.startingCash,
);

void main() {
  final start = Ledger.initial(_seats, 1500);
  final limited = Ledger.initial(_seats, 1500, bankLimit: 5000);
  final poor = _with(start, 'p2', 400);
  final poorLimited = _with(limited, 'p2', 400);

  group('a payment to the bank with a mortgage', () {
    test('pays in full and keeps what is left over', () {
      final s = _applied(
        Ledger.apply(poor, _payBank('p2', 700, mortgage: 360)),
      );
      expect(s.balances['p2'], 60);
    });

    test('moves the bank by what it pays out and takes in', () {
      final s = _applied(
        Ledger.apply(poorLimited, _payBank('p2', 700, mortgage: 360)),
      );
      expect(s.balances['p2'], 60);
      expect(s.balances['bank'], 5000 - 360 + 700);
    });

    test('is refused when the bank does not hold the mortgage', () {
      final thin = LedgerState(
        balances: {...poorLimited.balances, 'bank': 359},
        bankrupt: const [],
        bankerSeat: null,
        startingCash: 1500,
      );
      expect(
        _why(Ledger.apply(thin, _payBank('p2', 700, mortgage: 360))),
        LedgerRejection.bankLimit,
      );
    });
  });

  group('a transfer with a mortgage', () {
    test('pays the receiver in full from the bank and the seat', () {
      final s = _applied(
        Ledger.apply(poorLimited, _transfer('p2', 'p3', 700, mortgage: 360)),
      );
      expect(s.balances['p2'], 60);
      expect(s.balances['p3'], 2200);
      expect(s.balances['bank'], 5000 - 360);
    });
  });

  group('a mortgage is refused', () {
    test('when the seat could pay without it', () {
      for (final cash in [700, 800]) {
        final s = _with(start, 'p2', cash);
        expect(
          _why(Ledger.apply(s, _payBank('p2', 700, mortgage: 100))),
          LedgerRejection.invalidMortgage,
          reason: '$cash',
        );
        expect(
          _why(Ledger.apply(s, _transfer('p2', 'p3', 700, mortgage: 100))),
          LedgerRejection.invalidMortgage,
          reason: '$cash',
        );
      }
    });

    test('when it does not cover what is missing', () {
      expect(
        _why(Ledger.apply(poor, _payBank('p2', 700, mortgage: 299))),
        LedgerRejection.insufficient,
      );
    });

    test('when what is left over is more than half the starting cash', () {
      // 400 + 1050 - 700 = 750 is exactly half of 1500
      expect(
        Ledger.apply(poor, _payBank('p2', 700, mortgage: 1050)),
        isA<Applied>(),
      );
      expect(
        _why(Ledger.apply(poor, _payBank('p2', 700, mortgage: 1051))),
        LedgerRejection.invalidMortgage,
      );
      expect(
        _why(Ledger.apply(poor, _transfer('p2', 'p3', 700, mortgage: 1051))),
        LedgerRejection.invalidMortgage,
      );
    });

    test('when it is zero, negative or too large', () {
      for (final m in [0, -5, maxEntryAmount + 1]) {
        expect(
          _why(Ledger.apply(poor, _payBank('p2', 700, mortgage: m))),
          LedgerRejection.invalidAmount,
          reason: '$m',
        );
      }
    });

    test('on a kind that pays nothing out of the seat', () {
      for (final kind in [EntryKind.receive, EntryKind.passGo]) {
        final e = RoomEntry(
          seq: 0,
          kind: kind,
          seat: 'p2',
          from: 'bank',
          to: 'p2',
          amount: 100,
          mortgage: 50,
        );
        expect(_why(Ledger.apply(poor, e)), LedgerRejection.invalidMortgage);
      }
    });
  });

  group('undoing a payment with a mortgage', () {
    test('gives the seat, the bank and the receiver back as they were', () {
      for (final e in [
        _payBank('p2', 700, mortgage: 360),
        _transfer('p2', 'p3', 700, mortgage: 360),
      ]) {
        final done = _applied(Ledger.apply(poorLimited, e));
        expect(_applied(Ledger.undo(done, e)).balances, poorLimited.balances);
      }
    });

    test('is refused when the receiver has spent what it got', () {
      final e = _transfer('p2', 'p3', 700, mortgage: 360);
      final done = _applied(Ledger.apply(poor, e));
      final spent = _applied(Ledger.apply(done, _payBank('p3', 2200)));
      expect(_why(Ledger.undo(spent, e)), LedgerRejection.insufficient);
    });

    test(
      'gives money to a bank below zero (after a bankruptcy) when it gains',
      () {
        // The mortgage 200 was bigger than the payment 100: undoing it pays the
        // bank back 100 net, so the bank gains and may stay below zero.
        final e = _payBank('p2', 100, mortgage: 200);
        final after = LedgerState(
          balances: {'p1': 1500, 'p2': 150, 'p3': 1500, 'bank': -500},
          bankrupt: const [],
          bankerSeat: null,
          startingCash: 1500,
        );
        final back = _applied(Ledger.undo(after, e));
        expect(back.balances['p2'], 50);
        expect(back.balances['bank'], -400);
      },
    );

    test('is refused when the bank no longer holds what it was paid', () {
      final e = _payBank('p2', 700, mortgage: 360);
      final done = _applied(Ledger.apply(poorLimited, e));
      final drained = _applied(
        Ledger.apply(
          done,
          RoomEntry(
            seq: 0,
            kind: EntryKind.receive,
            seat: 'p1',
            from: 'bank',
            to: 'p1',
            amount: done.balances['bank']! - 100,
          ),
        ),
      );
      expect(_why(Ledger.undo(drained, e)), LedgerRejection.bankLimit);
    });
  });

  test(
    'random games with mortgages: every undo gives back the state before',
    () {
      final rng = Random(11);
      var mortgaged = 0;
      for (var game = 0; game < 300; game++) {
        var state = rng.nextBool() ? start : limited;
        for (var step = 0; step < 20; step++) {
          final seat = _seats[rng.nextInt(3)];
          final other = _seats[(_seats.indexOf(seat) + 1 + rng.nextInt(2)) % 3];
          final cash = state.balances[seat]!;
          final amount = 1 + rng.nextInt(2500);
          final mortgage = amount > cash && rng.nextBool()
              ? amount - cash + rng.nextInt(400)
              : null;
          final e = rng.nextBool()
              ? _payBank(seat, amount, mortgage: mortgage)
              : _transfer(seat, other, amount, mortgage: mortgage);
          final r = Ledger.apply(state, e);
          if (r is! Applied) continue;
          if (mortgage != null) mortgaged++;
          final back = Ledger.undo(r.state, e);
          expect(back, isA<Applied>());
          expect((back as Applied).state.balances, state.balances);
          state = r.state;
        }
      }
      expect(mortgaged, greaterThan(100));
    },
  );
}
