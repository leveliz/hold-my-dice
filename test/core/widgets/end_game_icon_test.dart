import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/widgets/end_game_icon.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';

import '../../features/bank/presentation/bank_flow_test.dart' as f;
import '../../features/point/presentation/point_flow_test.dart' as p;
import '../../features/score/presentation/score_flow_test.dart' as s;

Finder byKey(String k) => f.byKey(k);

/// The end-game icon inside the button with [key].
Finder iconIn(String key) =>
    find.descendant(of: byKey(key), matching: find.byType(EndGameIcon));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the icon itself', () {
    testWidgets('is a bundled picture that can be loaded', (tester) async {
      final data = await rootBundle.load(EndGameIcon.asset);
      expect(data.lengthInBytes, greaterThan(1000));
    });

    testWidgets('takes its size from the icon theme', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: IconTheme(
            data: IconThemeData(size: 40, color: Color(0xFF123456)),
            child: Center(child: EndGameIcon()),
          ),
        ),
      );
      final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
      expect(icon.size, 40 * 0.88);
      expect(
        tester.getSize(find.byType(ImageIcon)),
        Size(icon.size!, icon.size!),
      );
    });

    testWidgets('is 24 wide in a plain icon theme, like the others', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: EndGameIcon(),
        ),
      );
      expect(tester.widget<ImageIcon>(find.byType(ImageIcon)).size, 24 * 0.88);
    });

    testWidgets('keeps its size inside a box of a fixed size', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 48, height: 48, child: EndGameIcon()),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ImageIcon)),
        const Size(24 * 0.88, 24 * 0.88),
      );
      expect(
        tester.getCenter(find.byType(ImageIcon)),
        tester.getCenter(find.byType(SizedBox).first),
      );
    });

    testWidgets('a size or colour given to it wins over the theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: IconTheme(
            data: IconThemeData(size: 40, color: Color(0xFF123456)),
            child: EndGameIcon(size: 100, color: Color(0xFFFF0000)),
          ),
        ),
      );
      final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
      expect(icon.color, const Color(0xFFFF0000));
      expect(icon.size, 88);
    });

    testWidgets('is drawn in the colour of the icon theme', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: IconTheme(
            data: IconThemeData(size: 24, color: Color(0xFF123456)),
            child: EndGameIcon(),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.color, const Color(0xFF123456));
    });
  });

  group('where the game is ended', () {
    testWidgets('Pocket Banker: the bar button and the confirm button', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(3));
      expect(iconIn('end-game-button'), findsOneWidget);
      await tester.tap(byKey('end-game-button'));
      await tester.pumpAndSettle();
      expect(iconIn('end-confirm'), findsOneWidget);
    });

    testWidgets('Score Snitch: the bar button and the confirm button', (
      tester,
    ) async {
      await f.pumpAt(tester, '/score/play', container: s.started());
      expect(iconIn('end-game-button'), findsOneWidget);
      await tester.tap(byKey('end-game-button'));
      await tester.pumpAndSettle();
      expect(iconIn('end-confirm'), findsOneWidget);
    });

    testWidgets('Point Blank: the strip button and the confirm button', (
      tester,
    ) async {
      await f.pumpAt(
        tester,
        '/point/play',
        container: p.containerWith(),
        size: const Size(800, 400),
      );
      expect(iconIn('end-game-button'), findsOneWidget);
      await tester.tap(byKey('end-game-button'));
      await tester.pumpAndSettle();
      expect(iconIn('end-confirm'), findsOneWidget);
    });

    testWidgets('Point Blank: every strip icon is the same size and tint', (
      tester,
    ) async {
      await f.pumpAt(
        tester,
        '/point/play',
        container: p.containerWith(),
        size: const Size(800, 400),
      );
      // The button box is 48 wide; what differs is the size the glyph is
      // drawn at, which comes down through the icon theme.
      double themeSize(String key) => IconTheme.of(
        tester.element(
          find.descendant(of: byKey(key), matching: find.byType(Icon)),
        ),
      ).size!;
      expect(themeSize('swap-button'), 24);
      expect(themeSize('reset-button'), 24);
      expect(
        tester
            .widget<ImageIcon>(
              find.descendant(
                of: byKey('end-game-button'),
                matching: find.byType(ImageIcon),
              ),
            )
            .size,
        24 * 0.88,
      );
      // Enabled icons are solid white; the undo button has nothing to undo.
      double alpha(Finder icon) => IconTheme.of(tester.element(icon)).color!.a;
      expect(alpha(find.byIcon(LucideIcons.arrowLeftRight)), 1);
      expect(
        alpha(
          find.descendant(
            of: byKey('end-game-button'),
            matching: find.byType(ImageIcon),
          ),
        ),
        1,
      );
      expect(alpha(find.byIcon(LucideIcons.undo2)), closeTo(0.35, 0.01));
    });

    testWidgets('Point Blank: the stop button between two rounds', (
      tester,
    ) async {
      final c = p.containerWith();
      c.read(pointProvider.notifier).addPoint(Side.red);
      c.read(pointProvider.notifier).finishRound();
      await f.pumpAt(
        tester,
        '/point/play',
        container: c,
        size: const Size(800, 400),
      );
      expect(iconIn('end-after-round'), findsOneWidget);
    });
  });
}
