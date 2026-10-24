import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';

ProviderContainer started() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(bankProvider.notifier)
      .start(
        players: const [
          Player(id: 'a', name: 'ผู้เล่น 1', color: 1),
          Player(id: 'b', name: 'ผู้เล่น 2', color: 2),
        ],
        startingCash: 1500,
        goAmount: 200,
      );
  return c;
}

void main() {
  test('no session until a game is started', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(bankProvider), isNull);
  });

  test('a transaction enables undo and sets a readable label', () {
    final c = started();
    c.read(bankProvider.notifier).passGo('a');
    final s = c.read(bankProvider)!;
    expect(s.game.balanceOf('a'), 1700);
    expect(s.undoAvailable, isTrue);
    expect(s.lastLabel, 'ผ่านจุดเริ่ม ผู้เล่น 1 +200');
  });

  test('undo reverts once and then is unavailable', () {
    final c = started();
    final n = c.read(bankProvider.notifier);
    n.passGo('a');
    n.receive('a', 100);
    n.undo();
    expect(c.read(bankProvider)!.game.balanceOf('a'), 1700);
    expect(c.read(bankProvider)!.undoAvailable, isFalse);
    n.undo();
    expect(c.read(bankProvider)!.game.balanceOf('a'), 1700);
  });

  test('pay refuses when the balance is too low and keeps state', () {
    final c = started();
    final r = c.read(bankProvider.notifier).pay('a', 2000);
    expect(r, isA<Insufficient>());
    expect((r as Insufficient).shortfall, 500);
    final s = c.read(bankProvider)!;
    expect(s.game.balanceOf('a'), 1500);
    expect(s.undoAvailable, isFalse);
  });

  test('recent amounts are newest first, unique and capped at 3', () {
    final c = started();
    final n = c.read(bankProvider.notifier);
    n.receive('a', 100);
    n.receive('a', 200);
    n.pay('a', 100);
    n.receive('a', 300);
    n.receive('a', 400);
    expect(c.read(bankProvider)!.recentAmounts, [400, 300, 100]);
  });

  test('passing go does not touch recent amounts', () {
    final c = started();
    c.read(bankProvider.notifier).passGo('a');
    expect(c.read(bankProvider)!.recentAmounts, isEmpty);
  });

  test('transfer moves money, labels it and is one undo step', () {
    final c = started();
    final n = c.read(bankProvider.notifier);
    final r = n.transfer('a', 'b', 500);
    expect(r, isA<Paid>());
    final s = c.read(bankProvider)!;
    expect(s.game.balanceOf('a'), 1000);
    expect(s.game.balanceOf('b'), 2000);
    expect(s.lastLabel, 'โอน 500 ผู้เล่น 1 → ผู้เล่น 2');
    n.undo();
    expect(c.read(bankProvider)!.game.balanceOf('b'), 1500);
  });

  test('a transfer the payer cannot cover changes nothing', () {
    final c = started();
    final r = c.read(bankProvider.notifier).transfer('a', 'b', 1600);
    expect((r as Insufficient).shortfall, 100);
    expect(c.read(bankProvider)!.game.history, isEmpty);
    expect(c.read(bankProvider)!.undoAvailable, isFalse);
  });

  test('payWithMortgage records mortgages and payment as one entry', () {
    final c = started();
    final n = c.read(bankProvider.notifier);
    final r = n.payWithMortgage(
      payerId: 'a',
      payeeId: 'b',
      amount: 1800,
      mortgages: [200, 150],
    );
    expect(r, isA<Paid>());
    final s = c.read(bankProvider)!;
    expect(s.game.history.length, 1);
    expect(s.game.balanceOf('a'), 1500 + 350 - 1800);
    expect(s.recentAmounts, [1800]);
    n.undo();
    expect(c.read(bankProvider)!.game.balanceOf('a'), 1500);
  });

  test('payWithMortgage that still falls short is refused', () {
    final c = started();
    final r = c
        .read(bankProvider.notifier)
        .payWithMortgage(
          payerId: 'a',
          payeeId: 'b',
          amount: 2000,
          mortgages: [100],
        );
    expect((r as Insufficient).shortfall, 400);
    expect(c.read(bankProvider)!.game.history, isEmpty);
  });

  test('declareBankrupt removes the player and can be undone', () {
    final c = started();
    final n = c.read(bankProvider.notifier);
    n.pay('a', 1300);
    n.declareBankrupt('a', owed: 1000, creditorId: 'b');
    var s = c.read(bankProvider)!;
    expect(s.game.isBankrupt('a'), isTrue);
    expect(s.game.balanceOf('b'), 2500);
    expect(s.lastLabel, 'ผู้เล่น 1 ล้มละลาย');
    expect(s.game.isOver, isTrue);
    n.undo();
    s = c.read(bankProvider)!;
    expect(s.game.isBankrupt('a'), isFalse);
    expect(s.game.balanceOf('a'), 200);
  });

  test('end drops the session', () {
    final c = started();
    c.read(bankProvider.notifier).end();
    expect(c.read(bankProvider), isNull);
  });
}
