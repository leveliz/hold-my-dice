import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';

Future<void> pumpSplash(WidgetTester tester) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp.router(
      theme: buildTheme(Brightness.light),
      routerConfig: createRouter(initialLocation: '/splash'),
    ),
  ),
);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('splash plays first, then opens the hub', (tester) async {
    await pumpSplash(tester);

    expect(find.byKey(const ValueKey('splash-die')), findsOneWidget);
    expect(find.byKey(const ValueKey('helper-bank')), findsNothing);

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('splash-die')), findsNothing);
    expect(find.byKey(const ValueKey('helper-bank')), findsOneWidget);
  });

  testWidgets('faces change in the air and land on a six', (tester) async {
    await pumpSplash(tester);
    expect(find.byKey(const ValueKey('splash-face-3')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('splash-face-3')), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('splash-face-6')), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
