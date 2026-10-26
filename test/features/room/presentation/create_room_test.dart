import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/players/player_colors.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';

import 'room_test_app.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

/// The room code on the screen, read from its tiles.
String shownCode(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('code-tiles')),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .join();

String seatsValue(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('seats-value'))).data!;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the money starts at the usual Monopoly sums', (tester) async {
    await openApp(tester, FakeRoomStore(), '/room/create');
    final start = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('start-cash')),
        matching: find.byType(TextField),
      ),
    );
    final go = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('go-cash')),
        matching: find.byType(TextField),
      ),
    );
    expect(start.controller?.text, '1,500');
    expect(go.controller?.text, '200');
  });

  testWidgets('a room needs a name before it can be opened', (tester) async {
    await openApp(tester, FakeRoomStore(), '/room/create');
    expect(isEnabled(tester, 'create-room'), isFalse);
    await typeInto(tester, 'room-name', '   ');
    expect(isEnabled(tester, 'create-room'), isFalse);
    await typeInto(tester, 'room-name', 'ต้น');
    expect(isEnabled(tester, 'create-room'), isTrue);
  });

  testWidgets('empty money keeps the button off', (tester) async {
    await openApp(tester, FakeRoomStore(), '/room/create');
    await typeInto(tester, 'room-name', 'ต้น');
    await typeInto(tester, 'start-cash', '');
    expect(isEnabled(tester, 'create-room'), isFalse);
    await typeInto(tester, 'start-cash', '1000');
    await typeInto(tester, 'go-cash', '');
    expect(isEnabled(tester, 'create-room'), isFalse);
  });

  testWidgets('seats can be 2 to 8, starting at 6', (tester) async {
    await openApp(tester, FakeRoomStore(), '/room/create');
    expect(seatsValue(tester), '6 คน');
    for (var i = 0; i < 6; i++) {
      await tapKey(tester, 'seats-minus');
    }
    expect(seatsValue(tester), '2 คน');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('seats-minus')))
          .onPressed,
      isNull,
    );
    for (var i = 0; i < 9; i++) {
      await tapKey(tester, 'seats-plus');
    }
    expect(seatsValue(tester), '8 คน');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('seats-plus')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a password is asked for only when it is switched on', (
    tester,
  ) async {
    await openApp(tester, FakeRoomStore(), '/room/create');
    await typeInto(tester, 'room-name', 'ต้น');
    expect(find.byKey(const ValueKey('room-password')), findsNothing);
    await tester.tap(find.text('ตั้งรหัสผ่านห้อง'));
    await tester.pump();
    expect(find.byKey(const ValueKey('room-password')), findsOneWidget);
    expect(isEnabled(tester, 'create-room'), isFalse);
    await typeInto(tester, 'room-password', 'abcd');
    expect(isEnabled(tester, 'create-room'), isTrue);
  });

  testWidgets('a bank limit is asked for only when it is switched on', (
    tester,
  ) async {
    await openApp(tester, FakeRoomStore(), '/room/create');
    await typeInto(tester, 'room-name', 'ต้น');
    expect(find.byKey(const ValueKey('bank-limit')), findsNothing);
    await tester.ensureVisible(find.text('ธนาคารมีเงินจำกัด'));
    await tester.tap(find.text('ธนาคารมีเงินจำกัด'));
    await tester.pump();
    expect(find.byKey(const ValueKey('bank-limit')), findsOneWidget);
    expect(isEnabled(tester, 'create-room'), isFalse);
    await typeInto(tester, 'bank-limit', '20000');
    expect(isEnabled(tester, 'create-room'), isTrue);
  });

  testWidgets('opening the room lands in its waiting room as p1', (
    tester,
  ) async {
    final store = FakeRoomStore();
    await openApp(tester, store, '/room/create', uid: 'me');
    await typeInto(tester, 'room-name', 'ต้น');
    await tapKey(tester, 'create-room');
    await tester.pumpAndSettle();
    expect(find.text('ห้องรอ'), findsOneWidget);
    expect(find.byKey(const ValueKey('seat-p1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('seat-p1')),
        matching: find.text('ต้น'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the room is made as the form says', (tester) async {
    final store = FakeRoomStore();
    await openApp(tester, store, '/room/create', uid: 'me');
    await typeInto(tester, 'room-name', 'ต้น');
    await typeInto(tester, 'start-cash', '2000');
    await typeInto(tester, 'go-cash', '300');
    for (var i = 0; i < 3; i++) {
      await tapKey(tester, 'seats-minus');
    }
    await tester.tap(find.text('ตั้งรหัสผ่านห้อง'));
    await tester.pump();
    await typeInto(tester, 'room-password', 'abcd');
    await tester.tap(find.text('ให้ผู้ชมเข้าได้'));
    await tester.tap(find.text('ซ่อนยอดคนอื่นบนจอ'));
    await tester.pump();
    await tester.ensureVisible(find.text('ธนาคารมีเงินจำกัด'));
    await tester.tap(find.text('ธนาคารมีเงินจำกัด'));
    await tester.pump();
    await typeInto(tester, 'bank-limit', '20000');
    await tester.ensureVisible(
      find.byKey(ValueKey('color-${playerPalette[3].toARGB32()}')),
    );
    await tester.tap(
      find.byKey(ValueKey('color-${playerPalette[3].toARGB32()}')),
    );
    await tester.pump();
    await tapKey(tester, 'create-room');
    await tester.pumpAndSettle();

    final code = shownCode(tester);
    final meta = (await metaOf(tester, store, code))!;
    expect(meta.settings.startingCash, 2000);
    expect(meta.settings.goAmount, 300);
    expect(meta.settings.maxPlayers, 3);
    expect(meta.settings.allowSpectators, isFalse);
    expect(meta.settings.hideOthers, isTrue);
    expect(meta.settings.bankLimit, 20000);
    expect(meta.hasPassword, isTrue);
    expect(meta.ownerUid, 'me');
    final seats = await repoOn(store, 'me').readSeats(code);
    expect(seats[0]?.name, 'ต้น');
    expect(seats[0]?.color, playerPalette[3].toARGB32());
  });

  testWidgets('a room without a password and with the default options', (
    tester,
  ) async {
    final store = FakeRoomStore();
    await openApp(tester, store, '/room/create', uid: 'me');
    await typeInto(tester, 'room-name', 'ต้น');
    await tapKey(tester, 'create-room');
    await tester.pumpAndSettle();
    final meta = (await metaOf(tester, store, shownCode(tester)))!;
    expect(meta.hasPassword, isFalse);
    expect(meta.settings.maxPlayers, 6);
    expect(meta.settings.allowSpectators, isTrue);
    expect(meta.settings.hideOthers, isFalse);
    expect(meta.settings.bankLimit, isNull);
    expect(meta.settings.startingCash, 1500);
  });

  testWidgets('says that hiding the balances is only on the screen', (
    tester,
  ) async {
    await openApp(tester, FakeRoomStore(), '/room/create');
    await tester.ensureVisible(find.text('ซ่อนยอดคนอื่นบนจอ'));
    expect(find.byKey(const ValueKey('hide-note')), findsNothing);
    await tester.tap(find.text('ซ่อนยอดคนอื่นบนจอ'));
    await tester.pump();
    expect(find.byKey(const ValueKey('hide-note')), findsOneWidget);
    expect(find.textContaining('ซ่อนบนหน้าจอเท่านั้น'), findsOneWidget);
    await tester.tap(find.text('ซ่อนยอดคนอื่นบนจอ'));
    await tester.pump();
    expect(find.byKey(const ValueKey('hide-note')), findsNothing);
  });
}
