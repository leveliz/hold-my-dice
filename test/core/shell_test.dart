import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
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
    testWidgets('every page sits on the sky gradient', (tester) async {
      for (final path in ['/bank', '/score', '/point']) {
        await pumpRoute(tester, path);
        expect(find.byType(PageBackground), findsOneWidget, reason: path);
      }
    });

    testWidgets('the hub has the gradient behind it and on its sheet', (
      tester,
    ) async {
      await pumpRoute(tester, '/');
      expect(find.byType(PageBackground), findsNWidgets(2));
    });

    testWidgets('each helper colours its own header', (tester) async {
      for (final h in helpers) {
        await pumpRoute(tester, h.route);
        expect(
          appBarColor(tester),
          headerColorFor(h.color, Brightness.light),
          reason: h.id,
        );
      }
    });

    testWidgets('header titles and icons are white on the coloured bar', (
      tester,
    ) async {
      await pumpRoute(tester, '/bank');
      final title = tester.widget<Text>(find.text('ตั้งค่าเกม'));
      final style = DefaultTextStyle.of(
        tester.element(find.text('ตั้งค่าเกม')),
      );
      expect(title.style?.color ?? style.style.color, Colors.white);
    });

    testWidgets('the bar is flat, with no rounded corners', (tester) async {
      await pumpRoute(tester, '/score');
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.shape, isNull);
      final theme = Theme.of(tester.element(find.byType(AppBar)));
      expect(theme.appBarTheme.elevation, 0);
    });

    testWidgets('the coloured header does not leak into other helpers', (
      tester,
    ) async {
      await pumpRoute(tester, '/bank');
      final bank = appBarColor(tester);
      await pumpRoute(tester, '/point');
      expect(appBarColor(tester), isNot(bank));
    });
  });
}
