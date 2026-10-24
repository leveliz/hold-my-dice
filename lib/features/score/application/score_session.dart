import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';

/// The Score Snitch game being played, backed up after every change so a
/// closed app can be resumed. Null when no game is open.
class ScoreNotifier extends Notifier<ScoreGame?> {
  @override
  ScoreGame? build() => null;

  ScoreGame get _game => state!;

  void start({
    required List<Player> players,
    required int roundCount,
    required WinMode winMode,
    int? targetScore,
  }) {
    state = ScoreGame.start(
      players: players,
      roundCount: roundCount,
      winMode: winMode,
      targetScore: targetScore,
    );
    _backUp();
  }

  /// Continues a game restored from the backup.
  void restore(ScoreGame game) => state = game;

  void setScore({
    required int round,
    required String playerId,
    required int score,
  }) {
    state = _game.setScore(round: round, playerId: playerId, score: score);
    _changed();
  }

  void finishRound() {
    state = _game.finishRound();
    _changed();
  }

  void endNow() {
    state = _game.endNow();
    _changed();
  }

  /// The game is over (or abandoned): drop it and its backup.
  void end() {
    state = null;
    unawaited(ref.read(scoreStorageProvider).clearGame());
  }

  void _changed() {
    _backUp();
    ref.read(hapticsProvider).transaction();
  }

  void _backUp() {
    unawaited(ref.read(scoreStorageProvider).saveGame(state!));
  }
}

final scoreProvider = NotifierProvider<ScoreNotifier, ScoreGame?>(
  ScoreNotifier.new,
);
