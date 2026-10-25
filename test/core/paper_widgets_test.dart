import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';
import 'package:hold_my_dice/core/widgets/dither.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/page_background.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:hold_my_dice/core/widgets/stamp.dart';
import 'package:hold_my_dice/core/widgets/tint_button.dart';
import 'package:hold_my_dice/features/bank/presentation/drag_tile.dart';

const _green = Color(0xFF3F7A52);

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    );

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

Finder byKey(String k) => find.byKey(ValueKey(k));

BoxDecoration decorationOf(WidgetTester tester, Finder within) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(of: within, matching: find.byType(DecoratedBox))
                  .first,
            )
            .decoration
        as BoxDecoration;

BoxDecoration containerDecoration(WidgetTester tester, Type inside) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(inside),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    NoiseTile.resetForTest();
  });

  group('the page', () {
    testWidgets('is ivory paper with a dotted grain', (tester) async {
      await pumpRoute(tester, '/bank');
      final base = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: byKey('paper-grain'),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(base.color, PaperStyle.paper);
    });

    testWidgets('the grain is one point per 14-pixel cell, in grain colour', (
      tester,
    ) async {
      await pumpRoute(tester, '/bank');
      final size = tester.getSize(byKey('paper-grain'));
      // A dot sits in the middle of each cell, 7 pixels in from its corner.
      final cells =
          ((size.width - 7) / 14).ceil() * ((size.height - 7) / 14).ceil();
      var count = -1;
      Paint? paint;
      PointMode? mode;
      expect(
        tester.renderObject(byKey('paper-grain')),
        paints..something((name, arguments) {
          if (name != #drawPoints) return false;
          mode = arguments[0] as PointMode;
          count = (arguments[1] as List).length;
          paint = arguments[2] as Paint;
          return true;
        }),
      );
      expect(mode, PointMode.points);
      expect(paint!.color.toARGB32(), PaperStyle.grain.toARGB32());
      expect(count, cells);
    });

    testWidgets('has no aurora blooms and no speckle', (tester) async {
      await pumpRoute(tester, '/bank');
      expect(byKey('aurora-blooms'), findsNothing);
      expect(find.byType(DitherOverlay), findsNothing);
    });

    testWidgets('the dark page has the blooms and no paper grain', (
      tester,
    ) async {
      await pumpRoute(tester, '/bank', brightness: Brightness.dark);
      expect(byKey('aurora-blooms'), findsOneWidget);
      expect(byKey('paper-grain'), findsNothing);
    });

    testWidgets('every light page is on paper', (tester) async {
      for (final path in ['/', '/bank', '/score', '/point']) {
        await pumpRoute(tester, path);
        expect(byKey('paper-grain'), findsWidgets, reason: path);
        expect(find.byType(PageBackground), findsWidgets, reason: path);
      }
    });
  });

  group('the card', () {
    Widget card({double radius = 28}) => GradientCard(
      key: const ValueKey('c'),
      accent: _green,
      radius: radius,
      child: const SizedBox(width: 120, height: 80),
    );

    testWidgets('is ivory with a thin edge and two sheets underneath', (
      tester,
    ) async {
      await tester.pumpWidget(host(card()));
      final d = decorationOf(tester, byKey('c'));
      expect(d.color, PaperStyle.card);
      expect((d.border! as Border).top.color, PaperStyle.edge);
      expect(d.boxShadow!.map((s) => s.offset), [
        const Offset(3, 3),
        const Offset(6, 6),
      ]);
    });

    testWidgets('is not tinted by its accent', (tester) async {
      await tester.pumpWidget(host(card()));
      final d = decorationOf(tester, byKey('c'));
      expect(d.gradient, isNull);
      expect(d.color, isNot(_green));
    });

    testWidgets('has a small corner whatever a screen asks for', (
      tester,
    ) async {
      for (final asked in [12.0, 20.0, 28.0]) {
        await tester.pumpWidget(host(card(radius: asked)));
        expect(
          decorationOf(tester, byKey('c')).borderRadius,
          BorderRadius.circular(PaperStyle.radius),
          reason: '$asked',
        );
      }
    });

    testWidgets('radiusFor says the corner that is really drawn', (
      tester,
    ) async {
      late BuildContext light;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) {
              light = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(GradientCard.radiusFor(light, 28), PaperStyle.radius);
      late BuildContext dark;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) {
              dark = c;
              return const SizedBox();
            },
          ),
          brightness: Brightness.dark,
        ),
      );
      // The theme eases from one look to the other; let it finish.
      await tester.pumpAndSettle();
      expect(GradientCard.radiusFor(dark, 28), 28);
    });

    testWidgets('has no speckle on paper, and still takes a tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          GradientCard(
            key: const ValueKey('c'),
            accent: _green,
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      );
      expect(find.byType(DitherOverlay), findsNothing);
      await tester.tap(byKey('c'));
      expect(taps, 1);
    });

    testWidgets('the dark card keeps its glow and its own corner', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(card(radius: 24), brightness: Brightness.dark),
      );
      final d = decorationOf(tester, byKey('c'));
      expect(d.borderRadius, BorderRadius.circular(24));
      expect(d.gradient, isNotNull);
      expect(find.byType(DitherOverlay), findsOneWidget);
    });
  });

  group('the player button', () {
    Widget button({
      Brightness brightness = Brightness.light,
      VoidCallback? onPressed,
    }) => host(
      SizedBox(
        width: 80,
        height: 44,
        child: TintButton(
          accent: _green,
          semanticLabel: 'รับจากธนาคาร',
          onPressed: onPressed ?? () {},
          child: const Text('+'),
        ),
      ),
      brightness: brightness,
    );

    testWidgets('is outlined with a dashed line in the accent colour', (
      tester,
    ) async {
      await tester.pumpWidget(button());
      final dashed = tester.widget<DashedBorder>(find.byType(DashedBorder));
      expect(dashed.color, _green);
      expect(dashed.strokeWidth, 1.5);
      expect(dashed.radius, 5);
    });

    testWidgets('is only faintly tinted on paper', (tester) async {
      await tester.pumpWidget(button());
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(TintButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, isNot(_green));
      expect(material.color!.computeLuminance(), greaterThan(0.85));
    });

    testWidgets('is not dashed in the dark theme', (tester) async {
      await tester.pumpWidget(button(brightness: Brightness.dark));
      expect(find.byType(DashedBorder), findsNothing);
    });

    testWidgets('still takes a tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(button(onPressed: () => taps++));
      await tester.tap(find.byType(TintButton));
      expect(taps, 1);
    });
  });

  group('the amount chip', () {
    testWidgets('is an ivory stamp box on paper', (tester) async {
      await tester.pumpWidget(
        host(const BalanceChip(amount: 1500, accent: _green)),
      );
      final d = containerDecoration(tester, BalanceChip);
      expect(d.color, PaperStyle.card);
      expect(d.borderRadius, BorderRadius.circular(6));
      expect((d.border! as Border).top.width, 1.5);
    });

    testWidgets('is tinted and rounder in the dark theme', (tester) async {
      await tester.pumpWidget(
        host(
          const BalanceChip(amount: 1500, accent: _green),
          brightness: Brightness.dark,
        ),
      );
      final d = containerDecoration(tester, BalanceChip);
      expect(d.color, isNot(PaperStyle.card));
      expect(d.borderRadius, BorderRadius.circular(14));
    });

    testWidgets('shows the amount with thousands separators', (tester) async {
      await tester.pumpWidget(
        host(const BalanceChip(amount: 15000, accent: _green)),
      );
      expect(find.text('15,000'), findsOneWidget);
    });
  });

  group('the player circle', () {
    testWidgets('is ringed like a stamp on paper', (tester) async {
      await tester.pumpWidget(
        host(const PlayerAvatar(name: 'ต้น', color: _green, size: 40)),
      );
      final d = containerDecoration(tester, PlayerAvatar);
      expect((d.border! as Border).top.color, PaperStyle.card);
      expect(d.boxShadow!.single.color, _green);
      expect(d.boxShadow!.single.spreadRadius, 1.5);
    });

    testWidgets('is a plain circle in the dark theme', (tester) async {
      await tester.pumpWidget(
        host(
          const PlayerAvatar(name: 'ต้น', color: _green, size: 40),
          brightness: Brightness.dark,
        ),
      );
      final d = containerDecoration(tester, PlayerAvatar);
      expect(d.border, isNull);
      expect(d.boxShadow, isNull);
    });

    testWidgets('keeps its size, ring and all', (tester) async {
      await tester.pumpWidget(
        host(const PlayerAvatar(name: 'ต้น', color: _green, size: 40)),
      );
      expect(tester.getSize(find.byType(PlayerAvatar)), const Size(40, 40));
    });
  });

  group('the stamp', () {
    Widget stamp({double tilt = -12, double size = 40}) => host(
      Center(
        child: Stamp(
          color: _green,
          size: size,
          tilt: tilt,
          child: const Icon(Icons.star),
        ),
      ),
    );

    testWidgets('is turned a little off the straight, like a pressed stamp', (
      tester,
    ) async {
      await tester.pumpWidget(stamp());
      final turn = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(Stamp),
              matching: find.byType(Transform),
            )
            .first,
      );
      final angle = math.atan2(
        turn.transform.entry(1, 0),
        turn.transform.entry(0, 0),
      );
      expect(angle, closeTo(-12 * math.pi / 180, 0.001));
    });

    testWidgets('a stamp with no tilt stands straight', (tester) async {
      await tester.pumpWidget(stamp(tilt: 0));
      final turn = tester.widget<Transform>(
        find
            .descendant(
              of: find.byType(Stamp),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(turn.transform.entry(1, 0), closeTo(0, 0.0001));
    });

    testWidgets('is a dashed circle in its colour holding the mark', (
      tester,
    ) async {
      await tester.pumpWidget(stamp(size: 50));
      final dashed = tester.widget<DashedBorder>(find.byType(DashedBorder));
      expect(dashed.color, _green);
      expect(dashed.radius, 25);
      expect(tester.getSize(find.byType(Stamp)), const Size(50, 50));
      final icon = tester.widget<Icon>(find.byIcon(Icons.star));
      expect(icon.color, null);
      final theme = IconTheme.of(tester.element(find.byIcon(Icons.star)));
      expect(theme.color, _green);
      expect(theme.size, 25);
    });
  });

  group('drag and drop', () {
    Widget tile(ValueNotifier<String?> dragging, Brightness brightness) => host(
      DragTile(
        id: 'p1',
        enabled: true,
        accent: _green,
        radius: 28,
        feedbackLabel: 'ต้น',
        dragging: dragging,
        onDrop: (_) {},
        child: const SizedBox(width: 120, height: 80),
      ),
      brightness: brightness,
    );

    testWidgets('the drop outline follows the card corner', (tester) async {
      final dragging = ValueNotifier<String?>('other');
      addTearDown(dragging.dispose);
      await tester.pumpWidget(tile(dragging, Brightness.light));
      final box = tester.widget<DecoratedBox>(byKey('drop-zone-p1'));
      expect(
        (box.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(PaperStyle.radius),
      );
    });

    testWidgets('keeps the asked corner in the dark theme', (tester) async {
      final dragging = ValueNotifier<String?>('other');
      addTearDown(dragging.dispose);
      await tester.pumpWidget(tile(dragging, Brightness.dark));
      final box = tester.widget<DecoratedBox>(byKey('drop-zone-p1'));
      expect(
        (box.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(28),
      );
    });
  });
}
