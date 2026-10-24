import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';

GameState newGame({int players = 3, int start = 1500, int go = 200}) {
  return GameState.start(
    players: [
      for (var i = 1; i <= players; i++)
        Player(id: 'p$i', name: 'ผู้เล่น $i', color: 0xFF000000 + i),
    ],
    startingCash: start,
    goAmount: go,
  );
}

GameState paid(PayResult r) => (r as Paid).state;

void main() {
  group('start', () {
    test('everyone begins with the starting cash', () {
      final g = newGame();
      expect(g.balanceOf('p1'), 1500);
      expect(g.balanceOf('p3'), 1500);
      expect(g.history, isEmpty);
    });

    test('needs at least 2 players', () {
      expect(() => newGame(players: 1), throwsArgumentError);
    });

    test('starting cash and go amount must be positive', () {
      expect(() => newGame(start: 0), throwsArgumentError);
      expect(() => newGame(go: 0), throwsArgumentError);
    });

    test('player ids must be unique', () {
      expect(
        () => GameState.start(
          players: const [
            Player(id: 'a', name: 'A', color: 1),
            Player(id: 'a', name: 'B', color: 2),
          ],
          startingCash: 100,
          goAmount: 10,
        ),
        throwsArgumentError,
      );
    });
  });

  group('basic transactions', () {
    test('passGo pays the go amount from the bank', () {
      final g = newGame().passGo('p1');
      expect(g.balanceOf('p1'), 1700);
      final t = g.history.single.transactions.single;
      expect(t.type, TransactionType.passGo);
      expect(t.from, Transaction.bank);
      expect(t.to, 'p1');
    });

    test('receiveFromBank adds money', () {
      final g = newGame().receiveFromBank('p2', 300);
      expect(g.balanceOf('p2'), 1800);
    });

    test('payBank removes money', () {
      final g = paid(newGame().payBank('p1', 400));
      expect(g.balanceOf('p1'), 1100);
    });

    test('transfer moves money between players', () {
      final g = paid(newGame().transfer('p1', 'p2', 500));
      expect(g.balanceOf('p1'), 1000);
      expect(g.balanceOf('p2'), 2000);
    });

    test('mortgage adds money and records its own type', () {
      final g = newGame().mortgage('p1', 600);
      expect(g.balanceOf('p1'), 2100);
      expect(
        g.history.single.transactions.single.type,
        TransactionType.mortgage,
      );
    });

    test('amounts must be positive', () {
      expect(() => newGame().receiveFromBank('p1', 0), throwsArgumentError);
      expect(() => newGame().payBank('p1', -5), throwsArgumentError);
    });

    test('transfer to self or unknown player is rejected', () {
      expect(() => newGame().transfer('p1', 'p1', 10), throwsArgumentError);
      expect(() => newGame().transfer('p1', 'zzz', 10), throwsArgumentError);
    });
  });

  group('insufficient funds', () {
    test('paying more than the balance reports the shortfall', () {
      final r = newGame().payBank('p1', 1800);
      expect(r, isA<Insufficient>());
      expect((r as Insufficient).shortfall, 300);
    });

    test('state is untouched when the payment is refused', () {
      final g = newGame();
      g.transfer('p1', 'p2', 9999);
      expect(g.balanceOf('p1'), 1500);
      expect(g.history, isEmpty);
    });

    test('paying exactly the balance is allowed', () {
      final g = paid(newGame().payBank('p1', 1500));
      expect(g.balanceOf('p1'), 0);
    });

    test('transfer is refused with the same shortfall rule', () {
      final r = newGame().transfer('p1', 'p2', 1501);
      expect((r as Insufficient).shortfall, 1);
    });
  });

  group('mortgage then pay', () {
    test('mortgages cover the shortfall and the payment is one entry', () {
      final r = newGame().payWithMortgage(
        payerId: 'p1',
        payeeId: Transaction.bank,
        amount: 1800,
        mortgages: [200, 150],
      );
      final g = paid(r);
      expect(g.balanceOf('p1'), 1500 + 350 - 1800);
      expect(g.history.length, 1);
      expect(g.history.single.transactions.length, 3);
    });

    test('is refused when mortgages still fall short', () {
      final r = newGame().payWithMortgage(
        payerId: 'p1',
        payeeId: 'p2',
        amount: 2000,
        mortgages: [200, 100],
      );
      expect((r as Insufficient).shortfall, 200);
    });

    test('pays a player and credits them', () {
      final g = paid(
        newGame().payWithMortgage(
          payerId: 'p1',
          payeeId: 'p2',
          amount: 1700,
          mortgages: [300],
        ),
      );
      expect(g.balanceOf('p1'), 100);
      expect(g.balanceOf('p2'), 3200);
    });

    test('a single undo reverts the mortgages and the payment', () {
      final g = paid(
        newGame().payWithMortgage(
          payerId: 'p1',
          payeeId: Transaction.bank,
          amount: 1800,
          mortgages: [300],
        ),
      );
      expect(g.undo().balanceOf('p1'), 1500);
    });

    test('mortgage amounts must be positive', () {
      expect(
        () => newGame().payWithMortgage(
          payerId: 'p1',
          payeeId: Transaction.bank,
          amount: 1800,
          mortgages: [300, 0],
        ),
        throwsArgumentError,
      );
    });
  });

  group('bankruptcy', () {
    // p1 ends with 200 left.
    GameState poor() => paid(newGame().payBank('p1', 1300));

    test(
      'debt to a player: creditor is paid in full, bank covers the rest',
      () {
        final g = poor().declareBankrupt('p1', owed: 1000, creditorId: 'p2');
        expect(g.isBankrupt('p1'), isTrue);
        expect(g.balanceOf('p1'), 0);
        expect(g.balanceOf('p2'), 2500);
        final fromBank = g.history.last.transactions
            .where((t) => t.from == Transaction.bank)
            .single;
        expect(fromBank.amount, 800);
      },
    );

    test('debt to the bank: the remaining cash goes back to the bank', () {
      final g = poor().declareBankrupt('p1', owed: 1000);
      expect(g.balanceOf('p1'), 0);
      expect(g.balanceOf('p2'), 1500);
      final t = g.history.last.transactions.single;
      expect(t.from, 'p1');
      expect(t.to, Transaction.bank);
      expect(t.amount, 200);
    });

    test('player with zero cash left only triggers the bank cover', () {
      final g = paid(
        newGame().payBank('p1', 1500),
      ).declareBankrupt('p1', owed: 400, creditorId: 'p3');
      expect(g.balanceOf('p3'), 1900);
      expect(g.history.last.transactions.length, 1);
    });

    test('cannot go bankrupt while able to pay', () {
      expect(
        () => newGame().declareBankrupt('p1', owed: 1500),
        throwsArgumentError,
      );
    });

    test('a bankrupt player cannot take part in transactions', () {
      final g = poor().declareBankrupt('p1', owed: 1000);
      expect(() => g.passGo('p1'), throwsStateError);
      expect(() => g.transfer('p2', 'p1', 10), throwsStateError);
      expect(() => g.declareBankrupt('p1', owed: 5), throwsStateError);
    });

    test('creditor must be a different, active player', () {
      expect(
        () => poor().declareBankrupt('p1', owed: 1000, creditorId: 'p1'),
        throwsArgumentError,
      );
    });

    test('undo brings a bankrupt player back', () {
      final g = poor()
          .declareBankrupt('p1', owed: 1000, creditorId: 'p2')
          .undo();
      expect(g.isBankrupt('p1'), isFalse);
      expect(g.balanceOf('p1'), 200);
      expect(g.balanceOf('p2'), 1500);
    });
  });

  group('undo', () {
    test('reverts only the latest entry', () {
      final g = newGame().passGo('p1').receiveFromBank('p1', 100);
      final u = g.undo();
      expect(u.balanceOf('p1'), 1700);
      expect(u.history.length, 1);
    });

    test('canUndo is false on a fresh game and undo then throws', () {
      final g = newGame();
      expect(g.canUndo, isFalse);
      expect(g.undo, throwsStateError);
    });

    test('does not mutate the original state', () {
      final g = newGame().passGo('p1');
      g.undo();
      expect(g.balanceOf('p1'), 1700);
    });
  });

  group('end of game and ranking', () {
    test('game is over when only one player is left', () {
      final g = paid(
        newGame(players: 2).payBank('p1', 1500),
      ).declareBankrupt('p1', owed: 10);
      expect(g.isOver, isTrue);
      expect(g.winner?.id, 'p2');
    });

    test('not over while two or more players remain', () {
      final g = paid(
        newGame().payBank('p1', 1500),
      ).declareBankrupt('p1', owed: 10);
      expect(g.isOver, isFalse);
      expect(g.winner, isNull);
    });

    test('ranking sorts by money, bankrupt players last', () {
      var g = newGame(players: 4);
      g = g.receiveFromBank('p3', 1000); // 2500
      g = g.receiveFromBank('p2', 300); // 1800
      g = paid(g.payBank('p4', 1500)).declareBankrupt('p4', owed: 1);
      final order = g.ranking.map((p) => p.id).toList();
      expect(order, ['p3', 'p2', 'p1', 'p4']);
    });

    test('later bankruptcy ranks higher than an earlier one', () {
      var g = newGame(players: 4);
      g = paid(g.payBank('p1', 1500)).declareBankrupt('p1', owed: 1);
      g = paid(g.payBank('p2', 1500)).declareBankrupt('p2', owed: 1);
      final order = g.ranking.map((p) => p.id).toList();
      expect(order.sublist(2), ['p2', 'p1']);
    });

    test('ties keep the original player order', () {
      final order = newGame().ranking.map((p) => p.id).toList();
      expect(order, ['p1', 'p2', 'p3']);
    });
  });
}
