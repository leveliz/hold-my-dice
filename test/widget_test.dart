import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/app.dart';

void main() {
  testWidgets('app shows the hub screen', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(const ProviderScope(child: HoldMyDiceApp()));
    await tester.pumpAndSettle();
    expect(find.text('Hold My Dice'), findsOneWidget);
  });
}
