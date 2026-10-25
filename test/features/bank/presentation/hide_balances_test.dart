import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'bank_flow_test.dart' as f;

Finder byKey(String k) => f.byKey(k);

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

String balanceText(WidgetTester tester, String id) =>
    tester.widget<Text>(byKey('balance-$id')).data!;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('hiding balances', () {
    testWidgets('the eye button swaps every balance for dots and back', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      expect(balanceText(tester, 'p1'), '1,500');
      await tapKey(tester, 'hide-balances-button');
      for (final id in ['p1', 'p2', 'p3']) {
        expect(balanceText(tester, id), '••••');
      }
      await tapKey(tester, 'hide-balances-button');
      expect(balanceText(tester, 'p2'), '1,500');
    });

    testWidgets('the button shows an open eye until balances are hidden', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(2));
      expect(
        find.descendant(
          of: byKey('hide-balances-button'),
          matching: find.byIcon(LucideIcons.eye),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'hide-balances-button');
      expect(
        find.descendant(
          of: byKey('hide-balances-button'),
          matching: find.byIcon(LucideIcons.eyeOff),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the recipient list hides balances too', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'hide-balances-button');
      await tapKey(tester, 'player-card-p1');
      expect(
        find.descendant(of: byKey('recipient-p2'), matching: find.text('••••')),
        findsOneWidget,
      );
      expect(find.text('1,500'), findsNothing);
    });

    testWidgets('the recipient list shows balances when not hidden', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tapKey(tester, 'player-card-p1');
      expect(
        find.descendant(
          of: byKey('recipient-p2'),
          matching: find.text('1,500'),
        ),
        findsOneWidget,
      );
    });
  });

  group('player avatar', () {
    Widget host(String name, Color color) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlayerAvatar(name: name, color: color, size: 40),
        ),
      ),
    );

    testWidgets('shows the first letter of the name', (tester) async {
      await tester.pumpWidget(host('Bell', Colors.blue));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('a numbered name shows its number', (tester) async {
      await tester.pumpWidget(host('ผู้เล่น 3', Colors.blue));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a name ending in a long number keeps its first letter', (
      tester,
    ) async {
      await tester.pumpWidget(host('Bell 2024', Colors.blue));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('a name with leading spaces still shows its first letter', (
      tester,
    ) async {
      await tester.pumpWidget(host('  tom', Colors.blue));
      expect(find.text('t'), findsOneWidget);
    });

    testWidgets('an empty name shows an empty circle without failing', (
      tester,
    ) async {
      await tester.pumpWidget(host('   ', Colors.blue));
      expect(tester.takeException(), isNull);
      expect(find.byType(PlayerAvatar), findsOneWidget);
    });

    testWidgets('keeps the letter readable on dark and light colours', (
      tester,
    ) async {
      Color letter() => tester.widget<Text>(find.text('A')).style!.color!;
      await tester.pumpWidget(host('A', const Color(0xFF16163F)));
      expect(letter(), Colors.white);
      await tester.pumpWidget(host('A', const Color(0xFFFFEB3B)));
      expect(letter(), Colors.black87);
    });

    testWidgets('player cards and recipients carry the avatar', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      expect(
        find.descendant(
          of: byKey('player-card-p1'),
          matching: find.byType(PlayerAvatar),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'player-card-p1');
      expect(
        find.descendant(
          of: byKey('recipient-p2'),
          matching: find.byType(PlayerAvatar),
        ),
        findsOneWidget,
      );
    });
  });
}
