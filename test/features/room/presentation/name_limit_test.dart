import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';

import 'room_test_app.dart';

TextEditingValue _edit(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('NameLimitFormatter', () {
    const formatter = NameLimitFormatter();

    test('lets a name within 20 UTF-16 units through unchanged', () {
      final next = _edit('x' * 20);
      expect(formatter.formatEditUpdate(_edit(''), next), next);
    });

    test('cuts a longer name and keeps the caret at its end', () {
      final out = formatter.formatEditUpdate(_edit(''), _edit('x' * 25));
      expect(out.text, 'x' * 20);
      expect(out.selection.baseOffset, 20);
    });

    test('counts an emoji as two units and never splits one', () {
      final out = formatter.formatEditUpdate(_edit(''), _edit('😀' * 20));
      expect(out.text, '😀' * 10);
      final odd = formatter.formatEditUpdate(_edit(''), _edit('${'x' * 19}😀'));
      expect(odd.text, 'x' * 19);
    });

    test('keeps a caret in the middle where it was', () {
      final out = formatter.formatEditUpdate(
        _edit('x' * 20),
        TextEditingValue(
          text: 'a${'x' * 20}',
          selection: const TextSelection.collapsed(offset: 1),
        ),
      );
      expect(out.text.length, 20);
      expect(out.selection.baseOffset, 1);
    });
  });

  testWidgets('the name fields stop at 20 units while typing', (tester) async {
    final store = FakeRoomStore();
    await openApp(tester, store, '/room/create');
    await typeInto(tester, 'room-name', 'x' * 30);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('room-name')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, 'x' * 20);

    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'bens');
    await typeInto(tester, 'join-name', '😀' * 15);
    final join = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('join-name')),
        matching: find.byType(TextField),
      ),
    );
    expect(join.controller?.text, '😀' * 10);
  });
}
