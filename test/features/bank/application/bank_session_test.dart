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
}
