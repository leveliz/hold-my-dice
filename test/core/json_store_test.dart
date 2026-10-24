import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  const Settings(this.rounds);

  factory Settings.fromJson(Map<String, dynamic> json) =>
      Settings(json['rounds'] as int);

  final int rounds;

  Map<String, dynamic> toJson() => {'rounds': rounds};
}

class Game {
  const Game(this.scores);

  factory Game.fromJson(Map<String, dynamic> json) =>
      Game([for (final s in json['scores'] as List) s as int]);

  final List<int> scores;

  Map<String, dynamic> toJson() => {'scores': scores};
}

SavedGameStore<Settings, Game> storeOver(JsonStore json, {String id = 'demo'}) {
  return SavedGameStore<Settings, Game>(
    json,
    settingsKey: '$id.settings',
    gameKey: '$id.game',
    settingsFromJson: Settings.fromJson,
    settingsToJson: (s) => s.toJson(),
    gameFromJson: Game.fromJson,
    gameToJson: (g) => g.toJson(),
  );
}

Future<List<JsonStore>> stores() async {
  SharedPreferences.setMockInitialValues({});
  return [
    MemoryJsonStore(),
    PrefsJsonStore(await SharedPreferences.getInstance()),
  ];
}

void main() {
  group('JsonStore (memory and preferences behave the same)', () {
    test(
      'reads back what was written, and nothing for an unknown key',
      () async {
        for (final s in await stores()) {
          expect(s.read('a'), isNull, reason: '$s');
          await s.write('a', {'x': 1, 'name': 'ต้น'});
          expect(s.read('a'), {'x': 1, 'name': 'ต้น'}, reason: '$s');
        }
      },
    );

    test('remove deletes the value', () async {
      for (final s in await stores()) {
        await s.write('a', {'x': 1});
        await s.remove('a');
        expect(s.read('a'), isNull, reason: '$s');
      }
    });

    test('keys do not interfere', () async {
      for (final s in await stores()) {
        await s.write('a', {'v': 1});
        await s.write('b', {'v': 2});
        expect(s.read('a'), {'v': 1});
        expect(s.read('b'), {'v': 2});
      }
    });

    test('text that is not a JSON object is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'bad': 'not json {',
        'list': '[1, 2]',
      });
      final prefs = PrefsJsonStore(await SharedPreferences.getInstance());
      expect(prefs.read('bad'), isNull);
      expect(prefs.read('list'), isNull);

      final memory = MemoryJsonStore()
        ..putRaw('bad', 'not json {')
        ..putRaw('list', '[1, 2]');
      expect(memory.read('bad'), isNull);
      expect(memory.read('list'), isNull);
    });
  });

  group('SavedGameStore', () {
    test('settings and game are saved and loaded separately', () async {
      for (final s in await stores()) {
        final store = storeOver(s);
        expect(store.loadSettings(), isNull);
        expect(store.loadGame(), isNull);
        await store.saveSettings(const Settings(10));
        await store.saveGame(const Game([3, 5]));
        expect(store.loadSettings()!.rounds, 10);
        expect(store.loadGame()!.scores, [3, 5]);
      }
    });

    test('clearing the game keeps the settings', () async {
      for (final s in await stores()) {
        final store = storeOver(s);
        await store.saveSettings(const Settings(10));
        await store.saveGame(const Game([1]));
        await store.clearGame();
        expect(store.loadGame(), isNull);
        expect(store.loadSettings()!.rounds, 10);
      }
    });

    test('two helpers with different keys never see each other', () async {
      for (final s in await stores()) {
        final a = storeOver(s, id: 'a');
        final b = storeOver(s, id: 'b');
        await a.saveGame(const Game([1]));
        expect(b.loadGame(), isNull);
        await b.saveGame(const Game([2]));
        await a.clearGame();
        expect(b.loadGame()!.scores, [2]);
      }
    });

    test('data this version cannot parse is dropped, not thrown', () async {
      final memory = MemoryJsonStore()..putRaw('demo.game', '{"scores": "x"}');
      final store = storeOver(memory);
      expect(store.loadGame(), isNull);
      // Dropped for good, so it is not retried on every launch.
      await Future<void>.delayed(Duration.zero);
      expect(memory.read('demo.game'), isNull);
    });

    test('a missing field is treated like corrupt data', () async {
      final memory = MemoryJsonStore()..putRaw('demo.settings', '{}');
      expect(storeOver(memory).loadSettings(), isNull);
    });
  });
}
