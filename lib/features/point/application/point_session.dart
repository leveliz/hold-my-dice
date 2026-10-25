import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';

/// The Point Blank game being played, backed up after every change so a
/// closed app can be resumed. Null when no game is open.
class PointNotifier extends Notifier<PointGame?> {
  @override
  PointGame? build() => null;

  PointGame get _game => state!;

  void start({
    String redName = 'แดง',
    String blueName = 'น้ำเงิน',
    PointRules? rules,
  }) {
    state = PointGame.start(redName: redName, blueName: blueName, rules: rules);
    _backUp();
  }

  /// Continues a game restored from the backup.
  void restore(PointGame game) => state = game;

  void addPoint(Side side) {
    state = _game.addPoint(side);
    _scored();
  }

  void removePoint(Side side) {
    final before = _game;
    state = before.removePoint(side);
    if (!identical(state, before)) _scored();
  }

  void undo() {
    state = _game.undo();
    _backUp();
  }

  void chooseServer(Side side) {
    state = _game.chooseServer(side);
    _backUp();
  }

  void swapSides() {
    state = _game.swapSides();
    _backUp();
  }

  void rename(Side side, String name) {
    state = _game.rename(side, name);
    _backUp();
  }

  void finishRound() {
    state = _game.finishRound();
    _backUp();
  }

  void startNextRound({Side? firstServer}) {
    state = _game.startNextRound(firstServer: firstServer);
    _backUp();
  }

  void reset() {
    state = _game.reset();
    _backUp();
  }

  void endGame() {
    state = _game.endGame();
    _backUp();
  }

  /// The game is over (or abandoned): drop it and its backup.
  void end() {
    state = null;
    unawaited(ref.read(pointStorageProvider).clearGame());
  }

  void _scored() {
    _backUp();
    ref.read(hapticsProvider).transaction();
  }

  void _backUp() {
    unawaited(ref.read(pointStorageProvider).saveGame(state!));
  }
}

final pointProvider = NotifierProvider<PointNotifier, PointGame?>(
  PointNotifier.new,
);
