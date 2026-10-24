import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/app.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('every helper has a unique id and a route', () {
    final ids = helpers.map((h) => h.id).toSet();
    expect(ids.length, helpers.length);
    expect(helpers.every((h) => h.route.startsWith('/')), isTrue);
  });

  testWidgets('hub shows a square card for each helper', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HoldMyDiceApp()));
    await tester.pumpAndSettle();

    for (final h in helpers) {
      expect(find.text(h.name), findsOneWidget);
      final size = tester.getSize(find.byKey(ValueKey('helper-${h.id}')));
      expect(size.width, size.height);
    }
  });

  testWidgets('tapping a card opens that helper', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HoldMyDiceApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('helper-bank')));
    await tester.pumpAndSettle();

    expect(find.text('ตั้งค่าเกม'), findsOneWidget);
    expect(find.byKey(const ValueKey('helper-bank')), findsNothing);
  });
}
