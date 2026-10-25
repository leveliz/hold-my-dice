import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';

/// A game left in a backup (the app was closed mid-game) that can be resumed.
class SavedGame {
  const SavedGame({
    required this.helperId,
    required this.helperName,
    required this.detail,
    required this.route,
    required this.restore,
    required this.clear,
  });

  final String helperId;
  final String helperName;

  /// Where the game stood, e.g. "รอบ 2/5".
  final String detail;

  /// The play screen to open once the game is restored.
  final String route;
  final VoidCallback restore;
  final Future<void> Function() clear;
}

typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Every helper's backup that can still be played. A backup of a finished game
/// is cleared on the way, and a helper whose game is already open is skipped.
Future<List<SavedGame>> loadSavedGames(Reader read) async {
  final games = <SavedGame>[];

  if (read(bankProvider) == null) {
    final storage = read(bankStorageProvider);
    final saved = storage.loadGame();
    if (saved != null && saved.isOver) {
      await storage.clearGame();
    } else if (saved != null) {
      games.add(
        SavedGame(
          helperId: 'bank',
          helperName: 'Pocket Banker',
          detail: '${saved.activePlayers.length} คน',
          route: '/bank/play',
          restore: () => read(bankProvider.notifier).restore(saved),
          clear: storage.clearGame,
        ),
      );
    }
  }

  if (read(scoreProvider) == null) {
    final storage = read(scoreStorageProvider);
    final saved = storage.loadGame();
    if (saved != null && saved.isOver) {
      await storage.clearGame();
    } else if (saved != null) {
      games.add(
        SavedGame(
          helperId: 'score',
          helperName: 'Score Snitch',
          detail: 'รอบ ${saved.roundNumber}/${saved.roundCount}',
          route: '/score/play',
          restore: () => read(scoreProvider.notifier).restore(saved),
          clear: storage.clearGame,
        ),
      );
    }
  }

  if (read(pointProvider) == null) {
    final storage = read(pointStorageProvider);
    final saved = storage.loadGame();
    if (saved != null && saved.isOver) {
      await storage.clearGame();
    } else if (saved != null) {
      games.add(
        SavedGame(
          helperId: 'point',
          helperName: 'Point Blank',
          detail: 'รอบ ${saved.roundNumber} · ${saved.red}–${saved.blue}',
          route: '/point/play',
          restore: () => read(pointProvider.notifier).restore(saved),
          clear: storage.clearGame,
        ),
      );
    }
  }

  return games;
}

/// The list behind the "เกมค้าง" tab; read again each time the tab opens.
final savedGamesProvider = FutureProvider.autoDispose<List<SavedGame>>(
  (ref) => loadSavedGames(ref.read),
);
