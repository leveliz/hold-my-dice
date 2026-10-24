import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/players/player.dart' show PlayerSetting;
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountingHaptics implements Haptics {
  int taps = 0;

  @override
  void transaction() => taps++;
}

const _players = [
  Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
  Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
];

const _a = PlayerSetting(name: 'ต้น', color: 0xFF3D5AFE);
const _b = PlayerSetting(name: 'ใบ', color: 0xFF2E9E57);

ProviderContainer containerWith({ScoreStorage? storage, Haptics? haptics}) {
  final c = ProviderContainer(
    overrides: [
      scoreStorageProvider.overrideWithValue(storage ?? MemoryScoreStorage()),
      if (haptics != null) hapticsProvider.overrideWithValue(haptics),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void startGame(ProviderContainer c, {int rounds = 3, int? target}) {
  c
      .read(scoreProvider.notifier)
      .start(
        players: _players,
        roundCount: rounds,
        winMode: WinMode.highest,
        targetScore: target,
      );
}

String json(ScoreGame g) => jsonEncode(g.toJson());

void main() {
  group('ScoreSettings and storage', () {
    test('settings survive a JSON round trip, with and without a target', () {
      const withTarget = ScoreSettings(
        players: [_a, _b],
        roundCount: 8,
        winMode: WinMode.lowest,
        targetScore: 100,
      );
      final copy = ScoreSettings.fromJson(
        jsonDecode(jsonEncode(withTarget.toJson())) as Map<String, dynamic>,
      );
      expect(copy.players.map((p) => p.name), ['ต้น', 'ใบ']);
      expect(copy.roundCount, 8);
      expect(copy.winMode, WinMode.lowest);
      expect(copy.targetScore, 100);

      const noTarget = ScoreSettings(
        players: [_a, _b],
        roundCount: 3,
        winMode: WinMode.highest,
      );
      final copy2 = ScoreSettings.fromJson(
        jsonDecode(jsonEncode(noTarget.toJson())) as Map<String, dynamic>,
      );
      expect(copy2.targetScore, isNull);
      expect(copy2.winMode, WinMode.highest);
    });

    test('an unknown win mode is refused', () {
      final json = const ScoreSettings(
        players: [_a],
        roundCount: 1,
        winMode: WinMode.highest,
      ).toJson()..['winMode'] = 'middle';
      expect(() => ScoreSettings.fromJson(json), throwsArgumentError);
    });

    test('preferences storage keeps settings and the game', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = PrefsScoreStorage(prefs);
      expect(storage.loadGame(), isNull);
      final game = ScoreGame.start(
        players: _players,
        roundCount: 4,
      ).setScore(round: 0, playerId: 'p1', score: 9);
      await storage.saveGame(game);
      expect(PrefsScoreStorage(prefs).loadGame()!.totalOf('p1'), 9);
      await storage.clearGame();
      expect(storage.loadGame(), isNull);
    });

    test('a corrupt backup is dropped, and bank and score never mix', () async {
      SharedPreferences.setMockInitialValues({
        PrefsScoreStorage.gameKey: '{"v": 1, "players": []}',
        'bank.game.v1': 'something else',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(PrefsScoreStorage(prefs).loadGame(), isNull);
      expect(prefs.containsKey(PrefsScoreStorage.gameKey), isFalse);
      expect(prefs.getString('bank.game.v1'), 'something else');
    });

    test('production overrides use real score storage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: productionOverrides(prefs));
      addTearDown(c.dispose);
      expect(c.read(scoreStorageProvider), isA<PrefsScoreStorage>());
    });
  });

  group('ScoreNotifier', () {
    test('no game until one is started', () {
      expect(containerWith().read(scoreProvider), isNull);
    });

    test('starting backs the new game up', () {
      final storage = MemoryScoreStorage();
      final c = containerWith(storage: storage);
      startGame(c);
      expect(storage.loadGame(), isNotNull);
      expect(c.read(scoreProvider)!.roundNumber, 1);
    });

    test('every change is backed up', () {
      final storage = MemoryScoreStorage();
      final c = containerWith(storage: storage);
      startGame(c);
      final n = c.read(scoreProvider.notifier);

      n.setScore(round: 0, playerId: 'p1', score: 5);
      expect(storage.loadGame()!.totalOf('p1'), 5);
      n.setScore(round: 0, playerId: 'p2', score: 3);
      n.finishRound();
      expect(storage.loadGame()!.roundNumber, 2);
      n.endNow();
      expect(storage.loadGame()!.isOver, isTrue);
      expect(json(storage.loadGame()!), json(c.read(scoreProvider)!));
    });

    test('ending the game deletes the backup', () {
      final storage = MemoryScoreStorage();
      final c = containerWith(storage: storage);
      startGame(c);
      c.read(scoreProvider.notifier).end();
      expect(c.read(scoreProvider), isNull);
      expect(storage.loadGame(), isNull);
    });

    test('restore continues the saved game and keeps backing it up', () {
      final storage = MemoryScoreStorage();
      final c = containerWith(storage: storage);
      final saved = ScoreGame.start(
        players: _players,
        roundCount: 3,
      ).setScore(round: 0, playerId: 'p1', score: 4);
      final n = c.read(scoreProvider.notifier);
      n.restore(saved);
      expect(c.read(scoreProvider)!.totalOf('p1'), 4);
      n.setScore(round: 0, playerId: 'p2', score: 6);
      expect(storage.loadGame()!.totalOf('p2'), 6);
    });

    test('rules still apply through the notifier', () {
      final c = containerWith();
      startGame(c, rounds: 1);
      final n = c.read(scoreProvider.notifier);
      expect(n.finishRound, throwsStateError, reason: 'no scores yet');
      n.setScore(round: 0, playerId: 'p1', score: 1);
      n.setScore(round: 0, playerId: 'p2', score: 2);
      n.finishRound();
      expect(c.read(scoreProvider)!.endReason, EndReason.allRoundsPlayed);
      expect(
        () => n.setScore(round: 0, playerId: 'p1', score: 9),
        throwsStateError,
      );
    });

    test('a score, a finished round and an early end each tap once', () {
      final h = CountingHaptics();
      final c = containerWith(haptics: h);
      startGame(c);
      final n = c.read(scoreProvider.notifier);
      expect(h.taps, 0);
      n.setScore(round: 0, playerId: 'p1', score: 1);
      expect(h.taps, 1);
      n.setScore(round: 0, playerId: 'p2', score: 1);
      n.finishRound();
      expect(h.taps, 3);
      n.endNow();
      expect(h.taps, 4);
    });

    test('a refused change gives no tap and no backup', () {
      final h = CountingHaptics();
      final storage = MemoryScoreStorage();
      final c = containerWith(storage: storage, haptics: h);
      startGame(c);
      final n = c.read(scoreProvider.notifier);
      expect(
        () => n.setScore(round: 5, playerId: 'p1', score: 1),
        throwsArgumentError,
      );
      expect(h.taps, 0);
      expect(storage.loadGame()!.hasAnyScore, isFalse);
    });
  });
}
