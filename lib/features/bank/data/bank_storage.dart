import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerSetting {
  const PlayerSetting({required this.name, required this.color});

  factory PlayerSetting.fromJson(Map<String, dynamic> json) =>
      PlayerSetting(name: json['name'] as String, color: json['color'] as int);

  final String name;
  final int color;

  Map<String, dynamic> toJson() => {'name': name, 'color': color};
}

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

/// Local persistence: the last game's settings, and a backup of the game in
/// progress so it can be resumed if the app is closed mid-game.
abstract class BankStorage {
  GameSettings? loadSettings();
  Future<void> saveSettings(GameSettings settings);

  GameState? loadGame();
  Future<void> saveGame(GameState game);
  Future<void> clearGame();
}

class MemoryBankStorage implements BankStorage {
  GameSettings? _settings;
  Map<String, dynamic>? _game;

  @override
  GameSettings? loadSettings() => _settings;

  @override
  Future<void> saveSettings(GameSettings settings) async =>
      _settings = settings;

  @override
  GameState? loadGame() {
    final json = _game;
    return json == null ? null : GameState.fromJson(json);
  }

  @override
  Future<void> saveGame(GameState game) async => _game = game.toJson();

  @override
  Future<void> clearGame() async => _game = null;
}

class PrefsBankStorage implements BankStorage {
  PrefsBankStorage(this._prefs);

  static const settingsKey = 'bank.settings.v1';
  static const gameKey = 'bank.game.v1';

  final SharedPreferences _prefs;

  @override
  GameSettings? loadSettings() {
    return _read(settingsKey, (json) => GameSettings.fromJson(json));
  }

  @override
  Future<void> saveSettings(GameSettings settings) async {
    await _prefs.setString(settingsKey, jsonEncode(settings.toJson()));
  }

  @override
  GameState? loadGame() => _read(gameKey, GameState.fromJson);

  @override
  Future<void> saveGame(GameState game) async {
    await _prefs.setString(gameKey, jsonEncode(game.toJson()));
  }

  @override
  Future<void> clearGame() async {
    await _prefs.remove(gameKey);
  }

  /// A value this version cannot read (corrupt, or from another version) is
  /// dropped instead of crashing the app.
  T? _read<T>(String key, T Function(Map<String, dynamic>) parse) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return parse(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      _prefs.remove(key);
      return null;
    }
  }
}

/// In memory by default so tests need no setup; `main()` swaps in
/// [PrefsBankStorage] (see `productionOverrides`).
final bankStorageProvider = Provider<BankStorage>((ref) => MemoryBankStorage());
