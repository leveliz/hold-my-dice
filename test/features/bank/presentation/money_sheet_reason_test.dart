import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/bank/presentation/money_sheet.dart';

const _me = Player(id: 'p1', name: 'ต้น', color: 0xFF3D5AFE);

class _Limit5 extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) =>
      n.text.length > 5 ? o : n;
}

/// Opens the sheet and keeps what it was closed with.
class _Opened {
  MoneyResult? result;
  var closed = false;
}

Future<_Opened> _open(
  WidgetTester tester, {
  ReasonOptions? reason,
  bool isPay = false,
  Size size = const Size(400, 1000),
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = _Opened();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              opened.result = await showMoneySheet(
                context,
                player: _me,
                balance: 1800,
                isPay: isPay,
                recent: const [],
                reason: reason,
              );
              opened.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

Future<void> _keys(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('key-$d')));
  }
  await tester.pump();
}

bool _okEnabled(WidgetTester tester) =>
    tester
        .widget<ButtonStyleButton>(find.byKey(const ValueKey('sheet-ok')))
        .onPressed !=
    null;

void main() {
  testWidgets('a sheet without reason options has no reason field and '
      'answers without a reason', (tester) async {
    final opened = await _open(tester);
    expect(find.byKey(const ValueKey('sheet-reason')), findsNothing);
    await _keys(tester, '300');
    await tester.tap(find.byKey(const ValueKey('sheet-ok')));
    await tester.pumpAndSettle();
    expect(opened.result?.amount, 300);
    expect(opened.result?.reason, isNull);
  });

  testWidgets('with a required reason, OK waits for both amount and reason', (
    tester,
  ) async {
    final opened = await _open(
      tester,
      reason: const ReasonOptions(chips: ['ค่าเช่า', 'ภาษี']),
    );
    expect(find.byKey(const ValueKey('sheet-reason')), findsOneWidget);
    expect(_okEnabled(tester), isFalse);
    await _keys(tester, '300');
    expect(_okEnabled(tester), isFalse, reason: 'amount alone is not enough');
    await tester.enterText(find.byKey(const ValueKey('sheet-reason')), '   ');
    await tester.pump();
    expect(_okEnabled(tester), isFalse, reason: 'blanks are no reason');
    await tester.enterText(
      find.byKey(const ValueKey('sheet-reason')),
      ' ค่าน้ำ ',
    );
    await tester.pump();
    expect(_okEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('sheet-ok')));
    await tester.pumpAndSettle();
    expect(opened.result?.amount, 300);
    expect(opened.result?.reason, 'ค่าน้ำ');
  });

  testWidgets('a reason chip fills the field, and the field can be changed', (
    tester,
  ) async {
    final opened = await _open(
      tester,
      reason: const ReasonOptions(chips: ['ค่าเช่า', 'ภาษี']),
    );
    await _keys(tester, '5');
    await tester.tap(find.byKey(const ValueKey('reason-chip-ภาษี')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sheet-reason')))
          .controller
          ?.text,
      'ภาษี',
    );
    expect(_okEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('reason-chip-ค่าเช่า')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sheet-ok')));
    await tester.pumpAndSettle();
    expect(opened.result?.reason, 'ค่าเช่า');
  });

  testWidgets('the reason is held to the length the options allow', (
    tester,
  ) async {
    await _open(
      tester,
      reason: ReasonOptions(chips: const [], formatter: _Limit5()),
    );
    await tester.enterText(find.byKey(const ValueKey('sheet-reason')), 'abcde');
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('sheet-reason')),
      'abcdef',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sheet-reason')))
          .controller
          ?.text,
      'abcde',
    );
  });

  testWidgets('a payment sheet given no options stays without a reason', (
    tester,
  ) async {
    await _open(tester, isPay: true);
    expect(find.byKey(const ValueKey('sheet-reason')), findsNothing);
  });

  testWidgets(
    'on a short screen the sheet scrolls and OK can still be reached',
    (tester) async {
      final opened = await _open(
        tester,
        reason: const ReasonOptions(chips: ['ค่าเช่า']),
        size: const Size(360, 520),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('key-5')));
      await tester.tap(find.byKey(const ValueKey('key-5')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('reason-chip-ค่าเช่า')),
      );
      await tester.tap(find.byKey(const ValueKey('reason-chip-ค่าเช่า')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('sheet-ok')));
      await tester.tap(find.byKey(const ValueKey('sheet-ok')));
      await tester.pumpAndSettle();
      expect(opened.result?.amount, 5);
      expect(opened.result?.reason, 'ค่าเช่า');
    },
  );
}
