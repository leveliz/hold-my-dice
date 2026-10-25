import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

ProviderContainer gameWith(
  int players, {
  int start = 1500,
  int go = 200,
  List<Override> overrides = const [],
}) {
  final c = ProviderContainer(overrides: overrides);
  addTearDown(c.dispose);
  c
      .read(bankProvider.notifier)
      .start(
        players: [
          for (var i = 1; i <= players; i++)
            Player(id: 'p$i', name: 'ผู้เล่น $i', color: 0xFF3D5AFE + i * 1000),
        ],
        startingCash: start,
        goAmount: go,
      );
  return c;
}

Future<void> pumpAt(
  WidgetTester tester,
  String location, {
  ProviderContainer? container,
  Size size = const Size(400, 800),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp.router(
    theme: buildTheme(brightness),
    routerConfig: createRouter(initialLocation: location),
  );
  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
  await tester.pumpAndSettle();
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> typeKeys(WidgetTester tester, List<String> keys) async {
  for (final k in keys) {
    await tester.tap(byKey('key-$k'));
    await tester.pump();
  }
}

String? chipText(WidgetTester tester, String chipKey) => tester
    .widget<Text>(
      find.descendant(of: byKey(chipKey), matching: find.byType(Text)),
    )
    .data;

Future<void> closeResult(WidgetTester tester) async {
  expect(byKey('result-sheet'), findsOneWidget);
  await tester.tap(byKey('result-close'));
  await tester.pumpAndSettle();
}

String balance(WidgetTester tester, String id) =>
    tester.widget<Text>(byKey('balance-$id')).data!;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('setup screen', () {
    testWidgets('starts with two players and a disabled start button', (
      tester,
    ) async {
      await pumpAt(tester, '/bank');
      expect(byKey('name-p1'), findsOneWidget);
      expect(byKey('name-p2'), findsOneWidget);
      expect(byKey('remove-p1'), findsNothing);
      expect(
        tester.widget<FilledButton>(byKey('start-game')).onPressed,
        isNull,
      );
    });

    testWidgets('start needs both money values', (tester) async {
      await pumpAt(tester, '/bank');
      await tester.enterText(byKey('start-cash'), '1500');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(byKey('start-game')).onPressed,
        isNull,
      );
      await tester.enterText(byKey('go-cash'), '200');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(byKey('start-game')).onPressed,
        isNotNull,
      );
    });

    testWidgets('adds players with unique default names and unique colours', (
      tester,
    ) async {
      await pumpAt(tester, '/bank');
      await tester.tap(byKey('add-player'));
      await tester.pump();
      await tester.tap(byKey('add-player'));
      await tester.pump();
      final names = [
        for (final id in ['p1', 'p2', 'p3', 'p4'])
          tester.widget<TextField>(byKey('name-$id')).controller!.text,
      ];
      expect(names, ['ผู้เล่น 1', 'ผู้เล่น 2', 'ผู้เล่น 3', 'ผู้เล่น 4']);
      final colors = {
        for (final id in ['p1', 'p2', 'p3', 'p4'])
          (tester
                      .widget<Container>(
                        find.descendant(
                          of: byKey('color-$id'),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color,
      };
      expect(colors.length, 4);
    });

    testWidgets('a removed player frees the default name', (tester) async {
      await pumpAt(tester, '/bank');
      await tester.tap(byKey('add-player'));
      await tester.pump();
      await tester.tap(byKey('remove-p2'));
      await tester.pump();
      await tester.tap(byKey('add-player'));
      await tester.pump();
      expect(
        tester.widget<TextField>(byKey('name-p4')).controller!.text,
        'ผู้เล่น 2',
      );
    });

    testWidgets('starting opens the game with everyone at the start cash', (
      tester,
    ) async {
      await pumpAt(tester, '/bank');
      await tester.enterText(byKey('name-p1'), 'ต้น');
      await tester.enterText(byKey('start-cash'), '1500');
      await tester.enterText(byKey('go-cash'), '200');
      await tester.pump();
      await tester.tap(byKey('start-game'));
      await tester.pumpAndSettle();
      expect(find.text('ต้น'), findsOneWidget);
      expect(balance(tester, 'p1'), '1,500');
      expect(balance(tester, 'p2'), '1,500');
    });
  });

  group('game layout', () {
    testWidgets('up to 4 players get tall cards', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(4));
      for (final id in ['p1', 'p2', 'p3', 'p4']) {
        expect(
          tester.getSize(byKey('player-card-$id')).height,
          greaterThanOrEqualTo(112),
        );
      }
      expect(byKey('bank-card'), findsOneWidget);
    });

    testWidgets('5 players switch to compact rows', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(5));
      for (final id in ['p1', 'p5']) {
        expect(
          tester.getSize(byKey('player-card-$id')).height,
          lessThanOrEqualTo(92),
        );
      }
    });

    testWidgets('a short screen turns even 4 players compact', (tester) async {
      await pumpAt(
        tester,
        '/bank/play',
        container: gameWith(4),
        size: const Size(400, 520),
      );
      expect(tester.getSize(byKey('player-card-p1')).height, lessThan(112));
    });

    testWidgets('a wide window puts the players in two columns', (
      tester,
    ) async {
      await pumpAt(
        tester,
        '/bank/play',
        container: gameWith(4),
        size: const Size(1100, 800),
      );
      final p1 = tester.getRect(byKey('player-card-p1'));
      final p2 = tester.getRect(byKey('player-card-p2'));
      final p3 = tester.getRect(byKey('player-card-p3'));
      expect(p2.top, p1.top);
      expect(p2.left, greaterThan(p1.right));
      expect(p3.top, greaterThan(p1.bottom));
      expect(p3.left, p1.left);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone keeps one column', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(4));
      expect(
        tester.getTopLeft(byKey('player-card-p2')).dy,
        greaterThan(tester.getRect(byKey('player-card-p1')).bottom),
      );
    });

    testWidgets('an odd player on a wide window sits alone in the last row', (
      tester,
    ) async {
      await pumpAt(
        tester,
        '/bank/play',
        container: gameWith(3),
        size: const Size(1100, 800),
      );
      final p1 = tester.getRect(byKey('player-card-p1'));
      final p3 = tester.getRect(byKey('player-card-p3'));
      expect(p3.top, greaterThan(p1.bottom));
      expect(p3.left, p1.left);
      expect(p3.width, p1.width);
    });

    testWidgets('many players scroll instead of overflowing', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(12));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(byKey('player-card-p12'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('game actions', () {
    testWidgets('GO adds the go amount and shows undo', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      expect(byKey('undo-bar'), findsNothing);
      await tester.tap(byKey('btn-go-p1'));
      await tester.pumpAndSettle();
      expect(balance(tester, 'p1'), '1,700');
      expect(find.text('ผ่านจุดเริ่ม ผู้เล่น 1 +200'), findsOneWidget);
    });

    testWidgets('cards do not move when the undo bar appears', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(4));
      final before = tester.getRect(byKey('player-card-p1'));
      await tester.tap(byKey('btn-go-p1'));
      await tester.pumpAndSettle();
      expect(byKey('undo-bar'), findsOneWidget);
      expect(tester.getRect(byKey('player-card-p1')), before);
    });

    testWidgets('undo restores the balance and hides the bar', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-go-p1'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('undo-button'));
      await tester.pumpAndSettle();
      expect(balance(tester, 'p1'), '1,500');
      expect(byKey('undo-bar'), findsNothing);
    });

    testWidgets('+ opens the sheet and receiving updates the balance', (
      tester,
    ) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-plus-p2'));
      await tester.pumpAndSettle();
      await typeKeys(tester, ['3', '000']);
      expect(tester.widget<Text>(byKey('sheet-amount')).data, '3,000');
      expect(chipText(tester, 'sheet-balance-chip'), '1,500');
      await tester.tap(byKey('sheet-ok'));
      await tester.pumpAndSettle();
      expect(balance(tester, 'p2'), '4,500');
      await closeResult(tester);
      expect(find.text('รับจากธนาคาร ผู้เล่น 2 +3,000'), findsOneWidget);
    });

    testWidgets('the sheet shows only the current balance', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-plus-p1'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(byKey('sheet-balance-label')).data,
        'ยอดเงินคงเหลือปัจจุบัน',
      );
      expect(chipText(tester, 'sheet-balance-chip'), '1,500');
      await typeKeys(tester, ['4', '0', '0']);
      // Typing an amount does not change the current balance shown.
      expect(chipText(tester, 'sheet-balance-chip'), '1,500');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(byKey('btn-minus-p1'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(byKey('sheet-balance-label')).data,
        'ยอดเงินคงเหลือปัจจุบัน',
      );
      expect(chipText(tester, 'sheet-balance-chip'), '1,500');
      expect(byKey('sheet-before-chip'), findsNothing);
      expect(byKey('sheet-after-chip'), findsNothing);
    });

    testWidgets('confirming shows the new balance and a close button', (
      tester,
    ) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-plus-p2'));
      await tester.pumpAndSettle();
      await typeKeys(tester, ['3', '000']);
      await tester.tap(byKey('sheet-ok'));
      await tester.pumpAndSettle();
      expect(byKey('result-sheet'), findsOneWidget);
      expect(find.text('รับจากธนาคาร ผู้เล่น 2 +3,000'), findsWidgets);
      expect(chipText(tester, 'result-balance-p2'), '4,500');
      expect(byKey('result-balance-p1'), findsNothing);
      await tester.tap(byKey('result-close'));
      await tester.pumpAndSettle();
      expect(byKey('result-sheet'), findsNothing);
    });

    testWidgets('a refused payment shows no result sheet', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-minus-p1'));
      await tester.pumpAndSettle();
      await typeKeys(tester, ['2', '000']);
      await tester.tap(byKey('sheet-ok'));
      await tester.pumpAndSettle();
      expect(byKey('result-sheet'), findsNothing);
    });

    testWidgets('mortgage is an option of the + sheet only', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-minus-p1'));
      await tester.pumpAndSettle();
      expect(byKey('sheet-kind'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(byKey('btn-plus-p1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('จำนอง'));
      await tester.pump();
      await typeKeys(tester, ['6', '0']);
      await tester.tap(byKey('sheet-ok'));
      await tester.pumpAndSettle();
      expect(chipText(tester, 'result-balance-p1'), '1,560');
      await closeResult(tester);
      expect(balance(tester, 'p1'), '1,560');
      expect(find.text('จำนอง ผู้เล่น 1 +60'), findsOneWidget);
    });

    testWidgets('paying the bank lowers the balance', (tester) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-minus-p3'));
      await tester.pumpAndSettle();
      await typeKeys(tester, ['5', '0', '0']);
      await tester.tap(byKey('sheet-ok'));
      await tester.pumpAndSettle();
      expect(chipText(tester, 'result-balance-p3'), '1,000');
      await closeResult(tester);
      expect(balance(tester, 'p3'), '1,000');
      expect(find.text('จ่ายธนาคาร ผู้เล่น 3 -500'), findsOneWidget);
    });

    testWidgets('paying more than the balance opens the shortfall page', (
      tester,
    ) async {
      final c = gameWith(3);
      await pumpAt(tester, '/bank/play', container: c);
      await tester.tap(byKey('btn-minus-p1'));
      await tester.pumpAndSettle();
      await typeKeys(tester, ['2', '000']);
      await tester.tap(byKey('sheet-ok'));
      await tester.pumpAndSettle();
      expect(byKey('shortfall-summary'), findsOneWidget);
      expect(chipText(tester, 'shortfall-amount'), '500');
      // Nothing has been charged yet.
      expect(c.read(bankProvider)!.game.balanceOf('p1'), 1500);
      expect(c.read(bankProvider)!.undoAvailable, isFalse);
    });

    testWidgets('the sheet offers recent amounts and backspace', (
      tester,
    ) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-plus-p1'));
      await tester.pumpAndSettle();
      await typeKeys(tester, ['1', '2', 'back']);
      expect(tester.widget<Text>(byKey('sheet-amount')).data, '1');
      await tester.tap(byKey('sheet-ok'));
      await tester.pumpAndSettle();
      await closeResult(tester);

      await tester.tap(byKey('btn-plus-p2'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('recent-1'));
      await tester.pump();
      expect(tester.widget<Text>(byKey('sheet-amount')).data, '1');
    });

    testWidgets('the ok button stays disabled until an amount is typed', (
      tester,
    ) async {
      await pumpAt(tester, '/bank/play', container: gameWith(3));
      await tester.tap(byKey('btn-plus-p1'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(byKey('sheet-ok')).onPressed, isNull);
      await tester.tap(byKey('key-0'));
      await tester.pump();
      expect(tester.widget<FilledButton>(byKey('sheet-ok')).onPressed, isNull);
    });
  });

  group('setup input', () {
    testWidgets('money fields show thousands separators as you type', (
      tester,
    ) async {
      await pumpAt(tester, '/bank');
      await tester.enterText(byKey('start-cash'), '1500000');
      await tester.pump();
      expect(
        tester.widget<TextField>(byKey('start-cash')).controller!.text,
        '1,500,000',
      );
    });

    testWidgets('the add-player slot reads "+ เพิ่มผู้เล่น"', (tester) async {
      await pumpAt(tester, '/bank');
      expect(find.text('+ เพิ่มผู้เล่น'), findsOneWidget);
      expect(find.byIcon(LucideIcons.userPlus), findsNothing);
    });
  });

  group('leaving the game', () {
    testWidgets('back asks for confirmation and staying keeps the game', (
      tester,
    ) async {
      final c = gameWith(3);
      await pumpAt(tester, '/bank/play', container: c);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(byKey('leave-dialog'), findsOneWidget);
      await tester.tap(byKey('leave-stay'));
      await tester.pumpAndSettle();
      expect(byKey('leave-dialog'), findsNothing);
      expect(byKey('player-card-p1'), findsOneWidget);
      expect(c.read(bankProvider), isNotNull);
    });

    testWidgets('confirming leaves to the hub and discards the game', (
      tester,
    ) async {
      final c = gameWith(3);
      await pumpAt(tester, '/bank/play', container: c);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(byKey('leave-confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Hold My Dice'), findsOneWidget);
      expect(byKey('player-card-p1'), findsNothing);
      expect(c.read(bankProvider), isNull);
    });
  });
}
