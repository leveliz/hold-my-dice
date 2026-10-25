import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('dark sheets and dialogs are the page navy, one step lighter', () {
    final theme = buildTheme(Brightness.dark);
    final sheet = theme.bottomSheetTheme.backgroundColor!;
    final page = theme.colorScheme.surface;
    expect(page, Palette.night);
    expect(sheet, isNot(page));
    expect(
      HSLColor.fromColor(sheet).lightness,
      greaterThan(HSLColor.fromColor(page).lightness),
    );
    // Same hue family as the page, not a neutral grey.
    expect(sheet.b, greaterThan(sheet.r));
    expect(theme.dialogTheme.backgroundColor, sheet);
  });

  test('light sheets are paper and dialogs are a card, without a tint', () {
    final theme = buildTheme(Brightness.light);
    expect(theme.bottomSheetTheme.backgroundColor, PaperStyle.paper);
    expect(theme.dialogTheme.backgroundColor, PaperStyle.card);
    expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
    expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
  });

  test('text buttons are lighter than the filled cobalt in the dark theme', () {
    final dark = buildTheme(Brightness.dark).textButtonTheme.style!;
    final light = buildTheme(Brightness.light).textButtonTheme.style!;
    Color colorOf(ButtonStyle style) => style.foregroundColor!.resolve({})!;
    expect(colorOf(light), PaperStyle.ink);
    expect(colorOf(dark), Palette.cobaltLight);
    expect(
      HSLColor.fromColor(colorOf(dark)).lightness,
      greaterThan(HSLColor.fromColor(Palette.cobalt).lightness),
    );
  });
}
