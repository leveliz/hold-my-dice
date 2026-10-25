import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/theme.dart';

double contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final light = buildTheme(Brightness.light);
  final dark = buildTheme(Brightness.dark);

  group('the light theme is Papery', () {
    test('carries the paper style, and the dark theme does not', () {
      expect(light.extension<PaperStyle>(), isNotNull);
      expect(dark.extension<PaperStyle>(), isNull);
    });

    test('paper page, ink text, ink buttons with ivory lettering', () {
      expect(light.colorScheme.surface, PaperStyle.paper);
      expect(light.colorScheme.onSurface, PaperStyle.ink);
      expect(light.colorScheme.primary, PaperStyle.ink);
      expect(light.colorScheme.onPrimary, PaperStyle.onInk);
    });

    test('ink reads on paper and ivory reads on ink at 7:1 or better', () {
      expect(contrast(PaperStyle.ink, PaperStyle.paper), greaterThan(7));
      expect(contrast(PaperStyle.onInk, PaperStyle.ink), greaterThan(7));
      expect(contrast(PaperStyle.ink, PaperStyle.card), greaterThan(7));
    });

    test('muted kraft text still reads on a card at 4.5:1', () {
      expect(contrast(PaperStyle.kraft, PaperStyle.card), greaterThan(4.5));
    });

    test('buttons have a small corner, and the dark ones stay round', () {
      double radius(ThemeData t) {
        final shape =
            t.filledButtonTheme.style!.shape!.resolve({})!
                as RoundedRectangleBorder;
        return (shape.borderRadius as BorderRadius).topLeft.x;
      }

      expect(radius(light), PaperStyle.radius);
      expect(radius(dark), 20);
    });

    test('buttons rest on a kraft edge, the dark ones are flat', () {
      expect(light.filledButtonTheme.style!.elevation!.resolve({}), 2);
      expect(
        light.filledButtonTheme.style!.shadowColor!.resolve({}),
        PaperStyle.kraft,
      );
      expect(dark.filledButtonTheme.style!.elevation!.resolve({}), 0);
    });

    test('headings use the serif, and the dark theme keeps Itim', () {
      expect(light.appBarTheme.titleTextStyle!.fontFamily, 'NotoSerifThai');
      expect(light.dialogTheme.titleTextStyle!.fontFamily, 'NotoSerifThai');
      expect(dark.dialogTheme.titleTextStyle, isNull);
      expect(
        dark.appBarTheme.titleTextStyle!.fontFamily,
        isNot('NotoSerifThai'),
      );
    });

    test('body text and numbers stay in Itim', () {
      for (final style in [
        light.textTheme.bodyMedium,
        light.textTheme.headlineMedium,
        light.textTheme.titleLarge,
      ]) {
        expect(style!.fontFamily, isNot('NotoSerifThai'));
      }
    });

    test('the page bar has no fill, so the paper shows through', () {
      expect(light.appBarTheme.backgroundColor, Colors.transparent);
      expect(light.appBarTheme.elevation, 0);
    });

    test('the page bar has no fill in Aurora either', () {
      expect(dark.appBarTheme.backgroundColor, Colors.transparent);
      expect(dark.appBarTheme.elevation, 0);
    });

    test('sheets are paper and dialogs a card with a thin edge', () {
      expect(light.bottomSheetTheme.backgroundColor, PaperStyle.paper);
      final shape = light.dialogTheme.shape! as RoundedRectangleBorder;
      expect(shape.side.color, PaperStyle.edge);
      expect((shape.borderRadius as BorderRadius).topLeft.x, PaperStyle.radius);
    });

    test('the colour picker is drawn with kraft edges', () {
      expect(light.segmentedButtonTheme.style, isNotNull);
      expect(dark.segmentedButtonTheme.style, isNull);
    });

    test('the toast is ink with ivory writing', () {
      expect(light.snackBarTheme.backgroundColor, PaperStyle.ink);
    });
  });

  group('the paper corner', () {
    test('is small, so paper looks squarer than the 18+ corners of Aurora', () {
      expect(PaperStyle.radius, greaterThan(0));
      expect(PaperStyle.radius, lessThanOrEqualTo(10));
    });
  });

  group('serifStyle', () {
    test('sets the face, the weight and the variable weight axis', () {
      final style = serifStyle(const TextStyle(fontSize: 20))!;
      expect(style.fontFamily, 'NotoSerifThai');
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontVariations, [const FontVariation.weight(700)]);
      expect(style.fontSize, 20);
    });

    test('passes null through', () {
      expect(serifStyle(null), isNull);
    });
  });

  group('the paper card', () {
    test('is ivory, with a thin edge and two sheets underneath', () {
      final d = PaperStyle.cardDecoration();
      expect(d.color, PaperStyle.card);
      expect((d.border! as Border).top.color, PaperStyle.edge);
      expect(d.boxShadow!.length, 2);
      expect(d.boxShadow!.first.offset, const Offset(3, 3));
      expect(d.boxShadow!.last.offset, const Offset(6, 6));
      expect(d.borderRadius, BorderRadius.circular(PaperStyle.radius));
    });

    test('takes another corner when asked', () {
      expect(
        PaperStyle.cardDecoration(radius: 3).borderRadius,
        BorderRadius.circular(3),
      );
    });
  });

  group('the serif is bundled, so Thai headings need no network', () {
    test('the font file is a TrueType font', () async {
      final data = await rootBundle.load('assets/fonts/NotoSerifThai.ttf');
      expect(data.lengthInBytes, greaterThan(100000));
      expect(data.getUint32(0), 0x00010000);
    });

    test('its licence ships with it', () async {
      final text = await rootBundle.loadString(
        'assets/fonts/OFL-NotoSerifThai.txt',
      );
      expect(text, contains('SIL Open Font License'));
    });

    test('the family is declared in the font manifest', () async {
      final manifest = await rootBundle.loadStructuredData<List<dynamic>>(
        'FontManifest.json',
        (s) async => jsonDecode(s) as List<dynamic>,
      );
      final families = [for (final f in manifest) (f as Map)['family']];
      expect(families, contains('NotoSerifThai'));
    });
  });
}
