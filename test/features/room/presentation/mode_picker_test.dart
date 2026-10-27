import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';

import 'room_test_app.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('with rooms available, Pocket Banker asks which mode', (
    tester,
  ) async {
    await openApp(tester, FakeRoomStore(), '/bank');
    expect(find.text('เล่นกันแบบไหนดี'), findsOneWidget);
    expect(find.text('เครื่องเดียว'), findsOneWidget);
    expect(find.text('เครื่องนี้เป็นนายธนาคาร'), findsOneWidget);
    expect(find.text('หลายเครื่อง'), findsOneWidget);
    expect(find.text('มีรหัสห้อง เข้าห้อง'), findsOneWidget);
    expect(find.text('ตั้งค่าเกม'), findsNothing);
  });

  testWidgets('without rooms, Pocket Banker opens the setup straight away', (
    tester,
  ) async {
    await openApp(tester, FakeRoomStore(), '/bank', enabled: false);
    expect(find.text('ตั้งค่าเกม'), findsOneWidget);
    expect(find.text('เล่นกันแบบไหนดี'), findsNothing);
  });

  testWidgets('"เครื่องเดียว" opens the single-device setup', (tester) async {
    await openApp(tester, FakeRoomStore(), '/bank');
    await tester.tap(find.byKey(const ValueKey('mode-solo')));
    await tester.pumpAndSettle();
    expect(find.text('ตั้งค่าเกม'), findsOneWidget);
  });

  testWidgets('"หลายเครื่อง" opens the room creation', (tester) async {
    await openApp(tester, FakeRoomStore(), '/bank');
    await tester.tap(find.byKey(const ValueKey('mode-multi')));
    await tester.pumpAndSettle();
    expect(find.text('สร้างห้อง'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-room')), findsOneWidget);
  });

  testWidgets('"มีรหัสห้อง" opens the code entry', (tester) async {
    await openApp(tester, FakeRoomStore(), '/bank');
    await tester.tap(find.byKey(const ValueKey('mode-join')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('code-field')), findsOneWidget);
  });

  group('the example in the empty code field', () {
    testWidgets('says it is an example, and is faint next to what is typed', (
      tester,
    ) async {
      await openApp(tester, FakeRoomStore(), '/room/join');
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('code-field')),
      );
      expect(field.decoration?.hintText, 'เช่น K7M2QX');
      final hint = field.decoration!.hintStyle!.color!;
      final typed =
          field.style?.color ??
          Theme.of(
            tester.element(find.byType(TextField)),
          ).colorScheme.onSurface;
      expect(
        hint.a,
        lessThan(0.5),
        reason: 'a placeholder, not something that looks typed',
      );
      expect(typed.a, greaterThan(hint.a));
    });
  });

  group('typing a code', () {
    testWidgets('the button waits for a complete code', (tester) async {
      await openApp(tester, FakeRoomStore(), '/room/join');
      expect(isEnabled(tester, 'enter-code'), isFalse);
      await tester.enterText(find.byKey(const ValueKey('code-field')), 'K7M');
      await tester.pump();
      expect(isEnabled(tester, 'enter-code'), isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('code-field')),
        'K7M2QO',
      );
      await tester.pump();
      expect(
        isEnabled(tester, 'enter-code'),
        isFalse,
        reason: 'O is no letter',
      );
      await tester.enterText(
        find.byKey(const ValueKey('code-field')),
        'k7m 2qx',
      );
      await tester.pump();
      expect(isEnabled(tester, 'enter-code'), isTrue);
    });

    testWidgets('a code of a room that exists opens its join form', (
      tester,
    ) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      await openApp(tester, store, '/room/join');
      await tester.enterText(
        find.byKey(const ValueKey('code-field')),
        code.toLowerCase(),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('enter-code')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
      expect(find.text(code), findsOneWidget);
    });

    testWidgets('a code of no room says so', (tester) async {
      await openApp(tester, FakeRoomStore(), '/room/join');
      await tester.enterText(
        find.byKey(const ValueKey('code-field')),
        'K7M2QX',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('enter-code')));
      await tester.pumpAndSettle();
      expect(find.text('ห้องนี้จบแล้วหรือไม่มีอยู่'), findsOneWidget);
    });
  });
}
