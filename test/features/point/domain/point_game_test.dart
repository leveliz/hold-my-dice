import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';

PointGame newGame({int? target, bool deuce = false, int? cap}) =>
    PointGame.start(
      rules: PointRules(target: target, deuce: deuce, cap: cap),
    );

/// Scores [red] points for red and [blue] for blue (red's first).
PointGame score(PointGame g, int red, int blue) {
  var game = g;
  for (var i = 0; i < red; i++) {
    game = game.addPoint(Side.red);
  }
  for (var i = 0; i < blue; i++) {
    game = game.addPoint(Side.blue);
  }
  return game;
}

void main() {
  group('PointRules', () {
    test('rejects impossible settings', () {
      expect(() => PointRules(target: 0), throwsArgumentError);
      expect(() => PointRules(target: -3), throwsArgumentError);
      expect(() => PointRules(deuce: true), throwsArgumentError);
      expect(() => PointRules(cap: 30), throwsArgumentError);
      expect(() => PointRules(target: 21, cap: 30), throwsArgumentError);
      expect(
        () => PointRules(target: 21, deuce: true, cap: 21),
        throwsArgumentError,
      );
      expect(
        () => PointRules(target: 21, deuce: true, cap: 15),
        throwsArgumentError,
      );
    });

    test('with no target nobody ever wins a round', () {
      final r = PointRules();
      expect(r.winnerAt(0, 0), isNull);
      expect(r.winnerAt(500, 3), isNull);
    });

    test('plain target: first to reach it wins', () {
      final r = PointRules(target: 21);
      expect(r.winnerAt(20, 10), isNull);
      expect(r.winnerAt(21, 10), Side.red);
      expect(r.winnerAt(10, 21), Side.blue);
      expect(r.winnerAt(21, 20), Side.red, reason: 'no lead needed');
      expect(r.winnerAt(25, 10), Side.red, reason: 'kept scoring past it');
    });

    test('level at or past the target has no winner', () {
      expect(PointRules(target: 21).winnerAt(21, 21), isNull);
      expect(PointRules(target: 21, deuce: true).winnerAt(22, 22), isNull);
    });

    test('deuce: the target is not enough without a 2-point lead', () {
      final r = PointRules(target: 21, deuce: true);
      expect(r.winnerAt(21, 20), isNull);
      expect(r.winnerAt(21, 19), Side.red);
      expect(r.winnerAt(22, 20), Side.red);
      expect(r.winnerAt(29, 29), isNull);
      expect(r.winnerAt(30, 28), Side.red);
      expect(r.winnerAt(31, 30), isNull);
      expect(r.winnerAt(32, 30), Side.red);
      expect(r.winnerAt(20, 22), Side.blue);
      expect(r.winnerAt(19, 21), Side.blue);
    });

    test('deuce keeps going for ever when there is no cap', () {
      final r = PointRules(target: 21, deuce: true);
      expect(r.winnerAt(99, 98), isNull);
      expect(r.winnerAt(100, 98), Side.red);
    });

    test('a cap ends a deuce round whatever the lead', () {
      final r = PointRules(target: 21, deuce: true, cap: 30);
      expect(r.winnerAt(29, 29), isNull);
      expect(r.winnerAt(30, 29), Side.red);
      expect(r.winnerAt(29, 30), Side.blue);
      expect(r.winnerAt(30, 28), Side.red);
      expect(r.winnerAt(29, 28), isNull);
    });
  });

  group('a new game', () {
    test('starts 0-0 with default names, red on the left, nobody serving', () {
      final g = PointGame.start();
      expect(g.redName, 'แดง');
      expect(g.blueName, 'น้ำเงิน');
      expect(g.leftSide, Side.red);
      expect(g.rightSide, Side.blue);
      expect(g.red, 0);
      expect(g.blue, 0);
      expect(g.serving, isNull);
      expect(g.roundNumber, 1);
      expect(g.rounds, isEmpty);
      expect(g.isOver, isFalse);
      expect(g.canUndo, isFalse);
      expect(g.canFinishRound, isFalse);
    });

    test('team names are trimmed and blank ones use the default', () {
      final g = PointGame.start(redName: '  ต้น ', blueName: '   ');
      expect(g.redName, 'ต้น');
      expect(g.blueName, 'น้ำเงิน');
    });
  });

  group('adding and removing points', () {
    test('+1 goes to the side tapped and that side serves', () {
      final g = PointGame.start().addPoint(Side.blue);
      expect(g.blue, 1);
      expect(g.red, 0);
      expect(g.serving, Side.blue);
      final next = g.addPoint(Side.red);
      expect(next.serving, Side.red);
      expect(next.pointsOf(Side.red), 1);
    });

    test('does not change the game it was called on', () {
      final g = PointGame.start();
      g.addPoint(Side.red);
      expect(g.red, 0);
      expect(g.events, isEmpty);
    });

    test('-1 lowers that side and leaves the server alone', () {
      var g = score(PointGame.start(), 3, 2);
      expect(g.serving, Side.blue);
      g = g.removePoint(Side.red);
      expect(g.red, 2);
      expect(g.serving, Side.blue);
      // Removing from the serving side itself changes nothing either.
      g = g.removePoint(Side.blue);
      expect(g.blue, 1);
      expect(g.serving, Side.blue);
    });

    test('never goes below zero and records nothing then', () {
      final g = PointGame.start();
      final same = g.removePoint(Side.red);
      expect(same.red, 0);
      expect(same.events, isEmpty);
      final one = g.addPoint(Side.red).removePoint(Side.blue);
      expect(one.blue, 0);
      expect(one.events.length, 1);
    });

    test('points keep counting past the target', () {
      final g = score(newGame(target: 5), 8, 0);
      expect(g.red, 8);
      expect(g.roundWinner, Side.red);
    });
  });

  group('undo', () {
    test('steps back through several changes', () {
      var g = score(PointGame.start(), 2, 1);
      g = g.removePoint(Side.red);
      expect([g.red, g.blue], [1, 1]);
      g = g.undo();
      expect([g.red, g.blue], [2, 1], reason: 'the -1 is undone');
      g = g.undo();
      expect([g.red, g.blue], [2, 0]);
      g = g.undo();
      expect([g.red, g.blue], [1, 0]);
      g = g.undo();
      expect([g.red, g.blue], [0, 0]);
      expect(g.canUndo, isFalse);
    });

    test('gives the server back too', () {
      var g = PointGame.start().chooseServer(Side.red);
      g = g.addPoint(Side.blue);
      expect(g.serving, Side.blue);
      g = g.undo();
      expect(g.serving, Side.red);
    });

    test('goes back to nobody serving when nobody was', () {
      final g = PointGame.start().addPoint(Side.red).undo();
      expect(g.serving, isNull);
      expect(g.red, 0);
    });

    test('undoing a -1 gives the point back', () {
      final g = score(PointGame.start(), 3, 0).removePoint(Side.red).undo();
      expect(g.red, 3);
    });

    test('cannot undo with nothing to undo', () {
      expect(PointGame.start().undo, throwsStateError);
    });

    test('works without limit inside a round', () {
      var g = PointGame.start();
      for (var i = 0; i < 40; i++) {
        g = g.addPoint(i.isEven ? Side.red : Side.blue);
      }
      for (var i = 0; i < 40; i++) {
        g = g.undo();
      }
      expect([g.red, g.blue], [0, 0]);
    });
  });

  group('serving', () {
    test('a side can be chosen before any point', () {
      final g = PointGame.start().chooseServer(Side.blue);
      expect(g.serving, Side.blue);
      expect(g.red + g.blue, 0);
    });

    test('after that the latest scorer serves', () {
      var g = PointGame.start().chooseServer(Side.blue);
      g = g.addPoint(Side.red);
      expect(g.serving, Side.red);
      g = g.addPoint(Side.red);
      expect(g.serving, Side.red);
      g = g.addPoint(Side.blue);
      expect(g.serving, Side.blue);
    });

    test('choosing a server is not an undo step', () {
      final g = PointGame.start().chooseServer(Side.red);
      expect(g.canUndo, isFalse);
    });
  });

  group('swapping sides', () {
    test('flips left and right', () {
      final g = PointGame.start().swapSides();
      expect(g.leftSide, Side.blue);
      expect(g.rightSide, Side.red);
      expect(g.swapSides().leftSide, Side.red);
    });

    test('names and points stay with their team', () {
      var g = score(PointGame.start(redName: 'ต้น', blueName: 'ใบ'), 4, 7);
      g = g.swapSides();
      expect(g.nameOf(Side.red), 'ต้น');
      expect(g.pointsOf(Side.red), 4);
      expect(g.nameOf(g.leftSide), 'ใบ');
      expect(g.pointsOf(g.leftSide), 7);
      expect(g.serving, Side.blue);
    });

    test('does not disturb undo', () {
      final g = score(PointGame.start(), 2, 0).swapSides().undo();
      expect(g.red, 1);
      expect(g.leftSide, Side.blue, reason: 'the swap itself stays');
    });

    test('is allowed between rounds', () {
      final g = score(PointGame.start(), 1, 0).finishRound().swapSides();
      expect(g.leftSide, Side.blue);
    });
  });

  group('names', () {
    test('can be changed at any time', () {
      var g = score(PointGame.start(), 3, 3);
      g = g.rename(Side.red, 'ทีมเหย้า').rename(Side.blue, ' ทีมเยือน ');
      expect(g.redName, 'ทีมเหย้า');
      expect(g.blueName, 'ทีมเยือน');
      expect(g.red, 3);
    });

    test('a blank name falls back to the default', () {
      final g = PointGame.start(redName: 'ต้น').rename(Side.red, '  ');
      expect(g.redName, 'แดง');
      expect(g.rename(Side.blue, '').blueName, 'น้ำเงิน');
    });
  });

  group('round winner', () {
    test('follows the rules and updates as points change', () {
      var g = score(newGame(target: 21, deuce: true), 21, 20);
      expect(g.roundWinner, isNull);
      g = g.addPoint(Side.red);
      expect(g.roundWinner, Side.red);
      g = g.removePoint(Side.red);
      expect(g.roundWinner, isNull);
    });

    test('the round does not end by itself', () {
      final g = score(newGame(target: 5), 5, 0);
      expect(g.roundWinner, Side.red);
      expect(g.betweenRounds, isFalse);
      expect(g.rounds, isEmpty);
      expect(g.addPoint(Side.blue).blue, 1, reason: 'a wrong tap can be fixed');
    });

    test('a cap decides the round', () {
      final g = score(
        newGame(target: 5, deuce: true, cap: 8),
        7,
        7,
      ).addPoint(Side.blue);
      expect(g.roundWinner, Side.blue);
    });
  });

  group('finishing a round', () {
    test('needs a point to have been scored', () {
      expect(PointGame.start().finishRound, throwsStateError);
      expect(score(PointGame.start(), 1, 0).canFinishRound, isTrue);
    });

    test('records the winner decided by the rules', () {
      final g = score(newGame(target: 21), 21, 14).finishRound();
      expect(g.rounds.single.red, 21);
      expect(g.rounds.single.blue, 14);
      expect(g.rounds.single.winner, Side.red);
      expect(g.roundsWon(Side.red), 1);
      expect(g.roundsWon(Side.blue), 0);
      expect(g.betweenRounds, isTrue);
    });

    test('with no decision it records whoever has more points', () {
      final g = score(newGame(target: 21), 5, 9).finishRound();
      expect(g.rounds.single.winner, Side.blue);
      final h = score(PointGame.start(), 7, 3).finishRound();
      expect(h.rounds.single.winner, Side.red);
    });

    test('a level round has no winner', () {
      final g = score(PointGame.start(), 4, 4).finishRound();
      expect(g.rounds.single.winner, isNull);
      expect(g.roundsWon(Side.red), 0);
      expect(g.roundsWon(Side.blue), 0);
    });

    test('the board keeps the final score until the next round starts', () {
      final g = score(newGame(target: 5), 5, 2).finishRound();
      expect([g.red, g.blue], [5, 2]);
    });

    test('points can no longer change, and undo does not reach back', () {
      final g = score(newGame(target: 5), 5, 2).finishRound();
      expect(g.canUndo, isFalse);
      expect(() => g.addPoint(Side.red), throwsStateError);
      expect(() => g.removePoint(Side.red), throwsStateError);
      expect(g.undo, throwsStateError);
      expect(() => g.chooseServer(Side.red), throwsStateError);
      expect(g.reset, throwsStateError);
      expect(g.finishRound, throwsStateError);
    });

    test('the round number stays until the next round starts', () {
      var g = score(PointGame.start(), 3, 1);
      expect(g.roundNumber, 1);
      g = g.finishRound();
      expect(g.roundNumber, 1);
      g = g.startNextRound();
      expect(g.roundNumber, 2);
    });
  });

  group('starting the next round', () {
    test('resets the points and clears undo', () {
      final g = score(PointGame.start(), 3, 1).finishRound().startNextRound();
      expect([g.red, g.blue], [0, 0]);
      expect(g.canUndo, isFalse);
      expect(g.betweenRounds, isFalse);
      expect(g.serving, isNull);
      expect(g.rounds.length, 1);
    });

    test('can choose who serves first', () {
      final g = score(
        PointGame.start(),
        3,
        1,
      ).finishRound().startNextRound(firstServer: Side.blue);
      expect(g.serving, Side.blue);
    });

    test('keeps names, sides and the rules', () {
      var g = newGame(target: 21, deuce: true, cap: 30).rename(Side.red, 'ต้น');
      g = score(g, 21, 5).swapSides().finishRound().startNextRound();
      expect(g.redName, 'ต้น');
      expect(g.leftSide, Side.blue);
      expect(g.rules.cap, 30);
    });

    test('only after a round was finished', () {
      expect(PointGame.start().startNextRound, throwsStateError);
      expect(score(PointGame.start(), 1, 0).startNextRound, throwsStateError);
    });

    test('rounds add up over a match', () {
      var g = newGame(target: 5);
      g = score(g, 5, 2).finishRound().startNextRound();
      g = score(g, 1, 5).finishRound().startNextRound();
      g = score(g, 5, 0).finishRound();
      expect(g.rounds.length, 3);
      expect(g.roundsWon(Side.red), 2);
      expect(g.roundsWon(Side.blue), 1);
      expect(g.rounds.map((r) => r.winner), [Side.red, Side.blue, Side.red]);
    });
  });

  group('reset', () {
    test('sets the round back to 0-0 without recording it', () {
      final g = score(PointGame.start(), 4, 6).reset();
      expect([g.red, g.blue], [0, 0]);
      expect(g.serving, isNull);
      expect(g.canUndo, isFalse);
      expect(g.rounds, isEmpty);
      expect(g.roundNumber, 1);
    });

    test('leaves finished rounds alone', () {
      final g = score(
        PointGame.start(),
        3,
        1,
      ).finishRound().startNextRound().addPoint(Side.red).reset();
      expect(g.rounds.length, 1);
      expect(g.roundNumber, 2);
    });
  });

  group('ending the game', () {
    test('keeps a round the rules already decided', () {
      final g = score(newGame(target: 21), 21, 9).endGame();
      expect(g.isOver, isTrue);
      expect(g.rounds.single.winner, Side.red);
      expect(g.roundsWon(Side.red), 1);
    });

    test('drops an undecided round in progress', () {
      final g = score(newGame(target: 21), 12, 9).endGame();
      expect(g.isOver, isTrue);
      expect(g.rounds, isEmpty);
    });

    test('with no target a round in progress is dropped too', () {
      expect(score(PointGame.start(), 12, 9).endGame().rounds, isEmpty);
    });

    test('does not record the round twice when it was already finished', () {
      final g = score(newGame(target: 5), 5, 1).finishRound().endGame();
      expect(g.rounds.length, 1);
    });

    test('can end between rounds and right at the start', () {
      expect(PointGame.start().endGame().isOver, isTrue);
      final g = score(PointGame.start(), 1, 0).finishRound().startNextRound();
      expect(g.endGame().rounds.length, 1);
    });

    test('nothing changes afterwards', () {
      final g = score(PointGame.start(), 1, 0).endGame();
      expect(() => g.addPoint(Side.red), throwsStateError);
      expect(g.undo, throwsStateError);
      expect(g.swapSides, throwsStateError);
      expect(() => g.rename(Side.red, 'x'), throwsStateError);
      expect(g.endGame, throwsStateError);
      expect(g.canUndo, isFalse);
    });
  });

  group('saving', () {
    PointGame roundTrip(PointGame g) => PointGame.fromJson(
      jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>,
    );

    test('a game in progress survives, undo history included', () {
      var g = newGame(target: 21, deuce: true, cap: 30);
      g = g.rename(Side.red, 'ต้น').rename(Side.blue, 'ใบ');
      g = score(g, 21, 15).finishRound().startNextRound(firstServer: Side.blue);
      g = score(g, 3, 2).swapSides();
      final copy = roundTrip(g);

      expect(copy.redName, 'ต้น');
      expect(copy.blueName, 'ใบ');
      expect(copy.leftSide, Side.blue);
      expect([copy.red, copy.blue], [3, 2]);
      expect(copy.serving, Side.blue);
      expect(copy.rounds.single.red, 21);
      expect(copy.rounds.single.winner, Side.red);
      expect(copy.rules.target, 21);
      expect(copy.rules.deuce, isTrue);
      expect(copy.rules.cap, 30);
      expect(copy.roundNumber, 2);
      expect(copy.canUndo, isTrue);
      final undone = copy.undo();
      expect([undone.red, undone.blue], [3, 1]);
    });

    test('between rounds and after the end are kept', () {
      final between = score(PointGame.start(), 2, 1).finishRound();
      expect(roundTrip(between).betweenRounds, isTrue);
      expect(roundTrip(between).canUndo, isFalse);
      expect(roundTrip(PointGame.start().endGame()).isOver, isTrue);
    });

    test('no target is stored as null', () {
      final copy = roundTrip(PointGame.start());
      expect(copy.rules.target, isNull);
      expect(copy.rules.deuce, isFalse);
      expect(copy.rules.cap, isNull);
    });

    test('a restored game can be played on', () {
      final copy = roundTrip(score(PointGame.start(), 2, 2));
      expect(copy.addPoint(Side.red).red, 3);
    });

    test('an unknown version is refused', () {
      final json = PointGame.start().toJson()..['v'] = 99;
      expect(() => PointGame.fromJson(json), throwsFormatException);
    });

    test('negative points are refused', () {
      final json = PointGame.start().toJson()..['red'] = -1;
      expect(() => PointGame.fromJson(json), throwsFormatException);
    });

    test('an unknown side is refused', () {
      final json = PointGame.start().toJson()..['leftSide'] = 'green';
      expect(() => PointGame.fromJson(json), throwsArgumentError);
    });

    test('rules that make no sense are refused', () {
      final json = PointGame.start().toJson();
      (json['rules'] as Map<String, dynamic>)['cap'] = 30;
      expect(() => PointGame.fromJson(json), throwsArgumentError);
    });

    test('a missing field is refused', () {
      final json = PointGame.start().toJson()..remove('rounds');
      expect(() => PointGame.fromJson(json), throwsA(anything));
    });
  });
}
