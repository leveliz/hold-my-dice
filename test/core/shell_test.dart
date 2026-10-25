import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/dashed_line.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/page_background.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';

double contrastWithWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

Future<void> pumpRoute(
  WidgetTester tester,
  String location, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: buildTheme(brightness),
        routerConfig: createRouter(initialLocation: location),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? appBarColor(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(of: find.byType(AppBar), matching: find.byType(Material))
          .first,
    )
    .color;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('header colours', () {
    test('white text reads on every helper colour in both themes', () {
      for (final h in helpers) {
        for (final b in Brightness.values) {
          expect(
            contrastWithWhite(headerColorFor(h.color, b)),
            greaterThanOrEqualTo(4.5),
            reason: '${h.id} in $b',
          );
        }
      }
    });

    test('a colour that is already dark enough is kept in the light theme', () {
      const ink = Palette.ink;
      expect(headerColorFor(ink, Brightness.light), ink);
    });

    test('the dark theme uses a deeper tint than the light theme', () {
      final light = headerColorFor(Palette.rose, Brightness.light);
      final dark = headerColorFor(Palette.rose, Brightness.dark);
      expect(
        HSLColor.fromColor(dark).lightness,
        lessThan(HSLColor.fromColor(light).lightness),
      );
    });

    test('the hue of the helper survives the darkening', () {
      for (final h in helpers) {
        final bar = headerColorFor(h.color, Brightness.light);
        final diff =
            (HSLColor.fromColor(bar).hue - HSLColor.fromColor(h.color).hue)
                .abs();
        expect(diff, lessThan(6), reason: h.id);
      }
    });
  });

  group('pages', () {
    testWidgets('every page sits on the page background', (tester) async {
      for (final path in ['/bank', '/score', '/point']) {
        await pumpRoute(tester, path);
        expect(find.byType(PageBackground), findsOneWidget, reason: path);
      }
    });

    testWidgets('the hub has one page background in both looks, and no '
        'rolled-up sheet', (tester) async {
      for (final b in Brightness.values) {
        await pumpRoute(tester, '/', brightness: b);
        expect(find.byType(PageBackground), findsOneWidget, reason: '$b');
        expect(find.byKey(const ValueKey('hub-sheet')), findsNothing);
      }
    });

    testWidgets('the bar is flat, with no rounded corners', (tester) async {
      for (final b in Brightness.values) {
        await pumpRoute(tester, '/score', brightness: b);
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.shape, isNull, reason: '$b');
        final theme = Theme.of(tester.element(find.byType(AppBar)));
        expect(theme.appBarTheme.elevation, 0, reason: '$b');
      }
    });

    testWidgets('the bar is as tall on paper as in Aurora', (tester) async {
      await pumpRoute(tester, '/bank');
      final light = tester.getSize(find.byType(AppBar)).height;
      await pumpRoute(tester, '/bank', brightness: Brightness.dark);
      expect(tester.getSize(find.byType(AppBar)).height, light);
    });
  });

  group('on paper (light)', () {
    testWidgets('the header has no fill, so the paper shows through', (
      tester,
    ) async {
      for (final h in helpers) {
        await pumpRoute(tester, h.route);
        expect(appBarColor(tester), Colors.transparent, reason: h.id);
      }
    });

    testWidgets('a dashed line in the helper colour runs under the title', (
      tester,
    ) async {
      for (final h in helpers) {
        await pumpRoute(tester, h.route);
        expect(find.byKey(const ValueKey('header-line')), findsOneWidget);
        final line = tester.widget<DashedLine>(find.byType(DashedLine));
        expect(line.color, h.paperColor, reason: h.id);
      }
    });

    testWidgets('each helper has its own colour on the line', (tester) async {
      final seen = <Color>{};
      for (final h in helpers) {
        await pumpRoute(tester, h.route);
        seen.add(tester.widget<DashedLine>(find.byType(DashedLine)).color);
      }
      expect(seen.length, helpers.length);
    });

    testWidgets('the line sits at the foot of the bar and is inset', (
      tester,
    ) async {
      await pumpRoute(tester, '/bank');
      final bar = tester.getRect(find.byType(AppBar));
      final line = tester.getRect(find.byType(DashedLine));
      expect(line.bottom, closeTo(bar.bottom, 1));
      expect(line.left, 16);
      expect(line.right, bar.right - 16);
    });

    testWidgets('the title is ink in the serif face', (tester) async {
      await pumpRoute(tester, '/bank');
      final style = DefaultTextStyle.of(
        tester.element(find.text('ตั้งค่าเกม')),
      ).style;
      expect(style.fontFamily, 'NotoSerifThai');
      expect(style.color, PaperStyle.ink);
    });

    testWidgets('the back arrow is ink too', (tester) async {
      await pumpRoute(tester, '/bank');
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(theme.appBarTheme.foregroundColor, PaperStyle.ink);
    });

    testWidgets('the line is drawn in the helper colour of paper, not Aurora', (
      tester,
    ) async {
      await pumpRoute(tester, '/point');
      final line = tester.widget<DashedLine>(find.byType(DashedLine));
      expect(line.color, isNot(helperById('point').color));
      expect(line.color, helperById('point').paperColor);
    });
  });

  group('in Aurora (dark)', () {
    testWidgets('each helper colours its own header band', (tester) async {
      for (final h in helpers) {
        await pumpRoute(tester, h.route, brightness: Brightness.dark);
        expect(
          appBarColor(tester),
          headerColorFor(h.color, Brightness.dark),
          reason: h.id,
        );
      }
    });

    testWidgets('there is no dashed line under the band', (tester) async {
      await pumpRoute(tester, '/bank', brightness: Brightness.dark);
      expect(find.byKey(const ValueKey('header-line')), findsNothing);
      expect(find.byType(DashedLine), findsNothing);
    });

    testWidgets('titles are white on the band', (tester) async {
      await pumpRoute(tester, '/bank', brightness: Brightness.dark);
      final style = DefaultTextStyle.of(
        tester.element(find.text('ตั้งค่าเกม')),
      ).style;
      expect(style.color, Colors.white);
      expect(style.fontFamily, isNot('NotoSerifThai'));
    });

    testWidgets('one helper colour does not leak into another', (tester) async {
      await pumpRoute(tester, '/bank', brightness: Brightness.dark);
      final bank = appBarColor(tester);
      await pumpRoute(tester, '/point', brightness: Brightness.dark);
      expect(appBarColor(tester), isNot(bank));
    });
  });
}
