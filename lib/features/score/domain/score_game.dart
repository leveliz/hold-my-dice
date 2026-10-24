import 'package:hold_my_dice/core/players/player.dart';

export 'package:hold_my_dice/core/players/player.dart' show Player;

/// Which end of the scoreboard wins.
enum WinMode { highest, lowest }

enum EndReason { allRoundsPlayed, targetReached, endedManually }

class RankedPlayer {
  const RankedPlayer(this.player, this.total, this.rank);

  final Player player;
  final int total;

  /// 1 for the best; players with the same total share a rank and the next
  /// rank is skipped (1, 1, 3).
  final int rank;
}

/// A round-by-round scoreboard. Immutable: every change returns a new game.
///
/// Each round holds at most one score per player. The last round is the
/// current one; earlier rounds can still be corrected until the game ends.
class ScoreGame {
  ScoreGame._(
    this.players,
    this.roundCount,
    this.winMode,
    this.targetScore,
    this._rounds,
    this.endReason,
  );

  factory ScoreGame.start({
    required List<Player> players,
    required int roundCount,
    WinMode winMode = WinMode.highest,
    int? targetScore,
  }) {
    if (players.length < 2) {
      throw ArgumentError('A game needs at least 2 players');
    }
    if (players.map((p) => p.id).toSet().length != players.length) {
      throw ArgumentError('Player ids must be unique');
    }
    if (roundCount < 1) throw ArgumentError('There must be at least 1 round');
    if (targetScore != null && targetScore <= 0) {
      throw ArgumentError('The target score must be positive');
    }
    return ScoreGame._(
      List.unmodifiable(players),
      roundCount,
      winMode,
      targetScore,
      const [{}],
      null,
    );
  }

  /// Restores a game saved with [toJson]. Throws if the data is not a game
  /// this version understands, so callers can discard a corrupt backup.
  factory ScoreGame.fromJson(Map<String, dynamic> json) {
    if (json['v'] != _jsonVersion) {
      throw FormatException('Unsupported game version: ${json['v']}');
    }
    final base = ScoreGame.start(
      players: [
        for (final p in json['players'] as List)
          Player.fromJson(p as Map<String, dynamic>),
      ],
      roundCount: json['roundCount'] as int,
      winMode: WinMode.values.byName(json['winMode'] as String),
      targetScore: json['targetScore'] as int?,
    );
    final ids = base.players.map((p) => p.id).toSet();
    final rounds = <Map<String, int>>[
      for (final r in json['rounds'] as List)
        {
          for (final e in (r as Map<String, dynamic>).entries)
            e.key: e.value as int,
        },
    ];
    if (rounds.isEmpty || rounds.length > base.roundCount) {
      throw const FormatException('Wrong number of rounds');
    }
    if (rounds.any((r) => !ids.containsAll(r.keys))) {
      throw const FormatException('A score belongs to an unknown player');
    }
    final reason = json['endReason'] as String?;
    return ScoreGame._(
      base.players,
      base.roundCount,
      base.winMode,
      base.targetScore,
      List<Map<String, int>>.unmodifiable([
        for (final r in rounds) Map<String, int>.unmodifiable(r),
      ]),
      reason == null ? null : EndReason.values.byName(reason),
    );
  }

  static const _jsonVersion = 1;

  final List<Player> players;
  final int roundCount;
  final WinMode winMode;
  final int? targetScore;
  final EndReason? endReason;
  final List<Map<String, int>> _rounds;

  bool get isOver => endReason != null;

  /// How many rounds have a row on the board (the current one included).
  int get roundsOnBoard => _rounds.length;

  /// Index of the round being played, from 0.
  int get currentRound => _rounds.length - 1;

  /// The round being played as people say it: 1 for the first.
  int get roundNumber => currentRound + 1;

  /// The score of [playerId] in [round] (from 0), or null if not entered.
  int? scoreOf(int round, String playerId) {
    _checkPlayer(playerId);
    if (round < 0 || round >= _rounds.length) return null;
    return _rounds[round][playerId];
  }

  /// Everything entered so far, including a round still in progress.
  int totalOf(String playerId) {
    _checkPlayer(playerId);
    return _rounds.fold(0, (sum, r) => sum + (r[playerId] ?? 0));
  }

  bool get hasAnyScore => _rounds.any((r) => r.isNotEmpty);

  /// Whether everyone has a score in the current round.
  bool get currentRoundComplete =>
      players.every((p) => _rounds.last.containsKey(p.id));

  bool get canFinishRound => !isOver && currentRoundComplete;

  /// Someone's total is at or beyond the target. The game still plays out the
  /// current round so everyone has had the same number of turns.
  bool get targetReached {
    final target = targetScore;
    return target != null && players.any((p) => totalOf(p.id) >= target);
  }

  /// Players best first by [winMode]; ties share a rank and keep seating order.
  List<RankedPlayer> get ranking {
    final entries = [
      for (final p in players) (player: p, total: totalOf(p.id)),
    ];
    final order = {for (final (i, p) in players.indexed) p.id: i};
    entries.sort((a, b) {
      final byScore = winMode == WinMode.highest
          ? b.total.compareTo(a.total)
          : a.total.compareTo(b.total);
      return byScore != 0
          ? byScore
          : order[a.player.id]!.compareTo(order[b.player.id]!);
    });
    final ranked = <RankedPlayer>[];
    for (final (i, e) in entries.indexed) {
      final tied = i > 0 && e.total == entries[i - 1].total;
      ranked.add(
        RankedPlayer(e.player, e.total, tied ? ranked[i - 1].rank : i + 1),
      );
    }
    return ranked;
  }

  /// Everyone sharing first place; empty until a score has been entered.
  List<Player> get leaders {
    if (!hasAnyScore) return const [];
    return [
      for (final r in ranking)
        if (r.rank == 1) r.player,
    ];
  }

  /// How far the leader is from the target score (zero or less once reached),
  /// or null when the game has no target.
  int? get distanceToTarget {
    final target = targetScore;
    if (target == null) return null;
    return target - ranking.first.total;
  }

  /// Enters or corrects a score. [round] counts from 0 and may be any round
  /// up to the current one.
  ScoreGame setScore({
    required int round,
    required String playerId,
    required int score,
  }) {
    _checkOpen();
    _checkPlayer(playerId);
    if (round < 0 || round > currentRound) {
      throw ArgumentError('Round $round is not on the board');
    }
    final rounds = [..._rounds];
    rounds[round] = {...rounds[round], playerId: score};
    return _copy(rounds: rounds);
  }

  /// Closes the current round. The game ends if that was the last round or if
  /// someone has reached the target; otherwise a new empty round begins.
  ScoreGame finishRound() {
    _checkOpen();
    if (!currentRoundComplete) {
      throw StateError('Every player needs a score before the round ends');
    }
    if (targetReached) return _copy(endReason: EndReason.targetReached);
    if (roundNumber >= roundCount) {
      return _copy(endReason: EndReason.allRoundsPlayed);
    }
    return _copy(rounds: [..._rounds, const {}]);
  }

  /// Ends the game now, keeping whatever has been entered.
  ScoreGame endNow() {
    _checkOpen();
    return _copy(endReason: EndReason.endedManually);
  }

  Map<String, dynamic> toJson() => {
    'v': _jsonVersion,
    'players': [for (final p in players) p.toJson()],
    'roundCount': roundCount,
    'winMode': winMode.name,
    'targetScore': targetScore,
    'rounds': [
      for (final r in _rounds) {for (final e in r.entries) e.key: e.value},
    ],
    'endReason': endReason?.name,
  };

  ScoreGame _copy({List<Map<String, int>>? rounds, EndReason? endReason}) {
    return ScoreGame._(
      players,
      roundCount,
      winMode,
      targetScore,
      List.unmodifiable(rounds ?? _rounds),
      endReason ?? this.endReason,
    );
  }

  void _checkOpen() {
    if (isOver) throw StateError('The game is over');
  }

  void _checkPlayer(String id) {
    if (!players.any((p) => p.id == id)) {
      throw ArgumentError('Unknown player: $id');
    }
  }
}
