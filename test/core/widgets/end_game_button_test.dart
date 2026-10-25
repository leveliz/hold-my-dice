import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/widgets/end_game_button.dart';
import 'package:hold_my_dice/core/widgets/end_game_icon.dart';

import '../../features/bank/presentation/bank_flow_test.dart' as f;
import '../../features/score/presentation/score_flow_test.dart' as s;

Finder byKey(String k) => f.byKey(k);

Future<void> pumpButton(
  WidgetTester tester, {
  VoidCallback? onPressed,
  Color color = const Color(0xFF123456),
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: IconTheme(
          data: IconThemeData(color: color, size: 24),
          child: EndGameButton(onPressed: onPressed ?? () {}),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the button', () {
    testWidgets('shows the picture with the word under it', (tester) async {
      await pumpButton(tester);
      expect(find.byType(EndGameIcon), findsOneWidget);
      expect(find.text('จบเกม'), findsOneWidget);
      expect(
        tester.getCenter(find.text('จบเกม')).dy,
        greaterThan(tester.getCenter(find.byType(EndGameIcon)).dy),
      );
    });

    testWidgets('a tap anywhere on it ends the game', (tester) async {
      var taps = 0;
      await pumpButton(tester, onPressed: () => taps++);
      await tester.tap(find.text('จบเกม'));
      await tester.tap(find.byType(EndGameIcon));
      expect(taps, 2);
    });

    testWidgets('is big enough to tap with a thumb', (tester) async {
      await pumpButton(tester);
      final size = tester.getSize(find.byType(EndGameButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the picture and the word share the colour of the bar', (
      tester,
    ) async {
      await pumpButton(tester, color: const Color(0xFFAA3300));
      expect(
        tester.widget<ImageIcon>(find.byType(ImageIcon)).color,
        const Color(0xFFAA3300),
      );
      expect(
        tester.widget<Text>(find.text('จบเกม')).style?.color,
        const Color(0xFFAA3300),
      );
    });

    testWidgets('is read out as one button called จบเกม', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpButton(tester);
      expect(find.bySemanticsLabel('จบเกม'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('จบเกม')),
        matchesSemantics(label: 'จบเกม', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('in the app bars', () {
    testWidgets('Pocket Banker has the word beside its other buttons', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      expect(
        find.descendant(
          of: byKey('end-game-button'),
          matching: find.text('จบเกม'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Score Snitch has the word beside its title', (tester) async {
      await f.pumpAt(tester, '/score/play', container: s.started());
      expect(
        find.descendant(
          of: byKey('end-game-button'),
          matching: find.text('จบเกม'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the Pocket Banker title still shows on a small phone', (
      tester,
    ) async {
      await f.pumpAt(
        tester,
        '/bank/play',
        container: f.gameWith(3),
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text('Pocket Banker'));
      expect(title.width, greaterThan(90));
      // Nothing of the bar overlaps the title.
      for (final k in [
        'hide-balances-button',
        'history-button',
        'end-game-button',
      ]) {
        expect(tester.getRect(byKey(k)).overlaps(title), isFalse, reason: k);
      }
    });

    testWidgets('ending the game from the bar still asks first', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      await tester.tap(find.text('จบเกม'));
      await tester.pumpAndSettle();
      expect(byKey('end-dialog'), findsOneWidget);
    });
  });
}
