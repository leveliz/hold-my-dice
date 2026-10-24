import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';

Future<BoxDecoration> pumpChip(
  WidgetTester tester,
  Brightness brightness,
  Color accent,
) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(body: BalanceChip(amount: 15000, accent: accent)),
    ),
  );
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(BalanceChip),
      matching: find.byType(Container),
    ),
  );
  return box.decoration! as BoxDecoration;
}

void main() {
  const accent = Color(0xFF2E9E57);

  testWidgets('shows the amount with separators', (tester) async {
    await pumpChip(tester, Brightness.light, accent);
    expect(find.text('15,000'), findsOneWidget);
  });

  testWidgets('light theme: pale fill and a darker outline of the accent', (
    tester,
  ) async {
    final d = await pumpChip(tester, Brightness.light, accent);
    final fill = HSLColor.fromColor(d.color!);
    final line = HSLColor.fromColor((d.border! as Border).top.color);
    final base = HSLColor.fromColor(accent);
    expect(fill.lightness, greaterThan(base.lightness));
    expect(line.lightness, lessThan(base.lightness));
    expect((line.hue - base.hue).abs(), lessThan(2));
  });

  testWidgets('dark theme: the outline stays visible against the fill', (
    tester,
  ) async {
    final d = await pumpChip(tester, Brightness.dark, accent);
    final line = (d.border! as Border).top.color;
    expect(line, accent);
    expect(d.color, isNot(accent));
  });
}
