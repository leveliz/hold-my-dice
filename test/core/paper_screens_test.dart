import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';
import 'package:hold_my_dice/core/widgets/dashed_line.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/key_tile.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';

import '../features/bank/presentation/bank_flow_test.dart' as f;

const _red = Color(0xFFB5432B);

Finder byKey(String k) => find.byKey(ValueKey(k));

const _players = [
  Player(id: 'p1', name: 'ต้น', color: 0xFF3F51A3),
  Player(id: 'p2', name: 'ใบ', color: 0xFF65A30D),
];

ProviderContainer scoreGame() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(scoreProvider.notifier)
      .start(players: _players, roundCount: 3, winMode: WinMode.highest);
  c.read(scoreProvider.notifier).setScore(round: 0, playerId: 'p1', score: 12);
  return c;
}

BoxDecoration decorationOf(WidgetTester tester, Finder finder) =>
    (tester.widget<Container>(finder).decoration!) as BoxDecoration;

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('rows and fields', () {
    Future<BoxDecoration> tile(WidgetTester tester, Brightness b) async {
      late BoxDecoration d;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              d = tileDecoration(context);
              return const SizedBox();
            },
          ),
          brightness: b,
        ),
      );
      await tester.pumpAndSettle();
      return d;
    }

    testWidgets('are ivory boxes with a thin edge and one sheet on paper', (
      tester,
    ) async {
      final d = await tile(tester, Brightness.light);
      expect(d.color, PaperStyle.card);
      expect(d.borderRadius, BorderRadius.circular(PaperStyle.radius));
      expect((d.border! as Border).top.color, PaperStyle.edge);
      expect(d.boxShadow!.single.color, PaperStyle.sheetFar);
    });

    testWidgets('keep a faint rounder panel in Aurora', (tester) async {
      final d = await tile(tester, Brightness.dark);
      expect(d.border, isNull);
      expect(d.boxShadow, isNull);
      expect(d.borderRadius, BorderRadius.circular(18));
    });

    testWidgets('honour the corner asked for in Aurora only', (tester) async {
      late BoxDecoration light;
      late BoxDecoration dark;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              light = tileDecoration(context, radius: 30);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              dark = tileDecoration(context, radius: 30);
              return const SizedBox();
            },
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(light.borderRadius, BorderRadius.circular(PaperStyle.radius));
      expect(dark.borderRadius, BorderRadius.circular(30));
    });

    testWidgets('the player list and the money fields use them', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank', container: ProviderContainer());
      final rows = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration &&
            d.color == PaperStyle.card &&
            d.boxShadow?.length == 1;
      });
      // Two players and two money fields.
      expect(rows, findsNWidgets(4));
    });

    testWidgets(
      'the add-player slot is a dashed kraft box with a small corner',
      (tester) async {
        await f.pumpAt(tester, '/bank', container: ProviderContainer());
        final slots = tester
            .widgetList<DashedBorder>(find.byType(DashedBorder))
            .toList();
        expect(slots.length, 1);
        expect(slots.single.color, PaperStyle.kraft);
        expect(slots.single.radius, PaperStyle.radius);
      },
    );

    testWidgets('the add-player slot stays soft in Aurora', (tester) async {
      await f.pumpAt(
        tester,
        '/bank',
        container: ProviderContainer(),
        brightness: Brightness.dark,
      );
      final slot = tester.widget<DashedBorder>(find.byType(DashedBorder));
      expect(slot.radius, 18);
      expect(slot.color, isNot(PaperStyle.kraft));
    });

    testWidgets('the history rows are tiles too', (tester) async {
      final c = f.gameWith(2);
      c.read(bankProvider.notifier).passGo('p1');
      await f.pumpAt(tester, '/bank/history', container: c);
      final d = decorationOf(tester, byKey('history-row-0'));
      expect(d.color, PaperStyle.card);
      expect(d.boxShadow, isNotNull);
    });
  });

  group('number keys', () {
    Widget keys() => KeyTile(
      inkKey: const ValueKey('k'),
      onTap: () {},
      child: const Text('5'),
    );

    testWidgets('are ivory tiles with a sheet underneath on paper', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(SizedBox(width: 80, height: 60, child: keys())),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(KeyTile),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, PaperStyle.card);
      expect(d.borderRadius, BorderRadius.circular(6));
      expect(d.boxShadow!.single.offset, const Offset(0, 2));
    });

    testWidgets('are faint rounded panels in Aurora', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(width: 80, height: 60, child: keys()),
          brightness: Brightness.dark,
        ),
      );
      expect(
        find.descendant(
          of: find.byType(KeyTile),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(KeyTile),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.borderRadius, BorderRadius.circular(16));
    });

    testWidgets('take a tap on the ink well that carries the key', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 80,
            height: 60,
            child: KeyTile(
              inkKey: const ValueKey('k'),
              onTap: () => taps++,
              child: const Text('5'),
            ),
          ),
        ),
      );
      await tester.tap(byKey('k'));
      expect(taps, 1);
      expect(tester.widget(byKey('k')), isA<InkWell>());
    });

    testWidgets('the money pad and the score pad both use them', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(2));
      await tester.tap(byKey('btn-plus-p1'));
      await tester.pumpAndSettle();
      expect(find.byType(KeyTile), findsWidgets);
      await f.pumpAt(tester, '/score/play', container: scoreGame());
      await tester.tap(byKey('score-cell-0-p2'));
      await tester.pumpAndSettle();
      expect(find.byType(KeyTile), findsWidgets);
    });

    testWidgets('typing on the paper pad still builds the amount', (
      tester,
    ) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(2));
      await tester.tap(byKey('btn-plus-p1'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('key-5'));
      await tester.pump();
      await tester.tap(byKey('key-0'));
      await tester.pump();
      expect(tester.widget<Text>(byKey('sheet-amount')).data, '50');
    });
  });

  group('the bank bar', () {
    testWidgets('is an ink ticket with a kraft edge on paper', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(2));
      final d = decorationOf(tester, byKey('bank-card'));
      expect(d.color, PaperStyle.ink);
      expect(d.gradient, isNull);
      expect(d.borderRadius, BorderRadius.circular(PaperStyle.radius));
      expect(d.boxShadow!.single.color, PaperStyle.kraft);
      expect(
        find.descendant(
          of: byKey('bank-card'),
          matching: find.byType(DashedLine),
        ),
        findsOneWidget,
      );
    });

    testWidgets('is the blue gradient bar in Aurora', (tester) async {
      await f.pumpAt(
        tester,
        '/bank/play',
        container: f.gameWith(2),
        brightness: Brightness.dark,
      );
      final d = decorationOf(tester, byKey('bank-card'));
      expect(d.gradient, isNotNull);
      expect(d.borderRadius, BorderRadius.circular(24));
      expect(
        find.descendant(
          of: byKey('bank-card'),
          matching: find.byType(DashedLine),
        ),
        findsNothing,
      );
    });

    testWidgets('its lettering is ivory on ink', (tester) async {
      await f.pumpAt(tester, '/bank/play', container: f.gameWith(2));
      final text = tester.widget<Text>(
        find.descendant(of: byKey('bank-card'), matching: find.text('ธนาคาร')),
      );
      expect(text.style!.color, PaperStyle.onInk);
    });
  });

  group('the score table', () {
    testWidgets('header chips are outlined in the player colour on paper', (
      tester,
    ) async {
      await f.pumpAt(tester, '/score/play', container: scoreGame());
      final d = decorationOf(tester, byKey('score-header-p1'));
      expect((d.border! as Border).top.color, const Color(0xFF3F51A3));
      expect(d.borderRadius, BorderRadius.circular(5));
      expect(d.gradient, isNull);
    });

    testWidgets('header chips are filled blocks in Aurora', (tester) async {
      await f.pumpAt(
        tester,
        '/score/play',
        container: scoreGame(),
        brightness: Brightness.dark,
      );
      final d = decorationOf(tester, byKey('score-header-p1'));
      expect(d.border, isNull);
      expect(d.borderRadius, BorderRadius.circular(14));
    });

    testWidgets('a filled cell is plain ivory with a thin edge on paper', (
      tester,
    ) async {
      await f.pumpAt(tester, '/score/play', container: scoreGame());
      final cell = find
          .ancestor(
            of: byKey('score-value-0-p1'),
            matching: find.byType(Container),
          )
          .first;
      final d = decorationOf(tester, cell);
      expect(d.color, PaperStyle.card);
      expect(d.gradient, isNull);
      expect(d.borderRadius, BorderRadius.circular(6));
    });

    testWidgets('a filled cell glows its colour in Aurora', (tester) async {
      await f.pumpAt(
        tester,
        '/score/play',
        container: scoreGame(),
        brightness: Brightness.dark,
      );
      final cell = find
          .ancestor(
            of: byKey('score-value-0-p1'),
            matching: find.byType(Container),
          )
          .first;
      expect(decorationOf(tester, cell).gradient, isNotNull);
    });

    testWidgets('an empty cell is dashed in the paper dash colour', (
      tester,
    ) async {
      await f.pumpAt(tester, '/score/play', container: scoreGame());
      final dashed = tester.widget<DashedBorder>(
        find.ancestor(
          of: byKey('score-empty-0-p2'),
          matching: find.byType(DashedBorder),
        ),
      );
      expect(dashed.color, PaperStyle.dash);
      expect(dashed.radius, 6);
    });

    testWidgets('the totals bar is ink with a small corner on paper', (
      tester,
    ) async {
      await f.pumpAt(tester, '/score/play', container: scoreGame());
      final bar = find
          .ancestor(of: find.text('รวม'), matching: find.byType(Container))
          .first;
      final d = decorationOf(tester, bar);
      expect(d.color, PaperStyle.ink);
      expect(
        d.borderRadius,
        const BorderRadius.horizontal(left: Radius.circular(PaperStyle.radius)),
      );
    });

    testWidgets('the totals bar is deep indigo and rounder in Aurora', (
      tester,
    ) async {
      await f.pumpAt(
        tester,
        '/score/play',
        container: scoreGame(),
        brightness: Brightness.dark,
      );
      final bar = find
          .ancestor(of: find.text('รวม'), matching: find.byType(Container))
          .first;
      final d = decorationOf(tester, bar);
      expect(d.color, const Color(0xFF2B3181));
      expect(
        d.borderRadius,
        const BorderRadius.horizontal(left: Radius.circular(18)),
      );
    });

    testWidgets('the round pill is an inked outline on paper', (tester) async {
      await f.pumpAt(tester, '/score/play', container: scoreGame());
      final d = decorationOf(tester, byKey('score-round-pill'));
      expect(d.color, isNull);
      expect((d.border! as Border).top.color, PaperStyle.ink);
    });

    testWidgets('the round pill is a faint pill in Aurora', (tester) async {
      await f.pumpAt(
        tester,
        '/score/play',
        container: scoreGame(),
        brightness: Brightness.dark,
      );
      final d = decorationOf(tester, byKey('score-round-pill'));
      expect(d.color, isNotNull);
      expect(d.border, isNull);
    });
  });

  group('page headers', () {
    testWidgets('a header outside any helper falls back to an ink line', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const Column(
            children: [
              SizedBox(height: 80, child: HelperAppBar(title: Text('x'))),
            ],
          ),
        ),
      );
      expect(
        tester.widget<DashedLine>(find.byType(DashedLine)).color,
        PaperStyle.ink,
      );
    });

    testWidgets('a header in a helper takes that helper colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const HelperScope(
            color: Colors.green,
            paperColor: _red,
            child: SizedBox(height: 80, child: HelperAppBar(title: Text('x'))),
          ),
        ),
      );
      expect(tester.widget<DashedLine>(find.byType(DashedLine)).color, _red);
    });

    testWidgets(
      'in Aurora there is no line and the band is the helper colour',
      (tester) async {
        await tester.pumpWidget(
          host(
            const HelperScope(
              color: Colors.green,
              paperColor: _red,
              child: SizedBox(
                height: 80,
                child: HelperAppBar(title: Text('x')),
              ),
            ),
            brightness: Brightness.dark,
          ),
        );
        expect(find.byType(DashedLine), findsNothing);
      },
    );

    testWidgets('headingStyle is serif on paper and unchanged in Aurora', (
      tester,
    ) async {
      late TextStyle? light;
      late TextStyle? dark;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) {
              light = headingStyle(c, const TextStyle(fontSize: 18));
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) {
              dark = headingStyle(c, const TextStyle(fontSize: 18));
              return const SizedBox();
            },
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(light!.fontFamily, 'NotoSerifThai');
      expect(dark!.fontFamily, isNull);
      expect(dark!.fontSize, 18);
    });
  });

  group('chips', () {
    testWidgets('are ivory with a kraft edge on paper', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: ActionChip(label: Text('ล่าสุด 500'), onPressed: null),
          ),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(ActionChip)));
      expect(theme.chipTheme.backgroundColor, PaperStyle.card);
      expect(theme.chipTheme.side!.color, PaperStyle.kraft);
    });

    testWidgets('keep the stock look in Aurora', (tester) async {
      await tester.pumpWidget(
        host(
          const Center(
            child: ActionChip(label: Text('ล่าสุด 500'), onPressed: null),
          ),
          brightness: Brightness.dark,
        ),
      );
      final theme = Theme.of(tester.element(find.byType(ActionChip)));
      expect(theme.chipTheme.backgroundColor, isNot(PaperStyle.card));
    });
  });
}
