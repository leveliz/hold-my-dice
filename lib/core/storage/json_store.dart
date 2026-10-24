import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small key to JSON-object store the helpers keep their data in.
abstract class JsonStore {
  /// The object saved under [key], or null if there is none. Data that is not
  /// a JSON object is dropped instead of crashing the app.
  Map<String, dynamic>? read(String key);

  Future<void> write(String key, Map<String, dynamic> value);

  Future<void> remove(String key);
}

class PrefsJsonStore implements JsonStore {
  PrefsJsonStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Map<String, dynamic>? read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      _prefs.remove(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    await _prefs.setString(key, jsonEncode(value));
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

/// Keeps values as JSON text just like [PrefsJsonStore], so tests see the
/// same round trip without touching the platform.
class MemoryJsonStore implements JsonStore {
  final _values = <String, String>{};

  /// Puts raw text under [key], for tests that need unreadable data.
  void putRaw(String key, String raw) => _values[key] = raw;

  @override
  Map<String, dynamic>? read(String key) {
    final raw = _values[key];
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      _values.remove(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    _values[key] = jsonEncode(value);
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

/// What every helper remembers: the settings of its last game, and a backup of
/// the game in progress so it can be resumed if the app is closed.
class SavedGameStore<S, G> {
  SavedGameStore(
    this._store, {
    required String settingsKey,
    required String gameKey,
    required S Function(Map<String, dynamic>) settingsFromJson,
    required Map<String, dynamic> Function(S) settingsToJson,
    required G Function(Map<String, dynamic>) gameFromJson,
    required Map<String, dynamic> Function(G) gameToJson,
  }) : _settingsKey = settingsKey,
       _gameKey = gameKey,
       _settingsFromJson = settingsFromJson,
       _settingsToJson = settingsToJson,
       _gameFromJson = gameFromJson,
       _gameToJson = gameToJson;

  final JsonStore _store;
  final String _settingsKey;
  final String _gameKey;
  final S Function(Map<String, dynamic>) _settingsFromJson;
  final Map<String, dynamic> Function(S) _settingsToJson;
  final G Function(Map<String, dynamic>) _gameFromJson;
  final Map<String, dynamic> Function(G) _gameToJson;

  S? loadSettings() => _read(_settingsKey, _settingsFromJson);

  Future<void> saveSettings(S settings) =>
      _store.write(_settingsKey, _settingsToJson(settings));

  G? loadGame() => _read(_gameKey, _gameFromJson);

  Future<void> saveGame(G game) => _store.write(_gameKey, _gameToJson(game));

  Future<void> clearGame() => _store.remove(_gameKey);

  /// A value this version cannot read (corrupt, or from another version) is
  /// dropped instead of crashing the app.
  T? _read<T>(String key, T Function(Map<String, dynamic>) parse) {
    final json = _store.read(key);
    if (json == null) return null;
    try {
      return parse(json);
    } on Object {
      unawaited(_store.remove(key));
      return null;
    }
  }
}
