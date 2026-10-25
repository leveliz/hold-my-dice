import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';
import 'package:hold_my_dice/core/widgets/dashed_line.dart';
import 'package:hold_my_dice/core/widgets/stamp.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/hub/settings_screen.dart';

import '../bank/presentation/bank_flow_test.dart' as f;
import 'hub_shell_test.dart' as hub;

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

Future<void> openHub(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  ProviderContainer? container,
  Size size = const Size(400, 800),
}) => f.pumpAt(
  tester,
  '/',
  container: container ?? hub.containerWith(),
  brightness: brightness,
  size: size,
);

TextStyle styleOf(WidgetTester tester, Finder text) => DefaultTextStyle.of(
  tester.element(text),
).style.merge(tester.widget<Text>(text).style);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the header on paper', () {
    testWidgets('has no gradient and no rolled-up sheet', (tester) async {
      await openHub(tester);
      final header = tester.widget<Container>(byKey('hub-header'));
      expect(header.decoration, isNull);
      expect(header.color, isNull);
      expect(byKey('hub-sheet'), findsNothing);
    });

    testWidgets('the title is ink in the serif, the line under it dashed', (
      tester,
    ) async {
      await openHub(tester);
      final style = styleOf(tester, byKey('hub-title'));
      expect(style.fontFamily, 'NotoSerifThai');
      expect(style.color, PaperStyle.ink);
      expect(
        find.descendant(
          of: byKey('hub-header'),
          matching: find.byType(DashedLine),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a red stamp marks the corner', (tester) async {
      await openHub(tester);
      final stamp = tester.widget<Stamp>(byKey('hub-stamp'));
      expect(stamp.color, PaperStyle.stamp);
      expect(stamp.tilt, lessThan(0));
    });

    testWidgets('the page starts below the header', (tester) async {
      await openHub(tester);
      final header = tester.getRect(byKey('hub-header'));
      final card = tester.getRect(byKey('helper-bank'));
      expect(card.top, greaterThan(header.bottom));
    });

    testWidgets('names the page you are on, in every tab', (tester) async {
      await openHub(tester);
      String title() => tester.widget<Text>(byKey('hub-title')).data!;
      expect(title(), 'Hold My Dice');
      await tapKey(tester, 'nav-saved');
      expect(title(), 'เกมค้าง');
      await tapKey(tester, 'nav-about');
      expect(title(), 'เกี่ยวกับ');
    });

    testWidgets('Aurora has the same layout: lettering, a glowing stamp, a '
        'glowing line', (tester) async {
      await openHub(tester, brightness: Brightness.dark);
      final header = tester.widget<Container>(byKey('hub-header'));
      expect(header.decoration, isNull);
      expect(header.color, isNull);
      expect(byKey('hub-sheet'), findsNothing);
      expect(byKey('hub-glow'), findsOneWidget);
      expect(byKey('hub-glow-line'), findsOneWidget);
      expect(byKey('hub-stamp'), findsOneWidget);
      final style = styleOf(tester, byKey('hub-title'));
      expect(style.fontFamily, isNot('NotoSerifThai'));
      expect(style.color, Colors.white);
    });

    testWidgets('the paper header has no glow', (tester) async {
      await openHub(tester);
      expect(byKey('hub-glow'), findsNothing);
      expect(byKey('hub-glow-line'), findsNothing);
    });

    testWidgets('the Aurora line fades from indigo to magenta', (tester) async {
      await openHub(tester, brightness: Brightness.dark);
      final line = tester.widget<Container>(byKey('hub-glow-line'));
      final gradient =
          (line.decoration! as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors, [Palette.auroraIndigo, Palette.auroraMagenta]);
    });

    testWidgets(
      'the page starts a modest step under the header in both looks',
      (tester) async {
        for (final b in Brightness.values) {
          await openHub(tester, brightness: b);
          final header = tester.getRect(byKey('hub-header'));
          final card = tester.getRect(byKey('helper-bank'));
          expect(card.top - header.bottom, greaterThan(20), reason: '$b');
          // The page starts 92 below the top, plus the grid's own 22 padding.
          expect(card.top, closeTo(92 + 22, 1), reason: '$b');
        }
      },
    );

    testWidgets('the subtitle is kraft on paper and pale violet in Aurora', (
      tester,
    ) async {
      Color? subtitle() => tester
          .widget<Text>(find.text('เลือกตัวช่วยสำหรับวงเกมวันนี้'))
          .style
          ?.color;
      await openHub(tester);
      expect(subtitle(), PaperStyle.kraft);
      await openHub(tester, brightness: Brightness.dark);
      expect(subtitle(), const Color(0xFFC7C7E8));
    });

    testWidgets('both looks start the page at the same height', (tester) async {
      await openHub(tester);
      final light = tester.getTopLeft(byKey('helper-bank')).dy;
      await openHub(tester, brightness: Brightness.dark);
      expect(tester.getTopLeft(byKey('helper-bank')).dy, light);
    });

    testWidgets('the Aurora stamp is pale violet on the dark page', (
      tester,
    ) async {
      await openHub(tester, brightness: Brightness.dark);
      final stamp = tester.widget<Stamp>(byKey('hub-stamp'));
      expect(stamp.color, const Color(0xFFC4B5FD));
      final glow = tester.widget<DecoratedBox>(byKey('hub-glow'));
      expect(
        (glow.decoration as BoxDecoration).boxShadow!.single.color.a,
        greaterThan(0.3),
      );
    });
  });

  group('the helper cards on paper', () {
    testWidgets('each has a stamp in its own paper colour', (tester) async {
      await openHub(tester);
      for (final h in helpers) {
        final stamp = tester.widget<Stamp>(byKey('helper-stamp-${h.id}'));
        expect(stamp.color, h.paperColor, reason: h.id);
      }
    });

    testWidgets('the names are in the serif', (tester) async {
      await openHub(tester);
      for (final h in helpers) {
        expect(
          styleOf(tester, byKey('helper-name-${h.id}')).fontFamily,
          'NotoSerifThai',
          reason: h.id,
        );
      }
    });

    testWidgets('there is room for the sheets under the cards', (tester) async {
      await openHub(tester);
      final bank = tester.getRect(byKey('helper-bank'));
      final score = tester.getRect(byKey('helper-score'));
      // The two sheets stick out 6 pixels; the gap must clear them.
      expect(score.left - bank.right, greaterThan(6));
      final point = tester.getRect(byKey('helper-point'));
      expect(point.top - bank.bottom, greaterThan(6));
    });

    testWidgets('the cards are square and fit a small phone', (tester) async {
      await openHub(tester, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
      for (final h in helpers) {
        final size = tester.getSize(byKey('helper-${h.id}'));
        expect(size.width, size.height, reason: h.id);
      }
    });

    testWidgets('Aurora cards have an icon tile, not a stamp', (tester) async {
      await openHub(tester, brightness: Brightness.dark);
      // Only the header's own stamp; no helper has one.
      expect(find.byType(Stamp), findsOneWidget);
      for (final h in helpers) {
        expect(byKey('helper-stamp-${h.id}'), findsNothing, reason: h.id);
      }
    });
  });

  group('the bar on paper', () {
    BoxDecoration fab(WidgetTester tester) =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: byKey('nav-start'),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    testWidgets('the start button is kraft brown with an ivory ring', (
      tester,
    ) async {
      await openHub(tester);
      final d = fab(tester);
      expect(d.color, PaperStyle.kraft);
      expect((d.border! as Border).top.color, PaperStyle.card);
      expect(d.gradient, isNull);
      expect(d.boxShadow!.length, 2);
      expect(d.boxShadow!.last.color, PaperStyle.kraftDark);
      expect(d.boxShadow!.last.offset, const Offset(0, 4));
    });

    testWidgets('the dot under the chosen tab is a red stamp dot', (
      tester,
    ) async {
      await openHub(tester);
      final dot = find
          .descendant(of: byKey('nav-home'), matching: find.byType(Container))
          .evaluate()
          .map((e) => e.widget as Container)
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle)
          .single;
      expect(dot.color, PaperStyle.stamp);
    });

    testWidgets('the chosen icon is ink and the others are faint', (
      tester,
    ) async {
      await openHub(tester);
      Color iconColor(String k) => tester
          .widget<Icon>(
            find.descendant(of: byKey(k), matching: find.byType(Icon)).first,
          )
          .color!;
      expect(iconColor('nav-home'), PaperStyle.ink);
      expect(iconColor('nav-saved'), PaperStyle.faint);
      expect(
        tester
            .widget<Icon>(
              find
                  .descendant(
                    of: byKey('nav-home'),
                    matching: find.byType(Icon),
                  )
                  .first,
            )
            .shadows,
        isNull,
      );
    });

    testWidgets('the rules tab is fainter still', (tester) async {
      await openHub(tester);
      Color iconColor(String k) => tester
          .widget<Icon>(
            find.descendant(of: byKey(k), matching: find.byType(Icon)).first,
          )
          .color!;
      expect(iconColor('nav-rules').a, lessThan(iconColor('nav-saved').a));
    });
  });

  group('saved games on paper', () {
    Future<void> openSaved(WidgetTester tester) async {
      final c = hub.containerWith();
      await openHub(tester, container: c);
      await hub.saveAll(c);
      await tapKey(tester, 'nav-saved');
    }

    testWidgets('each game is a ticket with a stamp on the stub', (
      tester,
    ) async {
      await openSaved(tester);
      for (final h in helpers) {
        final stamp = tester.widget<Stamp>(byKey('saved-stamp-${h.id}'));
        expect(stamp.color, h.paperColor, reason: h.id);
      }
      expect(byKey('ticket-perforation'), findsNWidgets(3));
    });

    testWidgets('the stub and the details sit side by side', (tester) async {
      await openSaved(tester);
      final stamp = tester.getCenter(byKey('saved-stamp-bank'));
      final detail = tester.getCenter(byKey('saved-detail-bank'));
      expect(stamp.dx, lessThan(detail.dx));
      final perforation = tester.getCenter(byKey('ticket-perforation').first);
      expect(perforation.dx, greaterThan(stamp.dx));
      expect(perforation.dx, lessThan(detail.dx));
    });

    testWidgets('the buttons are words only, and the drop one is dashed', (
      tester,
    ) async {
      await openSaved(tester);
      expect(
        find.descendant(
          of: byKey('saved-continue-bank'),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: byKey('saved-discard-bank'),
          matching: find.byType(DashedBorder),
        ),
        findsOneWidget,
      );
    });

    testWidgets('three tickets fit a small phone', (tester) async {
      final c = hub.containerWith();
      await openHub(tester, container: c, size: const Size(320, 568));
      await hub.saveAll(c);
      await tapKey(tester, 'nav-saved');
      expect(tester.takeException(), isNull);
    });

    testWidgets('continuing and dropping still work on a ticket', (
      tester,
    ) async {
      await openSaved(tester);
      await tapKey(tester, 'saved-discard-score');
      await tapKey(tester, 'discard-confirm');
      expect(byKey('saved-score'), findsNothing);
      await tapKey(tester, 'saved-continue-bank');
      expect(byKey('player-card-p1'), findsOneWidget);
    });

    testWidgets('the empty page is in paper tones', (tester) async {
      await openHub(tester);
      await tapKey(tester, 'nav-saved');
      expect(byKey('saved-empty'), findsOneWidget);
      expect(
        styleOf(tester, find.text('ไม่มีเกมที่เล่นค้างอยู่')).fontFamily,
        'NotoSerifThai',
      );
    });

    testWidgets('Aurora keeps its card with an icon tile and icon buttons', (
      tester,
    ) async {
      final c = hub.containerWith();
      await openHub(tester, container: c, brightness: Brightness.dark);
      await hub.saveAll(c);
      await tapKey(tester, 'nav-saved');
      expect(byKey('ticket-perforation'), findsNothing);
      expect(find.byType(Stamp), findsOneWidget);
      expect(byKey('saved-stamp-bank'), findsNothing);
      expect(
        find.descendant(
          of: byKey('saved-continue-bank'),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
      );
    });
  });

  group('the look picker', () {
    testWidgets('the ticked look has an ink outline and a red tick on paper', (
      tester,
    ) async {
      await openHub(tester);
      await tapKey(tester, 'hub-settings');
      await tapKey(tester, 'theme-light');
      final tick = tester.widget<Container>(byKey('theme-tick'));
      expect((tick.decoration! as BoxDecoration).color, PaperStyle.stamp);
      final tile = tester.widget<ThemeOption>(byKey('theme-light'));
      expect(tile.selected, isTrue);
    });

    testWidgets('in Aurora the tick is indigo', (tester) async {
      await openHub(tester, brightness: Brightness.dark);
      await tapKey(tester, 'hub-settings');
      final tick = tester.widget<Container>(byKey('theme-tick'));
      expect((tick.decoration! as BoxDecoration).color, Palette.auroraIndigo);
    });

    testWidgets('each option shows a picture of its look', (tester) async {
      await openHub(tester);
      await tapKey(tester, 'hub-settings');
      for (final k in ['theme-system', 'theme-light', 'theme-dark']) {
        expect(
          find.descendant(of: byKey(k), matching: find.byType(ClipRRect)),
          findsOneWidget,
          reason: k,
        );
      }
    });

    testWidgets('the Aurora picture is dark even on paper', (tester) async {
      await openHub(tester);
      await tapKey(tester, 'hub-settings');
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: byKey('theme-dark'),
              matching: find.byType(DecoratedBox),
            )
            .last,
      );
      final gradient =
          (box.decoration as BoxDecoration).gradient! as RadialGradient;
      for (final c in gradient.colors) {
        expect(c.a, 1, reason: 'opaque, so paper cannot show through');
      }
    });

    testWidgets('the page title of the card is in the serif on paper', (
      tester,
    ) async {
      await openHub(tester);
      await tapKey(tester, 'hub-settings');
      expect(styleOf(tester, find.text('ธีม')).fontFamily, 'NotoSerifThai');
    });
  });

  group('the start sheet on paper', () {
    testWidgets('each helper has a stamp, and the title is serif', (
      tester,
    ) async {
      await openHub(tester);
      await tapKey(tester, 'nav-start');
      for (final h in helpers) {
        final stamp = tester.widget<Stamp>(byKey('start-stamp-${h.id}'));
        expect(stamp.color, h.paperColor, reason: h.id);
      }
      expect(
        styleOf(tester, find.text('เริ่มเกมไหน?')).fontFamily,
        'NotoSerifThai',
      );
    });

    testWidgets('Aurora has icon tiles instead', (tester) async {
      await openHub(tester, brightness: Brightness.dark);
      await tapKey(tester, 'nav-start');
      expect(find.byType(Stamp), findsOneWidget);
      for (final h in helpers) {
        expect(byKey('start-stamp-${h.id}'), findsNothing, reason: h.id);
      }
    });
  });

  group('dialogs on paper', () {
    testWidgets('the launch question has a serif title and an ink button', (
      tester,
    ) async {
      final c = hub.containerWith();
      await hub.saveAll(c);
      await f.pumpAt(tester, '/', container: c);
      expect(byKey('resume-dialog'), findsOneWidget);
      final dialog = tester.widget<AlertDialog>(byKey('resume-dialog'));
      expect(dialog.title, isA<Text>());
      expect(
        styleOf(tester, find.text('เล่นเกมต่อไหม?')).fontFamily,
        'NotoSerifThai',
      );
    });
  });
}
