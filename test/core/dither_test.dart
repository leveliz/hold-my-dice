import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/dither.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';

Future<void> pumpRoute(
  WidgetTester tester,
  String location, {
  Brightness brightness = Brightness.dark,
  ProviderContainer? container,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp.router(
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
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

Finder overlays() => find.byType(DitherOverlay);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    NoiseTile.resetForTest();
  });

  group('the speckle tile', () {
    test('has one RGBA pixel per square of the tile', () {
      expect(buildNoiseTile(size: 8).length, 8 * 8 * 4);
    });

    test('every pixel is almost see-through', () {
      final tile = buildNoiseTile(maxAlpha: 5);
      for (var i = 0; i < tile.length; i += 4) {
        expect(tile[i + 3], inInclusiveRange(1, 5));
      }
    });

    test('is premultiplied: no colour is brighter than its opacity', () {
      final tile = buildNoiseTile();
      for (var i = 0; i < tile.length; i += 4) {
        for (var c = 0; c < 3; c++) {
          expect(tile[i + c], lessThanOrEqualTo(tile[i + 3]));
        }
      }
    });

    test('has both light and dark specks in balance', () {
      final tile = buildNoiseTile(size: 64);
      var light = 0;
      for (var i = 0; i < tile.length; i += 4) {
        if (tile[i] > 0) light++;
      }
      final share = light / (64 * 64);
      expect(share, inInclusiveRange(0.4, 0.6));
    });

    test('is the same every time for the same seed, and not for another', () {
      expect(buildNoiseTile(seed: 3), buildNoiseTile(seed: 3));
      expect(buildNoiseTile(seed: 3), isNot(buildNoiseTile(seed: 4)));
    });

    test('stays faint with the strength the app uses', () {
      final tile = buildNoiseTile();
      for (var i = 3; i < tile.length; i += 4) {
        expect(tile[i], lessThanOrEqualTo(8));
      }
    });

    test('uses every opacity step, so it is not a flat wash', () {
      final tile = buildNoiseTile(maxAlpha: 5);
      final alphas = {for (var i = 3; i < tile.length; i += 4) tile[i]};
      expect(alphas, {1, 2, 3, 4, 5});
    });
  });

  group('loading', () {
    testWidgets('decodes the tile once and keeps it', (tester) async {
      expect(NoiseTile.image, isNull);
      await tester.runAsync(() => NoiseTile.ready);
      final first = NoiseTile.image!;
      expect(first.width, 64);
      expect(first.height, 64);
      await tester.runAsync(() => NoiseTile.ready);
      expect(identical(NoiseTile.image, first), isTrue);
    });

    testWidgets('draws nothing while the tile is still being decoded', (
      tester,
    ) async {
      await pumpRoute(tester, '/');
      final paint = find.descendant(
        of: overlays().first,
        matching: find.byType(CustomPaint),
      );
      expect(NoiseTile.image, isNull);
      expect(tester.renderObject(paint.first), isNot(paints..rect()));
    });

    testWidgets('speckles the box once the tile is ready', (tester) async {
      // Decoded first, outside the test clock, as the real app does.
      await tester.runAsync(() => NoiseTile.ready);
      await pumpRoute(tester, '/');
      final paint = find.descendant(
        of: overlays().first,
        matching: find.byType(CustomPaint),
      );
      expect(tester.renderObject(paint.first), paints..rect());
    });
  });

  group('where it is used', () {
    testWidgets('the dark page has it over the blooms', (tester) async {
      await pumpRoute(tester, '/bank');
      expect(
        find.descendant(of: byKey('aurora-blooms'), matching: overlays()),
        findsOneWidget,
      );
    });

    testWidgets('the light page does not', (tester) async {
      await pumpRoute(tester, '/bank', brightness: Brightness.light);
      expect(overlays(), findsNothing);
    });

    testWidgets('each dark hub card has it, inside its rounded edge', (
      tester,
    ) async {
      await pumpRoute(tester, '/');
      final cards = find.byType(GradientCard);
      expect(cards, findsNWidgets(3));
      for (final card in cards.evaluate()) {
        final overlay = find.descendant(
          of: find.byWidget(card.widget),
          matching: overlays(),
        );
        expect(overlay, findsOneWidget);
        final clip = tester.widget<ClipRRect>(
          find.ancestor(of: overlay, matching: find.byType(ClipRRect)).first,
        );
        expect(
          (clip.borderRadius as BorderRadius).topLeft.x,
          (card.widget as GradientCard).radius,
        );
      }
    });

    testWidgets('light cards do not have it', (tester) async {
      await pumpRoute(tester, '/', brightness: Brightness.light);
      expect(
        find.descendant(of: find.byType(GradientCard), matching: overlays()),
        findsNothing,
      );
    });

    testWidgets('never takes a tap, so cards still open their page', (
      tester,
    ) async {
      await tester.runAsync(() => NoiseTile.ready);
      await pumpRoute(tester, '/');
      await tester.tap(byKey('helper-score'));
      await tester.pumpAndSettle();
      expect(byKey('rounds'), findsOneWidget);
    });

    testWidgets('buttons inside a card still work under the grain', (
      tester,
    ) async {
      await tester.runAsync(() => NoiseTile.ready);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(bankProvider.notifier)
          .start(
            players: const [
              Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE),
              Player(id: 'p2', name: 'ใบ', color: 0xFF2E9E57),
            ],
            startingCash: 1500,
            goAmount: 200,
          );
      await pumpRoute(tester, '/bank/play', container: c);
      await tester.tap(byKey('btn-go-p1'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(byKey('balance-p1')).data, '1,700');
    });

    testWidgets('does not change the size of a card', (tester) async {
      await pumpRoute(tester, '/');
      for (final id in ['bank', 'score', 'point']) {
        final size = tester.getSize(byKey('helper-$id'));
        expect(size.width, size.height, reason: id);
      }
    });
  });
}
