import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/settings/app_settings.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart' as bank;
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/hub/settings_tab.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';

import '../bank/presentation/bank_flow_test.dart' as f;

const _players = [
  Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
  Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
];

bank.GameState bankGame() =>
    bank.GameState.start(players: _players, startingCash: 1500, goAmount: 200);

ProviderContainer containerWith({AppSettingsStorage? settings}) {
  final c = ProviderContainer(
    overrides: [
      bankStorageProvider.overrideWithValue(MemoryBankStorage()),
      scoreStorageProvider.overrideWithValue(MemoryScoreStorage()),
      pointStorageProvider.overrideWithValue(MemoryPointStorage()),
      appSettingsStorageProvider.overrideWithValue(
        settings ?? MemoryAppSettingsStorage(),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Saves a game for each helper, as if the app had been closed mid-game.
Future<void> saveAll(ProviderContainer c) async {
  await c.read(bankStorageProvider).saveGame(bankGame());
  await c
      .read(scoreStorageProvider)
      .saveGame(ScoreGame.start(players: _players, roundCount: 5));
  await c
      .read(pointStorageProvider)
      .saveGame(PointGame.start().addPoint(Side.red));
}

Finder byKey(String k) => f.byKey(k);

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

String title(WidgetTester tester) =>
    tester.widget<Text>(byKey('hub-title')).data!;

NavigatorState navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the bar', () {
    testWidgets('has four tabs and a raised start button', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      for (final k in [
        'nav-home',
        'nav-saved',
        'nav-rules',
        'nav-settings',
        'nav-start',
      ]) {
        expect(byKey(k), findsOneWidget, reason: k);
      }
    });

    testWidgets('the start button sits above the bar, between the tabs', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      final start = tester.getCenter(byKey('nav-start'));
      final home = tester.getCenter(byKey('nav-home'));
      final settings = tester.getCenter(byKey('nav-settings'));
      expect(start.dx, closeTo(200, 1));
      expect(start.dy, lessThan(home.dy));
      expect(home.dx, lessThan(start.dx));
      expect(settings.dx, greaterThan(start.dx));
    });

    testWidgets('the selected tab has a dot under it and the rest do not', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      Finder dotsUnder(String key) => find.descendant(
        of: byKey(key),
        matching: find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final d = w.decoration;
          return d is BoxDecoration &&
              d.shape == BoxShape.circle &&
              d.color != null &&
              d.color != Colors.transparent;
        }),
      );
      expect(dotsUnder('nav-home'), findsOneWidget);
      expect(dotsUnder('nav-saved'), findsNothing);
      expect(dotsUnder('nav-settings'), findsNothing);
      await tapKey(tester, 'nav-saved');
      expect(dotsUnder('nav-home'), findsNothing);
      expect(dotsUnder('nav-saved'), findsOneWidget);
      expect(dotsUnder('nav-settings'), findsNothing);
      await tapKey(tester, 'nav-settings');
      expect(dotsUnder('nav-saved'), findsNothing);
      expect(dotsUnder('nav-settings'), findsOneWidget);
    });

    testWidgets('the rules library says it is coming and stays on the page', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tester.tap(byKey('nav-rules'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('คลังกฎกำลังจะมา เร็ว ๆ นี้'), findsOneWidget);
      expect(title(tester), 'Hold My Dice');
    });

    testWidgets('every tab has a label for screen readers', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      for (final label in ['หน้าแรก', 'เกมค้าง', 'เริ่มเกม', 'ตั้งค่า']) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
    });
  });

  group('the header', () {
    testWidgets('names the page you are on', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(title(tester), 'Hold My Dice');
      await tapKey(tester, 'nav-saved');
      expect(title(tester), 'เกมค้าง');
      await tapKey(tester, 'nav-settings');
      expect(title(tester), 'ตั้งค่า');
      await tapKey(tester, 'nav-home');
      expect(title(tester), 'Hold My Dice');
    });

    testWidgets('the feature pages are not curved', (tester) async {
      await f.pumpAt(tester, '/bank', container: containerWith());
      expect(byKey('hub-header'), findsNothing);
      expect(byKey('hub-sheet'), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('the bar is for the hub only', () {
    testWidgets('no feature page shows it', (tester) async {
      for (final h in helpers) {
        await f.pumpAt(tester, h.route, container: containerWith());
        expect(byKey('nav-home'), findsNothing, reason: h.id);
        expect(byKey('nav-start'), findsNothing, reason: h.id);
      }
    });

    testWidgets('the play screen does not have it either', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(2));
      expect(byKey('nav-start'), findsNothing);
    });
  });

  group('start button', () {
    testWidgets('lists every helper', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tapKey(tester, 'nav-start');
      expect(byKey('start-sheet'), findsOneWidget);
      for (final h in helpers) {
        expect(byKey('start-${h.id}'), findsOneWidget, reason: h.id);
      }
    });

    testWidgets('picking a helper closes the list and opens that helper', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tapKey(tester, 'nav-start');
      await tapKey(tester, 'start-score');
      expect(byKey('start-sheet'), findsNothing);
      expect(byKey('rounds'), findsOneWidget);
      // Back on the hub, the list is not left open underneath.
      navigator(tester).pop();
      await tester.pumpAndSettle();
      expect(title(tester), 'Hold My Dice');
      expect(byKey('start-sheet'), findsNothing);
    });

    testWidgets('each helper opens its own setup', (tester) async {
      const expected = {
        'bank': 'start-game',
        'score': 'rounds',
        'point': 'red-name',
      };
      for (final h in helpers) {
        await f.pumpAt(tester, '/', container: containerWith());
        await tapKey(tester, 'nav-start');
        await tapKey(tester, 'start-${h.id}');
        expect(byKey(expected[h.id]!), findsOneWidget, reason: h.id);
      }
    });
  });

  group('saved games tab', () {
    /// Opens the hub with nothing saved (so no launch question), then saves a
    /// game for each helper and opens the tab.
    Future<ProviderContainer> hubWithSaved(WidgetTester tester) async {
      final c = containerWith();
      await f.pumpAt(tester, '/', container: c);
      await saveAll(c);
      await tapKey(tester, 'nav-saved');
      return c;
    }

    String detail(WidgetTester tester, String id) =>
        tester.widget<Text>(byKey('saved-detail-$id')).data!;

    testWidgets('says so when nothing is waiting', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tapKey(tester, 'nav-saved');
      expect(byKey('saved-empty'), findsOneWidget);
    });

    testWidgets('lists each helper with where its game stood', (tester) async {
      await hubWithSaved(tester);
      expect(byKey('saved-empty'), findsNothing);
      expect(detail(tester, 'bank'), '2 คน');
      expect(detail(tester, 'score'), 'รอบ 1/5');
      expect(detail(tester, 'point'), 'รอบ 1 · 1–0');
    });

    testWidgets('continuing restores the game and opens its screen', (
      tester,
    ) async {
      final c = await hubWithSaved(tester);
      await tapKey(tester, 'saved-continue-score');
      expect(c.read(scoreProvider), isNotNull);
      expect(byKey('finish-round'), findsOneWidget);
      expect(c.read(bankProvider), isNull, reason: 'only that game');
    });

    testWidgets('a game that ends while playing is gone when you come back', (
      tester,
    ) async {
      final c = await hubWithSaved(tester);
      await tapKey(tester, 'saved-continue-bank');
      c.read(bankProvider.notifier).end();
      navigator(tester).pop();
      await tester.pumpAndSettle();
      expect(byKey('saved-bank'), findsNothing);
      expect(byKey('saved-score'), findsOneWidget);
    });

    testWidgets('dropping a game asks first and can be called off', (
      tester,
    ) async {
      final c = await hubWithSaved(tester);
      await tapKey(tester, 'saved-discard-score');
      expect(byKey('discard-dialog'), findsOneWidget);
      await tapKey(tester, 'discard-keep');
      expect(byKey('saved-score'), findsOneWidget);
      expect(c.read(scoreStorageProvider).loadGame(), isNotNull);
    });

    testWidgets('dropping a game removes it and its backup', (tester) async {
      final c = await hubWithSaved(tester);
      await tapKey(tester, 'saved-discard-score');
      await tapKey(tester, 'discard-confirm');
      expect(byKey('saved-score'), findsNothing);
      expect(c.read(scoreStorageProvider).loadGame(), isNull);
      expect(byKey('saved-bank'), findsOneWidget, reason: 'the others stay');
      expect(c.read(bankStorageProvider).loadGame(), isNotNull);
    });

    testWidgets('dropping the last game shows the empty page', (tester) async {
      final c = containerWith();
      await f.pumpAt(tester, '/', container: c);
      await c
          .read(pointStorageProvider)
          .saveGame(PointGame.start().addPoint(Side.red));
      await tapKey(tester, 'nav-saved');
      await tapKey(tester, 'saved-discard-point');
      await tapKey(tester, 'discard-confirm');
      expect(byKey('saved-empty'), findsOneWidget);
    });

    testWidgets('a finished game is not listed and its backup is cleared', (
      tester,
    ) async {
      final c = containerWith();
      await f.pumpAt(tester, '/', container: c);
      await c.read(pointStorageProvider).saveGame(PointGame.start().endGame());
      await tapKey(tester, 'nav-saved');
      expect(byKey('saved-empty'), findsOneWidget);
      expect(c.read(pointStorageProvider).loadGame(), isNull);
    });

    testWidgets('a game already open is not listed twice', (tester) async {
      final c = containerWith();
      await f.pumpAt(tester, '/', container: c);
      await saveAll(c);
      c.read(bankProvider.notifier).restore(bankGame());
      await tapKey(tester, 'nav-saved');
      expect(byKey('saved-bank'), findsNothing);
      expect(byKey('saved-score'), findsOneWidget);
    });

    testWidgets('three cards fit on a small phone', (tester) async {
      final c = containerWith();
      await f.pumpAt(tester, '/', container: c, size: const Size(320, 568));
      await saveAll(c);
      await tapKey(tester, 'nav-saved');
      expect(tester.takeException(), isNull);
    });
  });

  group('settings tab', () {
    Set<String> chosen(WidgetTester tester) => {
      for (final k in ['theme-system', 'theme-light', 'theme-dark'])
        if (tester.widget<ThemeOption>(byKey(k)).selected) k,
    };

    testWidgets('follows the phone until you choose', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tapKey(tester, 'nav-settings');
      expect(chosen(tester), {'theme-system'});
    });

    testWidgets('offers the phone setting, Papery and Aurora', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tapKey(tester, 'nav-settings');
      expect(find.text('ตามเครื่อง'), findsOneWidget);
      expect(find.text('Papery'), findsOneWidget);
      expect(find.text('Aurora'), findsOneWidget);
    });

    testWidgets('choosing a look changes it and keeps it', (tester) async {
      final settings = MemoryAppSettingsStorage();
      final c = containerWith(settings: settings);
      await f.pumpAt(tester, '/', container: c);
      await tapKey(tester, 'nav-settings');
      await tapKey(tester, 'theme-dark');
      expect(c.read(themeModeProvider), ThemeMode.dark);
      expect(settings.loadThemeMode(), ThemeMode.dark);
      expect(chosen(tester), {'theme-dark'});
      await tapKey(tester, 'theme-light');
      expect(c.read(themeModeProvider), ThemeMode.light);
      expect(chosen(tester), {'theme-light'});
    });

    testWidgets('the saved look is chosen when the page opens', (tester) async {
      final settings = MemoryAppSettingsStorage();
      await settings.saveThemeMode(ThemeMode.light);
      await f.pumpAt(tester, '/', container: containerWith(settings: settings));
      await tapKey(tester, 'nav-settings');
      expect(chosen(tester), {'theme-light'});
    });

    testWidgets('only the chosen look shows a tick', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tapKey(tester, 'nav-settings');
      expect(byKey('theme-tick'), findsOneWidget);
      await tapKey(tester, 'theme-dark');
      expect(byKey('theme-tick'), findsOneWidget);
      expect(
        find.descendant(of: byKey('theme-dark'), matching: byKey('theme-tick')),
        findsOneWidget,
      );
    });
  });

  group('looks', () {
    testWidgets('the hub fits a small phone on every tab', (tester) async {
      await f.pumpAt(
        tester,
        '/',
        container: containerWith(),
        size: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
      for (final tab in ['nav-saved', 'nav-settings', 'nav-home']) {
        await tapKey(tester, tab);
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets('the cards stay square', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      for (final h in helpers) {
        final size = tester.getSize(byKey('helper-${h.id}'));
        expect(size.width, size.height, reason: h.id);
      }
    });
  });
}
