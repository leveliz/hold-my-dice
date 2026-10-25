import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';

Future<void> pumpRoute(
  WidgetTester tester,
  String location, {
  Brightness brightness = Brightness.dark,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        routerConfig: createRouter(initialLocation: location),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder byKey(String k) => find.byKey(ValueKey(k));

List<RadialGradient> blooms(WidgetTester tester) => [
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(
      of: byKey('aurora-blooms'),
      matching: find.byType(DecoratedBox),
    ),
  ))
    (box.decoration as BoxDecoration).gradient! as RadialGradient,
];

double contrastWithWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the dark page is Aurora Glow', () {
    testWidgets('midnight with three blooms: indigo, magenta, emerald', (
      tester,
    ) async {
      await pumpRoute(tester, '/bank');
      final colors = blooms(tester).map((g) => g.colors.first).toList();
      expect(colors.length, 3);
      expect(colors.map((c) => c.withValues(alpha: 1)).toSet(), {
        Palette.auroraIndigo,
        Palette.auroraMagenta,
        Palette.auroraEmerald,
      });
      final base = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: byKey('aurora-blooms'),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(base.color, Palette.night);
    });

    testWidgets('each bloom fades to nothing at its edge', (tester) async {
      await pumpRoute(tester, '/bank');
      for (final g in blooms(tester)) {
        expect(g.colors.first.a, greaterThan(0.2));
        expect(g.colors.last.a, 0);
      }
    });

    testWidgets('the blooms are plain gradients, with no blur anywhere', (
      tester,
    ) async {
      await pumpRoute(tester, '/');
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('the blooms are painted once, apart from the page', (
      tester,
    ) async {
      await pumpRoute(tester, '/bank');
      final parents = <Widget>[];
      tester.element(byKey('aurora-blooms')).visitAncestorElements((e) {
        parents.add(e.widget);
        return parents.length < 2;
      });
      // The blooms, then the boundary that keeps them from repainting.
      expect(parents.last, isA<RepaintBoundary>());
    });

    testWidgets('the blooms sit behind the page and never take a tap', (
      tester,
    ) async {
      await pumpRoute(tester, '/');
      await tester.tap(byKey('helper-score'));
      await tester.pumpAndSettle();
      expect(byKey('rounds'), findsOneWidget);
    });

    testWidgets('every page has the blooms in the dark theme', (tester) async {
      for (final h in helpers) {
        await pumpRoute(tester, h.route);
        expect(byKey('aurora-blooms'), findsOneWidget, reason: h.id);
      }
    });

    testWidgets('and a small phone shows every page without a problem', (
      tester,
    ) async {
      for (final path in ['/', '/bank', '/score', '/point']) {
        await pumpRoute(tester, path, size: const Size(320, 568));
        expect(tester.takeException(), isNull, reason: path);
      }
    });
  });

  group('colours', () {
    test('the dark theme uses indigo, the light theme uses ink', () {
      expect(
        buildTheme(Brightness.dark).colorScheme.primary,
        Palette.auroraIndigo,
      );
      expect(buildTheme(Brightness.light).colorScheme.primary, PaperStyle.ink);
    });

    test('pages are see-through so the background shows', () {
      for (final b in Brightness.values) {
        expect(buildTheme(b).scaffoldBackgroundColor, Colors.transparent);
      }
    });

    test('text on the midnight page reads at 7:1 or better', () {
      final ink = buildTheme(Brightness.dark).colorScheme.onSurface;
      final l1 = ink.computeLuminance();
      final l2 = Palette.night.computeLuminance();
      expect((l1 + 0.05) / (l2 + 0.05), greaterThanOrEqualTo(7));
    });
  });

  group('the hub in Aurora', () {
    testWidgets('the start button glows indigo to magenta in the dark', (
      tester,
    ) async {
      await pumpRoute(tester, '/');
      final fab = tester.widget<Container>(
        find
            .descendant(
              of: byKey('nav-start'),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = fab.decoration! as BoxDecoration;
      expect((decoration.gradient! as LinearGradient).colors, [
        Palette.auroraIndigo,
        Palette.auroraMagenta,
      ]);
      expect(decoration.boxShadow!.single.color.a, greaterThan(0.4));
    });

    testWidgets('the selected tab glows in the dark theme only', (
      tester,
    ) async {
      Icon homeIcon() => tester.widget<Icon>(
        find
            .descendant(of: byKey('nav-home'), matching: find.byType(Icon))
            .first,
      );
      await pumpRoute(tester, '/');
      expect(homeIcon().shadows, isNotNull);
      final other = tester.widget<Icon>(
        find
            .descendant(of: byKey('nav-saved'), matching: find.byType(Icon))
            .first,
      );
      expect(other.shadows, isNull);
      await pumpRoute(tester, '/', brightness: Brightness.light);
      expect(homeIcon().shadows, isNull);
    });
  });

  group('cards', () {
    Future<DecoratedBox> cardBox(
      WidgetTester tester,
      Brightness brightness,
    ) async {
      await pumpRoute(tester, '/', brightness: brightness);
      return tester.widget<DecoratedBox>(
        find
            .descendant(
              of: byKey('helper-bank'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
    }

    testWidgets('catch a thin light edge in the dark theme', (tester) async {
      final box = await cardBox(tester, Brightness.dark);
      final border = (box.decoration as BoxDecoration).border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color.a, greaterThan(0.1));
    });

    testWidgets('glow in their own colour', (tester) async {
      final box = await cardBox(tester, Brightness.dark);
      final shadow = (box.decoration as BoxDecoration).boxShadow!.single;
      expect(shadow.color.a, closeTo(0.32, 0.01));
      expect(shadow.color.withValues(alpha: 1), Palette.green);
    });

    testWidgets('still work as buttons', (tester) async {
      await pumpRoute(tester, '/');
      expect(find.byType(GradientCard), findsWidgets);
    });
  });
}
