import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/standings.dart';

List<(String, int, bool)> flat(List<Standing> s) => [
  for (final e in s) (e.seat, e.rank, e.out),
];

void main() {
  group('standings', () {
    test('players still in are ranked by what they hold, most first', () {
      final s = standings(
        seats: ['p1', 'p2', 'p3'],
        balances: {'p1': 640, 'p2': 3420, 'p3': 1900},
        bankrupt: const [],
      );
      expect(flat(s), [('p2', 1, false), ('p3', 2, false), ('p1', 3, false)]);
      expect(s.first.balance, 3420);
    });

    test(
      'players with the same money share a rank, and the next rank skips',
      () {
        final s = standings(
          seats: ['p1', 'p2', 'p3', 'p4'],
          balances: {'p1': 1500, 'p2': 1500, 'p3': 900, 'p4': 2000},
          bankrupt: const [],
        );
        expect(flat(s), [
          ('p4', 1, false),
          ('p1', 2, false),
          ('p2', 2, false),
          ('p3', 4, false),
        ]);
      },
    );

    test('players who went out come after, the one who left last first', () {
      final s = standings(
        seats: ['p1', 'p2', 'p3', 'p4', 'p5'],
        balances: {'p1': 0, 'p2': 700, 'p3': 0, 'p4': 0, 'p5': 2500},
        bankrupt: ['p3', 'p1', 'p4'],
      );
      expect(flat(s), [
        ('p5', 1, false),
        ('p2', 2, false),
        ('p4', 3, true),
        ('p1', 4, true),
        ('p3', 5, true),
      ]);
    });

    test('a single player in the game wins', () {
      final s = standings(
        seats: ['p1', 'p2'],
        balances: {'p1': 5000, 'p2': 0},
        bankrupt: ['p2'],
      );
      expect(flat(s), [('p1', 1, false), ('p2', 2, true)]);
    });

    test('the money of the bank is not a player', () {
      final s = standings(
        seats: ['p1', 'p2'],
        balances: {'p1': 100, 'p2': 200, 'bank': 99999},
        bankrupt: const [],
      );
      expect(s.map((e) => e.seat), ['p2', 'p1']);
    });

    test('eight players, in seat order when the money is the same', () {
      final seats = [for (var i = 1; i <= 8; i++) 'p$i'];
      final s = standings(
        seats: seats,
        balances: {for (final p in seats) p: 1500},
        bankrupt: const [],
      );
      expect(s.map((e) => e.seat), seats);
      expect(s.map((e) => e.rank).toSet(), {1});
    });
  });
}
