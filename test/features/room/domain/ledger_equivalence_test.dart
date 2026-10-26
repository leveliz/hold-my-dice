import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

/// Plays random games on the single-device [GameState] and, step by step, the
/// same moves as [RoomEntry]s on the [Ledger]. Both must agree on every
/// balance, on who is bankrupt and on every refusal.
void main() {
  test('the ledger agrees with GameState over 2000 random games', () {
    for (var seed = 0; seed < 2000; seed++) {
      _playOneGame(seed);
    }
  });

  test('a payment with a mortgage in one entry agrees with GameState', () {
    var taken = 0;
    for (var seed = 0; seed < 500; seed++) {
      _playMortgageGame(seed, () => taken++);
    }
    expect(taken, greaterThan(300));
  });
}

/// The same payment with a mortgage as ONE entry: whenever the ledger takes
/// it, [GameState.payWithMortgage] takes it too and both end with the same
/// balances (the ledger also refuses some that GameState would allow).
void _playMortgageGame(int seed, void Function() applied) {
  final random = Random(seed);
  final seats = ['p1', 'p2', 'p3'];
  const startingCash = 1500;
  var game = GameState.start(
    players: [for (final s in seats) Player(id: s, name: s, color: 0)],
    startingCash: startingCash,
    goAmount: 200,
  );
  var ledger = Ledger.initial(seats, startingCash);
  for (var step = 0; step < 30 && !game.isOver; step++) {
    final who = seats[random.nextInt(3)];
    final cash = game.balanceOf(who);
    final amount = cash + 1 + random.nextInt(600);
    final payee = random.nextBool()
        ? 'bank'
        : seats.firstWhere((s) => s != who);
    final mortgage = amount - cash + random.nextInt(500);
    final moved = Ledger.apply(
      ledger,
      RoomEntry(
        seq: 0,
        kind: payee == 'bank' ? EntryKind.payBank : EntryKind.transfer,
        seat: who,
        from: who,
        to: payee,
        amount: amount,
        mortgage: mortgage,
      ),
    );
    if (moved is! Applied) {
      // Give the seat some money so the next presses are not all refused.
      game = game.receiveFromBank(who, 400);
      ledger = _ok(
        Ledger.apply(
          ledger,
          RoomEntry(
            seq: 0,
            kind: EntryKind.receive,
            seat: who,
            from: 'bank',
            to: who,
            amount: 400,
          ),
        ),
      );
      continue;
    }
    final result = game.payWithMortgage(
      payerId: who,
      payeeId: payee,
      amount: amount,
      mortgages: [mortgage],
    );
    expect(result, isA<Paid>(), reason: 'seed $seed, step $step');
    game = (result as Paid).state;
    ledger = moved.state;
    applied();
    for (final s in seats) {
      expect(ledger.balances[s], game.balanceOf(s), reason: 'seed $seed, $s');
    }
  }
}

void _playOneGame(int seed) {
  final random = Random(seed);
  final players = random.nextInt(5) + 2;
  final startingCash = (random.nextInt(30) + 1) * 100;
  const goAmount = 200;
  final seats = [for (var i = 1; i <= players; i++) 'p$i'];
  var game = GameState.start(
    players: [for (final s in seats) Player(id: s, name: s, color: 0)],
    startingCash: startingCash,
    goAmount: goAmount,
  );
  var ledger = Ledger.initial(seats, startingCash);
  final steps = random.nextInt(60) + 1;

  RoomEntry entry(
    EntryKind kind,
    String seat, {
    String? from,
    String? to,
    int? amount,
    BankruptInfo? bankrupt,
  }) => RoomEntry(
    seq: 0,
    kind: kind,
    seat: seat,
    from: from,
    to: to,
    amount: amount,
    bankrupt: bankrupt,
  );

  void check(String what) {
    for (final s in seats) {
      expect(
        ledger.balances[s],
        game.balanceOf(s),
        reason: 'seed $seed, $what, seat $s',
      );
    }
    expect(ledger.bankrupt, [
      for (final e in game.history) ?e.bankruptPlayerId,
    ], reason: 'seed $seed, $what, bankrupt list');
    expect(
      ledger.bankerSeat,
      ledger.bankrupt.firstOrNull,
      reason: 'seed $seed, $what, banker',
    );
  }

  for (var step = 0; step < steps && !game.isOver; step++) {
    final active = game.activePlayers.map((p) => p.id).toList();
    final who = active[random.nextInt(active.length)];
    final other = active.where((s) => s != who).toList()..shuffle(random);
    final amount = random.nextInt(startingCash * 2) + 1;
    final action = random.nextInt(7);
    final label = 'step $step action $action';

    switch (action) {
      case 0:
        game = game.passGo(who);
        ledger = _ok(
          Ledger.apply(
            ledger,
            entry(
              EntryKind.passGo,
              who,
              from: 'bank',
              to: who,
              amount: goAmount,
            ),
          ),
        );
      case 1:
        game = game.receiveFromBank(who, amount);
        ledger = _ok(
          Ledger.apply(
            ledger,
            entry(
              EntryKind.receive,
              who,
              from: 'bank',
              to: who,
              amount: amount,
            ),
          ),
        );
      case 2:
        game = game.mortgage(who, amount);
        ledger = _ok(
          Ledger.apply(
            ledger,
            entry(
              EntryKind.mortgage,
              who,
              from: 'bank',
              to: who,
              amount: amount,
            ),
          ),
        );
      case 3:
        final result = game.payBank(who, amount);
        final moved = Ledger.apply(
          ledger,
          entry(EntryKind.payBank, who, from: who, to: 'bank', amount: amount),
        );
        if (result is Paid) {
          game = result.state;
          ledger = _ok(moved);
        } else {
          expect(moved, isA<Rejected>(), reason: 'seed $seed, $label');
          expect((moved as Rejected).reason, LedgerRejection.insufficient);
        }
      case 4:
        final to = other.first;
        final result = game.transfer(who, to, amount);
        final moved = Ledger.apply(
          ledger,
          entry(EntryKind.transfer, who, from: who, to: to, amount: amount),
        );
        if (result is Paid) {
          game = result.state;
          ledger = _ok(moved);
        } else {
          expect(moved, isA<Rejected>(), reason: 'seed $seed, $label');
          expect((moved as Rejected).reason, LedgerRejection.insufficient);
        }
      case 5:
        final mortgages = [
          for (var i = random.nextInt(3) + 1; i > 0; i--)
            random.nextInt(startingCash) + 1,
        ];
        final payee = random.nextBool() ? 'bank' : other.first;
        final result = game.payWithMortgage(
          payerId: who,
          payeeId: payee,
          amount: amount,
          mortgages: mortgages,
        );
        final total = mortgages.fold<int>(0, (a, b) => a + b);
        final moved = Ledger.applyGroup(ledger, [
          entry(EntryKind.mortgage, who, from: 'bank', to: who, amount: total),
          entry(
            payee == 'bank' ? EntryKind.payBank : EntryKind.transfer,
            who,
            from: who,
            to: payee,
            amount: amount,
          ),
        ]);
        if (result is Paid) {
          game = result.state;
          ledger = _ok(moved);
        } else {
          expect(moved, isA<Rejected>(), reason: 'seed $seed, $label');
          expect((moved as Rejected).reason, LedgerRejection.insufficient);
        }
      default:
        final cash = game.balanceOf(who);
        final cap = 10 * startingCash;
        if (cash + 1 > cap) continue;
        final owed = cash + 1 + random.nextInt(cap - cash);
        final creditor = random.nextBool() ? other.first : null;
        game = game.declareBankrupt(who, owed: owed, creditorId: creditor);
        ledger = _ok(
          Ledger.apply(
            ledger,
            entry(
              EntryKind.bankrupt,
              who,
              bankrupt: BankruptInfo(
                seat: who,
                creditorSeat: creditor,
                cash: cash,
                owed: owed,
              ),
            ),
          ),
        );
    }
    check(label);
  }
}

LedgerState _ok(LedgerResult result) {
  expect(
    result,
    isA<Applied>(),
    reason: result is Rejected ? '${result.reason}' : null,
  );
  return (result as Applied).state;
}
