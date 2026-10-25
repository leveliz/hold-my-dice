import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

import 'room_test_app.dart';

Finder inSeat(String id, Finder what) =>
    find.descendant(of: find.byKey(ValueKey('seat-$id')), matching: what);

Future<void> join(WidgetTester tester, {String name = 'เบนซ์'}) async {
  await typeInto(tester, 'join-name', name);
  await tester.ensureVisible(find.byKey(const ValueKey('join-seat')));
  await tester.tap(find.byKey(const ValueKey('join-seat')));
  await tester.pumpAndSettle();
}

Future<void> addPlayer(FakeRoomStore store, String code, String uid) => repoOn(
  store,
  uid,
).joinAsPlayer(code: code, name: 'คน $uid', color: 0xFFE11D48);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a newcomer sees who invited them and how full the room is', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code');
    expect(find.text('ต้น ชวนคุณเข้าห้อง'), findsOneWidget);
    expect(find.text(code), findsOneWidget);
    expect(find.text('1 / 4 ที่นั่ง'), findsOneWidget);
    expect(find.text('มีรหัสผ่าน'), findsNothing);
    expect(find.byKey(const ValueKey('join-password')), findsNothing);
    expect(find.byKey(const ValueKey('ticket')), findsNothing);
  });

  testWidgets('sitting down needs a name and puts them in the waiting room', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'bens');
    expect(isEnabled(tester, 'join-seat'), isFalse);
    await typeInto(tester, 'join-name', '  ');
    expect(isEnabled(tester, 'join-seat'), isFalse);
    await join(tester);
    expect(find.text('ห้องรอ'), findsOneWidget);
    expect(inSeat('p2', find.text('เบนซ์')), findsOneWidget);
    expect(inSeat('p2', find.text('คุณ')), findsOneWidget);
    expect(inSeat('p1', find.text('ต้น')), findsOneWidget);
    expect(find.text('รอเจ้าของห้องเริ่มเกม'), findsOneWidget);
  });

  testWidgets('the colour they pick is the colour of their seat', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'bens');
    final swatches = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('color-'),
    );
    await tester.ensureVisible(swatches.at(4));
    await tester.tap(swatches.at(4));
    await tester.pump();
    final picked = (tester.widget(swatches.at(4)).key! as ValueKey<String>)
        .value
        .substring('color-'.length);
    await join(tester);
    final seats = await repoOn(store, 'bens').readSeats(code);
    expect(seats[1]?.color.toString(), picked);
  });

  testWidgets('a newcomer starts with a colour nobody in the room has', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await addPlayer(store, code, 'u2');
    await openApp(tester, store, '/room/$code', uid: 'bens');
    await join(tester);
    final seats = await repoOn(store, 'bens').readSeats(code);
    final used = {seats[0]!.color, seats[1]!.color};
    expect(used.length, 2, reason: 'owner and u2 differ');
    expect(seats[2]!.color, isNot(isIn(used)));
  });

  testWidgets('a room with a password asks for it', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store, password: 'abcd');
    await openApp(tester, store, '/room/$code', uid: 'bens');
    expect(find.text('มีรหัสผ่าน'), findsOneWidget);
    await typeInto(tester, 'join-name', 'เบนซ์');
    expect(isEnabled(tester, 'join-seat'), isFalse);
    expect(isEnabled(tester, 'join-spectator'), isFalse);
    await typeInto(tester, 'join-password', 'wrong');
    expect(isEnabled(tester, 'join-seat'), isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('join-seat')));
    await tester.tap(find.byKey(const ValueKey('join-seat')));
    await tester.pumpAndSettle();
    expect(snackText(tester), 'รหัสผ่านห้องไม่ถูกต้อง');
    expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
    await typeInto(tester, 'join-password', 'abcd');
    await tester.tap(find.byKey(const ValueKey('join-seat')));
    await tester.pumpAndSettle();
    expect(find.text('ห้องรอ'), findsOneWidget);
  });

  testWidgets('a full room says so and cannot be sat in', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(
      store,
      settings: const RoomSettings(
        startingCash: 1500,
        goAmount: 200,
        maxPlayers: 2,
      ),
    );
    await addPlayer(store, code, 'u2');
    await openApp(tester, store, '/room/$code', uid: 'bens');
    await typeInto(tester, 'join-name', 'เบนซ์');
    expect(find.text('ห้องเต็ม'), findsOneWidget);
    expect(isEnabled(tester, 'join-seat'), isFalse);
  });

  testWidgets('after the start only taking a seat over or watching is left', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await addPlayer(store, code, 'u2');
    await repoOn(store, 'owner').startGame(code);
    await openApp(tester, store, '/room/$code', uid: 'bens');
    expect(find.byKey(const ValueKey('join-seat')), findsNothing);
    expect(find.byKey(const ValueKey('already-started')), findsOneWidget);
    expect(find.byKey(const ValueKey('join-spectator')), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-p2')), findsOneWidget);
  });

  group('watching', () {
    testWidgets('a spectator joins and is counted in the waiting room', (
      tester,
    ) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      await openApp(tester, store, '/room/$code', uid: 's1');
      expect(isEnabled(tester, 'join-spectator'), isFalse);
      await typeInto(tester, 'join-name', 'ดู');
      await tester.ensureVisible(find.byKey(const ValueKey('join-spectator')));
      await tester.tap(find.byKey(const ValueKey('join-spectator')));
      await tester.pumpAndSettle();
      expect(find.text('ห้องรอ'), findsOneWidget);
      expect(find.text('ผู้ชม 1 คน'), findsOneWidget);
      expect(find.text('1 / 4'), findsOneWidget);
    });

    testWidgets('a room without spectators has no such button', (tester) async {
      final store = FakeRoomStore();
      final code = await makeRoom(
        store,
        settings: const RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          allowSpectators: false,
        ),
      );
      await openApp(tester, store, '/room/$code', uid: 's1');
      expect(find.byKey(const ValueKey('join-spectator')), findsNothing);
    });
  });

  group('taking a seat over after losing the phone', () {
    late DateTime clock;
    late FakeRoomStore store;
    late String code;

    setUp(() async {
      clock = DateTime.utc(2026, 10, 25, 12);
      store = FakeRoomStore(now: () => clock);
      code = await makeRoom(store);
      await addPlayer(store, code, 'u2');
    });

    testWidgets('every seat is offered by name', (tester) async {
      await openApp(tester, store, '/room/$code', uid: 'bens');
      expect(find.byKey(const ValueKey('claim-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-p2')), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-p3')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('claimable-p2')),
          matching: find.text('คน u2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a seat whose person was seen a moment ago is refused', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: 'bens');
      clock = clock.add(const Duration(seconds: 30));
      await tester.ensureVisible(find.byKey(const ValueKey('claim-p2')));
      await tester.tap(find.byKey(const ValueKey('claim-p2')));
      await tester.pumpAndSettle();
      expect(snackText(tester), contains('ยังมีคนใช้อยู่'));
      expect(find.byKey(const ValueKey('claim-p2')), findsOneWidget);
    });

    testWidgets('a seat left alone for over 2 minutes is taken over', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: 'bens');
      clock = clock.add(const Duration(minutes: 3));
      await tester.ensureVisible(find.byKey(const ValueKey('claim-p2')));
      await tester.tap(find.byKey(const ValueKey('claim-p2')));
      await tester.pumpAndSettle();
      expect(find.text('ห้องรอ'), findsOneWidget);
      expect(inSeat('p2', find.text('คน u2')), findsOneWidget);
      expect(inSeat('p2', find.text('คุณ')), findsOneWidget);
    });

    testWidgets('the password of the room is needed for that too', (
      tester,
    ) async {
      final secret = await makeRoom(store, password: 'abcd');
      await repoOn(store, 'u2').joinAsPlayer(
        code: secret,
        name: 'คน u2',
        color: 0xFFE11D48,
        password: 'abcd',
      );
      await openApp(tester, store, '/room/$secret', uid: 'bens');
      clock = clock.add(const Duration(minutes: 3));
      expect(isEnabled(tester, 'claim-p2'), isFalse);
      await typeInto(tester, 'join-password', 'abcd');
      expect(isEnabled(tester, 'claim-p2'), isTrue);
    });
  });

  testWidgets('a join that fails shows why and keeps the form', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(
      store,
      settings: const RoomSettings(
        startingCash: 1500,
        goAmount: 200,
        maxPlayers: 2,
      ),
    );
    await openApp(tester, store, '/room/$code', uid: 'bens');
    await typeInto(tester, 'join-name', 'เบนซ์');
    // Somebody else takes the last seat while the form is still open.
    await addPlayer(store, code, 'u2');
    await tester.ensureVisible(find.byKey(const ValueKey('join-seat')));
    await tester.tap(find.byKey(const ValueKey('join-seat')));
    await tester.pumpAndSettle();
    expect(snackText(tester), 'ห้องเต็มแล้ว');
    expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
    expect(find.text('ห้องรอ'), findsNothing);
  });

  testWidgets('the form changes by itself when the owner starts the game', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await addPlayer(store, code, 'u2');
    await openApp(tester, store, '/room/$code', uid: 'bens');
    expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
    await repoOn(store, 'owner').startGame(code);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join-seat')), findsNothing);
    expect(find.byKey(const ValueKey('already-started')), findsOneWidget);
  });
}
