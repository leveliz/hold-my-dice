/// The two sides of a point-counting game. Red and blue are fixed identities:
/// names, colours and points travel with the side when the sides swap places.
enum Side {
  red,
  blue;

  Side get other => this == Side.red ? Side.blue : Side.red;
}

/// When a round is won. With no target a round never ends by itself.
class PointRules {
  PointRules({this.target, this.deuce = false, this.cap}) {
    if (target != null && target! <= 0) {
      throw ArgumentError('The target must be positive');
    }
    if (target == null && (deuce || cap != null)) {
      throw ArgumentError('Deuce and a cap need a target');
    }
    if (cap != null && !deuce) {
      throw ArgumentError('A cap only makes sense with deuce');
    }
    if (cap != null && cap! <= target!) {
      throw ArgumentError('The cap must be above the target');
    }
  }

  factory PointRules.fromJson(Map<String, dynamic> json) => PointRules(
    target: json['target'] as int?,
    deuce: json['deuce'] as bool,
    cap: json['cap'] as int?,
  );

  /// Points needed to win a round, or null to count with no end.
  final int? target;

  /// The winner must also lead by 2 points.
  final bool deuce;

  /// With deuce, the first side to reach this wins whatever the lead.
  final int? cap;

  /// The side that has won a round at [red] to [blue], or null if none yet.
  Side? winnerAt(int red, int blue) {
    final goal = target;
    if (goal == null) return null;
    final high = red > blue ? red : blue;
    final low = red > blue ? blue : red;
    final ahead = red > blue ? Side.red : (blue > red ? Side.blue : null);
    if (ahead == null) return null;
    final ceiling = cap;
    if (ceiling != null && high >= ceiling) return ahead;
    if (high < goal) return null;
    return deuce ? (high - low >= 2 ? ahead : null) : ahead;
  }

  Map<String, dynamic> toJson() => {
    'target': target,
    'deuce': deuce,
    'cap': cap,
  };
}

/// A finished round.
class RoundResult {
  const RoundResult(this.red, this.blue, this.winner);

  factory RoundResult.fromJson(Map<String, dynamic> json) => RoundResult(
    json['red'] as int,
    json['blue'] as int,
    _sideOrNull(json['winner'] as String?),
  );

  final int red;
  final int blue;

  /// Null when the round ended level.
  final Side? winner;

  int pointsOf(Side side) => side == Side.red ? red : blue;

  Map<String, dynamic> toJson() => {
    'red': red,
    'blue': blue,
    'winner': winner?.name,
  };
}

/// One change to the score, kept so it can be undone.
class PointEvent {
  const PointEvent(this.side, this.delta, this.servingBefore);

  factory PointEvent.fromJson(Map<String, dynamic> json) => PointEvent(
    Side.values.byName(json['side'] as String),
    json['delta'] as int,
    _sideOrNull(json['servingBefore'] as String?),
  );

  final Side side;
  final int delta;
  final Side? servingBefore;

  Map<String, dynamic> toJson() => {
    'side': side.name,
    'delta': delta,
    'servingBefore': servingBefore?.name,
  };
}

Side? _sideOrNull(String? name) =>
    name == null ? null : Side.values.byName(name);

/// A two-sided scoreboard for sports like badminton, table tennis or
/// volleyball. Immutable: every change returns a new game.
class PointGame {
  PointGame._({
    required this.rules,
    required this.redName,
    required this.blueName,
    required this.leftSide,
    required this.red,
    required this.blue,
    required this.serving,
    required this.events,
    required this.rounds,
    required this.betweenRounds,
    required this.isOver,
  });

  factory PointGame.start({
    String redName = 'แดง',
    String blueName = 'น้ำเงิน',
    PointRules? rules,
  }) => PointGame._(
    rules: rules ?? PointRules(),
    redName: _cleanName(redName, 'แดง'),
    blueName: _cleanName(blueName, 'น้ำเงิน'),
    leftSide: Side.red,
    red: 0,
    blue: 0,
    serving: null,
    events: const [],
    rounds: const [],
    betweenRounds: false,
    isOver: false,
  );

  /// Restores a game saved with [toJson]. Throws if the data is not a game
  /// this version understands, so callers can discard a corrupt backup.
  factory PointGame.fromJson(Map<String, dynamic> json) {
    if (json['v'] != _jsonVersion) {
      throw FormatException('Unsupported game version: ${json['v']}');
    }
    final red = json['red'] as int;
    final blue = json['blue'] as int;
    if (red < 0 || blue < 0) throw const FormatException('Negative points');
    return PointGame._(
      rules: PointRules.fromJson(json['rules'] as Map<String, dynamic>),
      redName: _cleanName(json['redName'] as String, 'แดง'),
      blueName: _cleanName(json['blueName'] as String, 'น้ำเงิน'),
      leftSide: Side.values.byName(json['leftSide'] as String),
      red: red,
      blue: blue,
      serving: _sideOrNull(json['serving'] as String?),
      events: List.unmodifiable([
        for (final e in json['events'] as List)
          PointEvent.fromJson(e as Map<String, dynamic>),
      ]),
      rounds: List.unmodifiable([
        for (final r in json['rounds'] as List)
          RoundResult.fromJson(r as Map<String, dynamic>),
      ]),
      betweenRounds: json['betweenRounds'] as bool,
      isOver: json['isOver'] as bool,
    );
  }

  static const _jsonVersion = 1;

  final PointRules rules;
  final String redName;
  final String blueName;

  /// Which side is on the left of the screen.
  final Side leftSide;
  final int red;
  final int blue;

  /// Who serves next; null until the first point or a choice.
  final Side? serving;
  final List<PointEvent> events;
  final List<RoundResult> rounds;

  /// The round was finished and the next one has not started.
  final bool betweenRounds;
  final bool isOver;

  Side get rightSide => leftSide.other;

  String nameOf(Side side) => side == Side.red ? redName : blueName;

  int pointsOf(Side side) => side == Side.red ? red : blue;

  /// Rounds recorded so far, not counting the one being played.
  int get roundsFinished => rounds.length;

  /// The round being played as people say it: 1 for the first.
  int get roundNumber => betweenRounds ? rounds.length : rounds.length + 1;

  int roundsWon(Side side) => rounds.where((r) => r.winner == side).length;

  /// The side that has won the current round by the rules, if any.
  Side? get roundWinner => rules.winnerAt(red, blue);

  bool get canUndo => !isOver && !betweenRounds && events.isNotEmpty;

  /// A round can be recorded once any point has been scored.
  bool get canFinishRound => !isOver && !betweenRounds && red + blue > 0;

  /// +1 for [side], who then serves.
  PointGame addPoint(Side side) {
    _checkPlaying();
    return _copy(
      red: side == Side.red ? red + 1 : red,
      blue: side == Side.blue ? blue + 1 : blue,
      serving: side,
      events: [...events, PointEvent(side, 1, serving)],
    );
  }

  /// -1 for [side], never below 0. The server does not change.
  PointGame removePoint(Side side) {
    _checkPlaying();
    if (pointsOf(side) == 0) return this;
    return _copy(
      red: side == Side.red ? red - 1 : red,
      blue: side == Side.blue ? blue - 1 : blue,
      events: [...events, PointEvent(side, -1, serving)],
    );
  }

  /// Takes back the latest change, including who was serving before it.
  PointGame undo() {
    _checkPlaying();
    if (events.isEmpty) throw StateError('Nothing to undo');
    final last = events.last;
    return _copy(
      red: last.side == Side.red ? red - last.delta : red,
      blue: last.side == Side.blue ? blue - last.delta : blue,
      serving: last.servingBefore,
      clearServing: last.servingBefore == null,
      events: events.sublist(0, events.length - 1),
    );
  }

  /// Chooses who serves, before the round gets going.
  PointGame chooseServer(Side side) {
    _checkPlaying();
    return _copy(serving: side);
  }

  /// Puts the teams on opposite sides of the screen; names, colours and points
  /// stay with their team.
  PointGame swapSides() {
    _checkOpen();
    return _copy(leftSide: leftSide.other);
  }

  PointGame rename(Side side, String name) {
    _checkOpen();
    final clean = _cleanName(name, side == Side.red ? 'แดง' : 'น้ำเงิน');
    return side == Side.red ? _copy(redName: clean) : _copy(blueName: clean);
  }

  /// Records the round: the winner by the rules, or else whoever has more
  /// points (null if level). Undo no longer reaches back into it.
  PointGame finishRound() {
    _checkPlaying();
    if (!canFinishRound) throw StateError('No point has been scored yet');
    return _copy(
      rounds: [...rounds, _currentResult()],
      betweenRounds: true,
      events: const [],
    );
  }

  /// Starts a fresh round at 0-0, optionally choosing who serves first.
  PointGame startNextRound({Side? firstServer}) {
    _checkOpen();
    if (!betweenRounds) throw StateError('The round is not finished');
    return _copy(
      red: 0,
      blue: 0,
      serving: firstServer,
      clearServing: firstServer == null,
      events: const [],
      betweenRounds: false,
    );
  }

  /// Sets the round being played back to 0-0 without recording it.
  PointGame reset() {
    _checkPlaying();
    return _copy(red: 0, blue: 0, clearServing: true, events: const []);
  }

  /// Ends the game. A round in progress counts only if the rules already
  /// decided it; otherwise its points are dropped.
  PointGame endGame() {
    _checkOpen();
    final decided = !betweenRounds && roundWinner != null;
    return _copy(
      rounds: decided ? [...rounds, _currentResult()] : rounds,
      betweenRounds: true,
      events: const [],
      isOver: true,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': _jsonVersion,
    'rules': rules.toJson(),
    'redName': redName,
    'blueName': blueName,
    'leftSide': leftSide.name,
    'red': red,
    'blue': blue,
    'serving': serving?.name,
    'events': [for (final e in events) e.toJson()],
    'rounds': [for (final r in rounds) r.toJson()],
    'betweenRounds': betweenRounds,
    'isOver': isOver,
  };

  RoundResult _currentResult() {
    final winner =
        roundWinner ??
        (red > blue ? Side.red : (blue > red ? Side.blue : null));
    return RoundResult(red, blue, winner);
  }

  PointGame _copy({
    PointRules? rules,
    String? redName,
    String? blueName,
    Side? leftSide,
    int? red,
    int? blue,
    Side? serving,
    bool clearServing = false,
    List<PointEvent>? events,
    List<RoundResult>? rounds,
    bool? betweenRounds,
    bool? isOver,
  }) {
    return PointGame._(
      rules: rules ?? this.rules,
      redName: redName ?? this.redName,
      blueName: blueName ?? this.blueName,
      leftSide: leftSide ?? this.leftSide,
      red: red ?? this.red,
      blue: blue ?? this.blue,
      serving: clearServing ? null : (serving ?? this.serving),
      events: List.unmodifiable(events ?? this.events),
      rounds: List.unmodifiable(rounds ?? this.rounds),
      betweenRounds: betweenRounds ?? this.betweenRounds,
      isOver: isOver ?? this.isOver,
    );
  }

  void _checkOpen() {
    if (isOver) throw StateError('The game is over');
  }

  /// Points can only change while a round is being played.
  void _checkPlaying() {
    _checkOpen();
    if (betweenRounds) throw StateError('Start the next round first');
  }
}

String _cleanName(String name, String fallback) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}
