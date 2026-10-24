import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Score Snitch setup screen remembers from the last game.
class ScoreSettings {
  const ScoreSettings({
    required this.players,
    required this.roundCount,
    required this.winMode,
    this.targetScore,
  });

  factory ScoreSettings.fromJson(Map<String, dynamic> json) => ScoreSettings(
    players: [
      for (final p in json['players'] as List)
        PlayerSetting.fromJson(p as Map<String, dynamic>),
    ],
    roundCount: json['roundCount'] as int,
    winMode: WinMode.values.byName(json['winMode'] as String),
    targetScore: json['targetScore'] as int?,
  );

  final List<PlayerSetting> players;
  final int roundCount;
  final WinMode winMode;
  final int? targetScore;

  Map<String, dynamic> toJson() => {
    'players': [for (final p in players) p.toJson()],
    'roundCount': roundCount,
    'winMode': winMode.name,
    'targetScore': targetScore,
  };
}

/// Score Snitch's saved settings and running-game backup.
class ScoreStorage extends SavedGameStore<ScoreSettings, ScoreGame> {
  ScoreStorage(super.store)
    : super(
        settingsKey: settingsKey,
        gameKey: gameKey,
        settingsFromJson: ScoreSettings.fromJson,
        settingsToJson: (s) => s.toJson(),
        gameFromJson: ScoreGame.fromJson,
        gameToJson: (g) => g.toJson(),
      );

  static const settingsKey = 'score.settings.v1';
  static const gameKey = 'score.game.v1';
}

class MemoryScoreStorage extends ScoreStorage {
  MemoryScoreStorage() : super(MemoryJsonStore());
}

class PrefsScoreStorage extends ScoreStorage {
  PrefsScoreStorage(SharedPreferences prefs) : super(PrefsJsonStore(prefs));

  static const settingsKey = ScoreStorage.settingsKey;
  static const gameKey = ScoreStorage.gameKey;
}

/// In memory by default so tests need no setup; `main()` swaps in
/// [PrefsScoreStorage] (see `productionOverrides`).
final scoreStorageProvider = Provider<ScoreStorage>(
  (ref) => MemoryScoreStorage(),
);
