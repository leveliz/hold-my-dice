import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Point Blank setup screen remembers from the last game.
class PointSettings {
  const PointSettings({
    required this.redName,
    required this.blueName,
    required this.rules,
  });

  factory PointSettings.fromJson(Map<String, dynamic> json) => PointSettings(
    redName: json['redName'] as String,
    blueName: json['blueName'] as String,
    rules: PointRules.fromJson(json['rules'] as Map<String, dynamic>),
  );

  final String redName;
  final String blueName;
  final PointRules rules;

  Map<String, dynamic> toJson() => {
    'redName': redName,
    'blueName': blueName,
    'rules': rules.toJson(),
  };
}

/// Point Blank's saved settings and running-game backup.
class PointStorage extends SavedGameStore<PointSettings, PointGame> {
  PointStorage(super.store)
    : super(
        settingsKey: settingsKey,
        gameKey: gameKey,
        settingsFromJson: PointSettings.fromJson,
        settingsToJson: (s) => s.toJson(),
        gameFromJson: PointGame.fromJson,
        gameToJson: (g) => g.toJson(),
      );

  static const settingsKey = 'point.settings.v1';
  static const gameKey = 'point.game.v1';
}

class MemoryPointStorage extends PointStorage {
  MemoryPointStorage() : super(MemoryJsonStore());
}

class PrefsPointStorage extends PointStorage {
  PrefsPointStorage(SharedPreferences prefs) : super(PrefsJsonStore(prefs));

  static const settingsKey = PointStorage.settingsKey;
  static const gameKey = PointStorage.gameKey;
}

/// In memory by default so tests need no setup; `main()` swaps in
/// [PrefsPointStorage] (see `productionOverrides`).
final pointStorageProvider = Provider<PointStorage>(
  (ref) => MemoryPointStorage(),
);
