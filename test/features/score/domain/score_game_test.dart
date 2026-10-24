import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';

List<Player> seats(int n) => [
  for (var i = 1; i <= n; i++)
    Player(id: 'p$i', name: 'ผู้เล่น $i', color: 0xFF000000 + i),
];

ScoreGame newGame({
  int players = 3,
  int rounds = 5,
  WinMode mode = WinMode.highest,
  int? target,
}) => ScoreGame.start(
  players: seats(players),
  roundCount: rounds,
  winMode: mode,
  targetScore: target,
);

/// Enters one score per player (in seating order) for [round].
ScoreGame fill(ScoreGame g, int round, List<int> scores) {
  var game = g;
  for (final (i, s) in scores.indexed) {
    game = game.setScore(round: round, playerId: 'p${i + 1}', score: s);
  }
  return game;
}

List<String> order(ScoreGame g) => g.ranking.map((r) => r.player.id).toList();

void main() {
  group('start', () {
    test('begins on round 1 with an empty board', () {
      final g = newGame();
      expect(g.currentRound, 0);
      expect(g.roundNumber, 1);
      expect(g.roundsOnBoard, 1);
      expect(g.isOver, isFalse);
      expect(g.hasAnyScore, isFalse);
      expect(g.totalOf('p1'), 0);
      expect(g.scoreOf(0, 'p1'), isNull);
    });

    test('needs at least 2 players', () {
      expect(() => newGame(players: 1), throwsArgumentError);
    });

    test('player ids must be unique', () {
      expect(
        () => ScoreGame.start(
          players: const [
            Player(id: 'a', name: 'A', color: 1),
            Player(id: 'a', name: 'B', color: 2),
          ],
          roundCount: 3,
        ),
        throwsArgumentError,
      );
    });

    test('needs at least one round', () {
      expect(() => newGame(rounds: 0), throwsArgumentError);
      expect(() => newGame(rounds: -2), throwsArgumentError);
    });

    test('a target, when given, must be positive', () {
      expect(() => newGame(target: 0), throwsArgumentError);
      expect(() => newGame(target: -5), throwsArgumentError);
      expect(newGame(target: 100).targetScore, 100);
      expect(newGame().targetScore, isNull);
    });
  });

  group('entering scores', () {
    test('stores one score per player per round', () {
      final g = newGame().setScore(round: 0, playerId: 'p2', score: 7);
      expect(g.scoreOf(0, 'p2'), 7);
      expect(g.scoreOf(0, 'p1'), isNull);
      expect(g.totalOf('p2'), 7);
    });

    test('a score can be replaced, zero and negative included', () {
      var g = newGame().setScore(round: 0, playerId: 'p1', score: 5);
      g = g.setScore(round: 0, playerId: 'p1', score: -3);
      expect(g.scoreOf(0, 'p1'), -3);
      g = g.setScore(round: 0, playerId: 'p1', score: 0);
      expect(g.scoreOf(0, 'p1'), 0);
      expect(g.currentRoundComplete, isFalse, reason: 'others have none');
    });

    test('does not change the game it was called on', () {
      final g = newGame();
      g.setScore(round: 0, playerId: 'p1', score: 9);
      expect(g.scoreOf(0, 'p1'), isNull);
    });

    test('unknown players and rounds not yet played are refused', () {
      final g = newGame();
      expect(
        () => g.setScore(round: 0, playerId: 'zzz', score: 1),
        throwsArgumentError,
      );
      expect(
        () => g.setScore(round: 1, playerId: 'p1', score: 1),
        throwsArgumentError,
      );
      expect(
        () => g.setScore(round: -1, playerId: 'p1', score: 1),
        throwsArgumentError,
      );
      expect(() => g.totalOf('zzz'), throwsArgumentError);
    });

    test('totals add up across rounds, including a round in progress', () {
      var g = fill(newGame(), 0, [3, 5, 1]).finishRound();
      g = g.setScore(round: 1, playerId: 'p1', score: 10);
      expect(g.totalOf('p1'), 13);
      expect(g.totalOf('p2'), 5);
    });
  });

  group('finishing a round', () {
    test('only when everyone has a score', () {
      var g = newGame();
      expect(g.canFinishRound, isFalse);
      g = fill(g, 0, [1, 2]);
      expect(g.canFinishRound, isFalse);
      expect(g.finishRound, throwsStateError);
      g = g.setScore(round: 0, playerId: 'p3', score: 0);
      expect(g.canFinishRound, isTrue);
    });

    test('moves on to a new empty round', () {
      final g = fill(newGame(), 0, [3, 5, 1]).finishRound();
      expect(g.roundNumber, 2);
      expect(g.roundsOnBoard, 2);
      expect(g.isOver, isFalse);
      expect(g.scoreOf(1, 'p1'), isNull);
      expect(g.canFinishRound, isFalse);
      expect(g.scoreOf(0, 'p2'), 5, reason: 'earlier rows are kept');
    });

    test('the last round ends the game and adds no empty row', () {
      var g = newGame(rounds: 2);
      g = fill(g, 0, [1, 1, 1]).finishRound();
      g = fill(g, 1, [2, 2, 2]).finishRound();
      expect(g.isOver, isTrue);
      expect(g.endReason, EndReason.allRoundsPlayed);
      expect(g.roundsOnBoard, 2);
    });

    test('a one-round game ends after its only round', () {
      final g = fill(newGame(rounds: 1), 0, [1, 2, 3]).finishRound();
      expect(g.endReason, EndReason.allRoundsPlayed);
    });
  });

  group('target score', () {
    test('reaching it mid-round does not end the game yet', () {
      var g = newGame(target: 50, rounds: 10);
      g = g.setScore(round: 0, playerId: 'p1', score: 60);
      expect(g.targetReached, isTrue);
      expect(g.isOver, isFalse);
      expect(g.canFinishRound, isFalse, reason: 'others still have to play');
    });

    test('it ends once that round is finished', () {
      var g = newGame(target: 50, rounds: 10);
      g = fill(g, 0, [60, 10, 20]).finishRound();
      expect(g.isOver, isTrue);
      expect(g.endReason, EndReason.targetReached);
    });

    test('reaching it exactly counts', () {
      final g = fill(newGame(target: 50), 0, [50, 0, 0]).finishRound();
      expect(g.endReason, EndReason.targetReached);
    });

    test('just short of it keeps playing', () {
      final g = fill(newGame(target: 50), 0, [49, 10, 0]).finishRound();
      expect(g.isOver, isFalse);
      expect(g.targetReached, isFalse);
    });

    test('totals over several rounds can reach it', () {
      var g = newGame(target: 30, rounds: 10);
      g = fill(g, 0, [10, 5, 5]).finishRound();
      g = fill(g, 1, [10, 5, 5]).finishRound();
      expect(g.isOver, isFalse);
      g = fill(g, 2, [10, 5, 5]).finishRound();
      expect(g.endReason, EndReason.targetReached);
    });

    test('in lowest-wins mode it is still the end of the game', () {
      var g = newGame(target: 100, mode: WinMode.lowest);
      g = fill(g, 0, [100, 20, 5]).finishRound();
      expect(g.endReason, EndReason.targetReached);
      expect(order(g).first, 'p3', reason: 'the lowest total wins');
      expect(order(g).last, 'p1');
    });

    test('with no target, high scores never end the game', () {
      final g = fill(newGame(rounds: 5), 0, [9999, 0, 0]).finishRound();
      expect(g.isOver, isFalse);
      expect(g.targetReached, isFalse);
    });

    test('hitting the target in the last round names the target', () {
      final g = fill(newGame(rounds: 1, target: 10), 0, [10, 0, 0]);
      expect(g.finishRound().endReason, EndReason.targetReached);
    });
  });

  group('ending early', () {
    test('keeps what was entered, including a half-filled round', () {
      var g = fill(newGame(), 0, [3, 5, 1]).finishRound();
      g = g.setScore(round: 1, playerId: 'p1', score: 4);
      g = g.endNow();
      expect(g.isOver, isTrue);
      expect(g.endReason, EndReason.endedManually);
      expect(g.totalOf('p1'), 7);
      expect(g.totalOf('p2'), 5);
    });

    test('a finished game cannot be changed', () {
      final g = fill(newGame(), 0, [1, 2, 3]).endNow();
      expect(
        () => g.setScore(round: 0, playerId: 'p1', score: 9),
        throwsStateError,
      );
      expect(g.finishRound, throwsStateError);
      expect(g.endNow, throwsStateError);
    });

    test('is possible right at the start', () {
      expect(newGame().endNow().isOver, isTrue);
    });
  });

  group('correcting an earlier round', () {
    test('totals and ranking follow the edit', () {
      var g = fill(newGame(), 0, [10, 5, 1]).finishRound();
      g = fill(g, 1, [0, 0, 0]).finishRound();
      expect(order(g), ['p1', 'p2', 'p3']);
      g = g.setScore(round: 0, playerId: 'p3', score: 50);
      expect(g.totalOf('p3'), 50);
      expect(order(g), ['p3', 'p1', 'p2']);
    });

    test('an edit can bring someone to the target, ending it at round end', () {
      var g = newGame(target: 100, rounds: 10);
      g = fill(g, 0, [10, 5, 1]).finishRound();
      g = g.setScore(round: 0, playerId: 'p2', score: 120);
      expect(g.targetReached, isTrue);
      expect(g.isOver, isFalse);
      g = fill(g, 1, [0, 0, 0]).finishRound();
      expect(g.endReason, EndReason.targetReached);
    });
  });

  group('ranking', () {
    test('highest total first in highest-wins mode', () {
      final g = fill(newGame(), 0, [3, 9, 6]);
      expect(order(g), ['p2', 'p3', 'p1']);
      expect(g.ranking.map((r) => r.rank), [1, 2, 3]);
      expect(g.ranking.map((r) => r.total), [9, 6, 3]);
    });

    test('lowest total first in lowest-wins mode', () {
      final g = fill(newGame(mode: WinMode.lowest), 0, [3, 9, 6]);
      expect(order(g), ['p1', 'p3', 'p2']);
    });

    test('ties share a rank and the next rank is skipped', () {
      final g = fill(newGame(players: 4), 0, [5, 9, 5, 1]);
      expect(order(g), ['p2', 'p1', 'p3', 'p4']);
      expect(g.ranking.map((r) => r.rank), [1, 2, 2, 4]);
    });

    test('everyone tied is everyone first', () {
      final g = fill(newGame(), 0, [4, 4, 4]);
      expect(g.ranking.map((r) => r.rank), [1, 1, 1]);
      expect(order(g), ['p1', 'p2', 'p3'], reason: 'seating order');
    });

    test('negative totals rank below zero', () {
      final g = fill(newGame(), 0, [-5, 0, 3]);
      expect(order(g), ['p3', 'p2', 'p1']);
    });

    test('works while a round is half filled', () {
      final g = newGame().setScore(round: 0, playerId: 'p3', score: 8);
      expect(order(g).first, 'p3');
    });
  });

  group('leaders', () {
    test('nobody leads before a score is entered', () {
      expect(newGame().leaders, isEmpty);
    });

    test('the best total leads', () {
      final g = fill(newGame(), 0, [3, 9, 6]);
      expect(g.leaders.map((p) => p.id), ['p2']);
    });

    test('tied players all lead', () {
      final g = fill(newGame(), 0, [9, 9, 1]);
      expect(g.leaders.map((p) => p.id), ['p1', 'p2']);
    });

    test('in lowest-wins mode the lowest leads', () {
      final g = fill(newGame(mode: WinMode.lowest), 0, [3, 9, 6]);
      expect(g.leaders.map((p) => p.id), ['p1']);
    });

    test('a single score is enough to have a leader', () {
      final g = newGame().setScore(round: 0, playerId: 'p2', score: 0);
      expect(g.leaders, isNotEmpty);
    });
  });

  group('distance to the target', () {
    test('is null when there is no target', () {
      expect(fill(newGame(), 0, [5, 6, 7]).distanceToTarget, isNull);
    });

    test('is how far the leader still has to go', () {
      final g = fill(newGame(target: 100), 0, [30, 45, 10]);
      expect(g.distanceToTarget, 55);
    });

    test('is the full target before anything is scored', () {
      expect(newGame(target: 100).distanceToTarget, 100);
    });

    test('is zero or less once reached', () {
      expect(fill(newGame(target: 50), 0, [50, 0, 0]).distanceToTarget, 0);
      expect(fill(newGame(target: 50), 0, [70, 0, 0]).distanceToTarget, -20);
    });

    test('in lowest-wins mode it measures the lowest player', () {
      final g = fill(newGame(target: 100, mode: WinMode.lowest), 0, [
        30,
        45,
        10,
      ]);
      expect(g.distanceToTarget, 90);
    });
  });

  group('saving', () {
    ScoreGame roundTrip(ScoreGame g) => ScoreGame.fromJson(
      jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>,
    );

    test('a game in progress survives a JSON round trip', () {
      var g = newGame(target: 80, mode: WinMode.lowest, rounds: 6);
      g = fill(g, 0, [3, -5, 1]).finishRound();
      g = g.setScore(round: 1, playerId: 'p2', score: 7);
      final copy = roundTrip(g);

      expect(copy.players.map((p) => p.name), g.players.map((p) => p.name));
      expect(copy.roundCount, 6);
      expect(copy.winMode, WinMode.lowest);
      expect(copy.targetScore, 80);
      expect(copy.roundsOnBoard, 2);
      for (final p in g.players) {
        expect(copy.totalOf(p.id), g.totalOf(p.id));
        expect(copy.scoreOf(0, p.id), g.scoreOf(0, p.id));
        expect(copy.scoreOf(1, p.id), g.scoreOf(1, p.id));
      }
      expect(order(copy), order(g));
      expect(copy.isOver, isFalse);
    });

    test('a finished game keeps its end reason', () {
      final g = fill(newGame(target: 10), 0, [10, 0, 0]).finishRound();
      expect(roundTrip(g).endReason, EndReason.targetReached);
      expect(roundTrip(newGame().endNow()).endReason, EndReason.endedManually);
    });

    test('a restored game can be played on', () {
      final copy = roundTrip(fill(newGame(), 0, [1, 2, 3]));
      final next = copy.finishRound();
      expect(next.roundNumber, 2);
    });

    test('a game with no target stores null', () {
      expect(roundTrip(newGame()).targetScore, isNull);
    });

    test('an unknown version is refused', () {
      final json = newGame().toJson()..['v'] = 99;
      expect(() => ScoreGame.fromJson(json), throwsFormatException);
    });

    test('a score for an unknown player is refused', () {
      final json =
          jsonDecode(jsonEncode(newGame().toJson())) as Map<String, dynamic>;
      (json['rounds'] as List)[0] = {'ghost': 5};
      expect(() => ScoreGame.fromJson(json), throwsFormatException);
    });

    test('more rounds than the game has is refused', () {
      final json =
          jsonDecode(jsonEncode(newGame(rounds: 1).toJson()))
              as Map<String, dynamic>;
      (json['rounds'] as List).add(<String, dynamic>{});
      expect(() => ScoreGame.fromJson(json), throwsFormatException);
    });

    test('no rounds at all is refused', () {
      final json =
          jsonDecode(jsonEncode(newGame().toJson())) as Map<String, dynamic>;
      json['rounds'] = [];
      expect(() => ScoreGame.fromJson(json), throwsFormatException);
    });

    test('an unknown win mode or end reason is refused', () {
      final a =
          jsonDecode(jsonEncode(newGame().toJson())) as Map<String, dynamic>;
      a['winMode'] = 'middle';
      expect(() => ScoreGame.fromJson(a), throwsArgumentError);
      final b =
          jsonDecode(jsonEncode(newGame().toJson())) as Map<String, dynamic>;
      b['endReason'] = 'boredom';
      expect(() => ScoreGame.fromJson(b), throwsArgumentError);
    });

    test('a missing field is refused', () {
      final json =
          jsonDecode(jsonEncode(newGame().toJson())) as Map<String, dynamic>;
      json.remove('roundCount');
      expect(() => ScoreGame.fromJson(json), throwsA(anything));
    });
  });
}
