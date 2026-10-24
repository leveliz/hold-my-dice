import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:hold_my_dice/core/players/player.dart' show PlayerSetting;

/// What the setup screen remembers from the last game: names, colours and
/// the two money amounts.
class GameSettings {
  const GameSettings({
    required this.players,
    required this.startingCash,
    required this.goAmount,
  });

  factory GameSettings.fromJson(Map<String, dynamic> json) => GameSettings(
    players: [
      for (final p in json['players'] as List)
        PlayerSetting.fromJson(p as Map<String, dynamic>),
    ],
    startingCash: json['startingCash'] as int,
    goAmount: json['goAmount'] as int,
  );

  final List<PlayerSetting> players;
  final int startingCash;
  final int goAmount;

  Map<String, dynamic> toJson() => {
    'players': [for (final p in players) p.toJson()],
    'startingCash': startingCash,
    'goAmount': goAmount,
  };
}

/// Pocket Banker's saved settings and running-game backup.
class BankStorage extends SavedGameStore<GameSettings, GameState> {
  BankStorage(super.store)
    : super(
        settingsKey: settingsKey,
        gameKey: gameKey,
        settingsFromJson: GameSettings.fromJson,
        settingsToJson: (s) => s.toJson(),
        gameFromJson: GameState.fromJson,
        gameToJson: (g) => g.toJson(),
      );

  static const settingsKey = 'bank.settings.v1';
  static const gameKey = 'bank.game.v1';
}

class MemoryBankStorage extends BankStorage {
  MemoryBankStorage() : super(MemoryJsonStore());
}

class PrefsBankStorage extends BankStorage {
  PrefsBankStorage(SharedPreferences prefs) : super(PrefsJsonStore(prefs));

  static const settingsKey = BankStorage.settingsKey;
  static const gameKey = BankStorage.gameKey;
}

/// In memory by default so tests need no setup; `main()` swaps in
/// [PrefsBankStorage] (see `productionOverrides`).
final bankStorageProvider = Provider<BankStorage>((ref) => MemoryBankStorage());
