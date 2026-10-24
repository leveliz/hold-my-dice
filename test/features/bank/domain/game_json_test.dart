import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';

GameState paid(PayResult r) => (r as Paid).state;

GameState richGame() {
  var g = GameState.start(
    players: const [
      Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
      Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
      Player(id: 'p3', name: 'ฟ้า', color: 0xFFE8920C),
    ],
    startingCash: 1500,
    goAmount: 200,
  );
  g = g.passGo('p1');
  g = g.receiveFromBank('p2', 300);
  g = g.mortgage('p3', 60);
  g = paid(
    g.payWithMortgage(
      payerId: 'p1',
      payeeId: 'p2',
      amount: 2000,
      mortgages: [200, 150],
    ),
  );
  g = paid(g.transfer('p3', 'p2', 100));
  g = paid(g.payBank('p3', 1400));
  return g.declareBankrupt('p3', owed: 500, creditorId: 'p1');
}

GameState roundTrip(GameState g) => GameState.fromJson(
  jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>,
);

void main() {
  test('a game with every kind of entry survives a JSON round trip', () {
    final original = richGame();
    final copy = roundTrip(original);

    expect(copy.players.map((p) => p.name), ['ต้น', 'ใบ', 'ฟ้า']);
    expect(copy.players.map((p) => p.color), [
      0xFF3D5AFE,
      0xFF2E9E57,
      0xFFE8920C,
    ]);
    expect(copy.startingCash, 1500);
    expect(copy.goAmount, 200);
    expect(copy.history.length, original.history.length);
    for (final p in original.players) {
      expect(copy.balanceOf(p.id), original.balanceOf(p.id), reason: p.id);
      expect(copy.isBankrupt(p.id), original.isBankrupt(p.id), reason: p.id);
    }
    expect(copy.ranking.map((p) => p.id), original.ranking.map((p) => p.id));
    expect(copy.isOver, original.isOver);
  });

  test('entries keep their transactions and types', () {
    final copy = roundTrip(richGame());
    final mortgageEntry = copy.history[3];
    expect(mortgageEntry.transactions.length, 3);
    expect(mortgageEntry.transactions.first.type, TransactionType.mortgage);
    expect(mortgageEntry.transactions.last.type, TransactionType.transfer);
    expect(copy.history.last.bankruptPlayerId, 'p3');
  });

  test('a restored game can be undone and played on', () {
    final copy = roundTrip(richGame());
    final undone = copy.undo();
    expect(undone.isBankrupt('p3'), isFalse);
    final next = copy.passGo('p1');
    expect(next.balanceOf('p1'), copy.balanceOf('p1') + 200);
  });

  test('a fresh game round-trips too', () {
    final g = GameState.start(
      players: const [
        Player(id: 'a', name: 'A', color: 1),
        Player(id: 'b', name: 'B', color: 2),
      ],
      startingCash: 100,
      goAmount: 10,
    );
    final copy = roundTrip(g);
    expect(copy.history, isEmpty);
    expect(copy.balanceOf('a'), 100);
  });

  test('an unknown version is refused', () {
    final json = richGame().toJson()..['v'] = 99;
    expect(() => GameState.fromJson(json), throwsFormatException);
  });

  test('an unknown transaction type is refused', () {
    final json =
        jsonDecode(jsonEncode(richGame().toJson())) as Map<String, dynamic>;
    ((json['history'] as List).first as Map)['transactions'][0]['type'] =
        'teleport';
    expect(() => GameState.fromJson(json), throwsArgumentError);
  });

  test('a missing field is refused instead of loading half a game', () {
    final json =
        jsonDecode(jsonEncode(richGame().toJson())) as Map<String, dynamic>;
    json.remove('goAmount');
    expect(() => GameState.fromJson(json), throwsA(anything));
  });

  test('fewer than two players is refused', () {
    final json =
        jsonDecode(jsonEncode(richGame().toJson())) as Map<String, dynamic>;
    json['players'] = [(json['players'] as List).first];
    expect(() => GameState.fromJson(json), throwsArgumentError);
  });
}
