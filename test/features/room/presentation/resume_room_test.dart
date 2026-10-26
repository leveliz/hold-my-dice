import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/room/application/last_room.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';

import 'room_test_app.dart';

LastRoomStorage _remembering(String code) => LastRoomStorage(
  MemoryJsonStore()..putRaw(LastRoomStorage.key, '{"code": "$code"}'),
);

void main() {
  late FakeRoomStore store;
  late String code;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    store = FakeRoomStore();
    code = await makeRoom(store);
  });

  Finder card() => find.byKey(const ValueKey('mode-resume'));

  Future<void> openPicker(
    WidgetTester tester, {
    LastRoomStorage? remembered,
    String uid = 'owner',
  }) => openApp(
    tester,
    store,
    '/bank',
    uid: uid,
    overrides: [
      if (remembered != null)
        lastRoomStorageProvider.overrideWithValue(remembered),
    ],
  );

  testWidgets('a person who was never in a room is offered no way back', (
    tester,
  ) async {
    await openPicker(tester);
    expect(find.text('เล่นกันแบบไหนดี'), findsOneWidget);
    expect(card(), findsNothing);
  });

  testWidgets('the card leads back to the waiting room', (tester) async {
    await openPicker(tester, remembered: _remembering(code));
    expect(card(), findsOneWidget);
    expect(find.text('กลับเข้าห้อง $code'), findsOneWidget);
    expect(find.text('ห้องรอ ยังไม่เริ่มเกม'), findsOneWidget);
    await tester.tap(card());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticket')), findsOneWidget);
  });

  testWidgets('the card leads back to a game in progress', (tester) async {
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await repoOn(store, 'owner').startGame(code);
    await openPicker(tester, remembered: _remembering(code));
    expect(find.text('เกมกำลังเล่นอยู่'), findsOneWidget);
    await tester.tap(card());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('room-playing')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-balance')), findsOneWidget);
  });

  testWidgets('no card for a room that does not exist', (tester) async {
    await openPicker(tester, remembered: _remembering('ZZZZZZ'));
    expect(card(), findsNothing);
  });

  testWidgets('no card when this person has no place in the room', (
    tester,
  ) async {
    await openPicker(tester, remembered: _remembering(code), uid: 'stranger');
    expect(card(), findsNothing);
  });

  testWidgets('being in a room makes the picker offer it next time', (
    tester,
  ) async {
    await openApp(tester, store, '/room/$code', uid: 'owner');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.read(lastRoomProvider), code);
    await tester.pump();
    expect(container.read(lastRoomStorageProvider).read(), code);
  });

  testWidgets('a newcomer who only looks at the join form is not remembered', (
    tester,
  ) async {
    await openApp(tester, store, '/room/$code', uid: 'visitor');
    expect(find.byKey(const ValueKey('join-name')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.read(lastRoomProvider), isNull);
  });
}
