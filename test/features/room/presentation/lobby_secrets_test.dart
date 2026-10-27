import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/room/application/room_password.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';

import 'room_test_app.dart';

Finder key(String k) => find.byKey(ValueKey(k));

/// Records what the app puts on the clipboard.
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

/// The letters in the tiles of the room code, as shown.
List<String> tiles(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: key('code-tiles'), matching: find.byType(Text)),
  ))
    t.data!,
];

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the room password on this device', () {
    test('is read back for the room it was kept for', () {
      final s = MemoryRoomPasswordStorage();
      expect(s.read('ABC234'), isNull);
      s.save('ABC234', 'secret');
      s.save('XYZ789', 'other');
      expect(s.read('ABC234'), 'secret');
      expect(s.read('XYZ789'), 'other');
      expect(s.read('NOPE22'), isNull);
    });

    test('a new password for the same room replaces the old one', () {
      final s = MemoryRoomPasswordStorage();
      s.save('ABC234', 'one');
      s.save('ABC234', 'two');
      expect(s.read('ABC234'), 'two');
    });

    test('is forgotten when asked, and the others stay', () {
      final s = MemoryRoomPasswordStorage();
      s.save('ABC234', 'one');
      s.save('XYZ789', 'two');
      s.forget('ABC234');
      expect(s.read('ABC234'), isNull);
      expect(s.read('XYZ789'), 'two');
    });

    test('only the latest five rooms are kept', () {
      final s = MemoryRoomPasswordStorage();
      for (var i = 0; i < 7; i++) {
        s.save('ROOM0$i', 'pw$i');
      }
      expect(s.read('ROOM00'), isNull);
      expect(s.read('ROOM01'), isNull);
      for (var i = 2; i < 7; i++) {
        expect(s.read('ROOM0$i'), 'pw$i');
      }
    });

    test(
      'saving a room again makes it the newest, so it is not the first to go',
      () {
        final s = MemoryRoomPasswordStorage();
        for (var i = 0; i < 5; i++) {
          s.save('ROOM0$i', 'pw$i');
        }
        s.save('ROOM00', 'pw0');
        s.save('ROOM05', 'pw5');
        expect(s.read('ROOM00'), 'pw0');
        expect(s.read('ROOM01'), isNull);
      },
    );

    test('data that is not a list of passwords is ignored', () {
      final store = MemoryJsonStore()
        ..putRaw(RoomPasswordStorage.key, '{"items":"nope"}');
      expect(RoomPasswordStorage(store).read('ABC234'), isNull);
      final mixed = MemoryJsonStore()
        ..putRaw(
          RoomPasswordStorage.key,
          '{"items":[1,{"code":"ABC234"},{"code":"ABC234","password":"ok"}]}',
        );
      expect(RoomPasswordStorage(mixed).read('ABC234'), 'ok');
    });
  });

  group('the waiting room of a room with a password', () {
    late FakeRoomStore store;
    late RoomPasswordStorage passwords;
    late String code;

    setUp(() async {
      store = FakeRoomStore();
      passwords = MemoryRoomPasswordStorage();
      code = await makeRoom(store, password: 'secret');
    });

    Future<void> open(WidgetTester tester, {String uid = 'owner'}) => openApp(
      tester,
      store,
      '/room/$code',
      uid: uid,
      overrides: [roomPasswordStorageProvider.overrideWithValue(passwords)],
    );

    testWidgets('shows the owner the password they set on this device', (
      tester,
    ) async {
      passwords.save(code, 'secret');
      await open(tester);
      expect(key('room-password-row'), findsOneWidget);
      expect(find.textContaining('secret'), findsOneWidget);
    });

    testWidgets('says so when this device does not know the password', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('ไม่ทราบรหัสผ่านบนเครื่องนี้'), findsOneWidget);
      expect(key('copy-password'), findsNothing);
    });

    testWidgets('does not show it to a player who is not the owner', (
      tester,
    ) async {
      passwords.save(code, 'secret');
      await repoOn(
        store,
        'u2',
      ).joinAsPlayer(code: code, name: 'แพร', color: 1, password: 'secret');
      await open(tester, uid: 'u2');
      expect(key('room-password-row'), findsNothing);
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets('copies the password', (tester) async {
      passwords.save(code, 'secret');
      final copied = captureClipboard(tester);
      await open(tester);
      await tester.tap(key('copy-password'));
      await tester.pump();
      expect(copied, ['secret']);
      expect(snackText(tester), 'คัดลอกรหัสผ่านแล้ว');
    });

    testWidgets(
      'hides the code and the password together, and shows them again',
      (tester) async {
        passwords.save(code, 'secret');
        await open(tester);
        expect(tiles(tester).join(), code);
        expect(find.text('ซ่อนรหัส'), findsOneWidget);
        await tester.tap(key('toggle-secret'));
        await tester.pump();
        expect(tiles(tester), List.filled(6, '•'));
        expect(find.textContaining('secret'), findsNothing);
        expect(find.textContaining('••••••'), findsOneWidget);
        expect(find.text('แสดงรหัส'), findsOneWidget);
        await tester.tap(key('toggle-secret'));
        await tester.pump();
        expect(tiles(tester).join(), code);
        expect(find.textContaining('secret'), findsOneWidget);
      },
    );

    testWidgets(
      'still copies the real code and password while they are hidden',
      (tester) async {
        passwords.save(code, 'secret');
        final copied = captureClipboard(tester);
        await open(tester);
        await tester.tap(key('toggle-secret'));
        await tester.pump();
        await tester.tap(key('copy-code'));
        await tester.pump();
        await tester.tap(key('copy-password'));
        await tester.pump();
        await tester.tap(key('code-tiles'));
        await tester.pump();
        expect(copied, [code, 'secret', code]);
      },
    );

    testWidgets(
      'the label of the tiles does not give the code away while hidden',
      (tester) async {
        final handle = tester.ensureSemantics();
        await open(tester);
        String label() => tester.getSemantics(key('code-tiles')).label;
        expect(label(), contains('คัดลอกรหัสห้อง'));
        expect(label(), contains(code));
        await tester.tap(key('toggle-secret'));
        await tester.pump();
        expect(label(), contains('คัดลอกรหัสห้อง'));
        expect(RegExp('[A-Z2-9]').hasMatch(label()), isFalse, reason: label());
        handle.dispose();
      },
    );
  });

  group('the waiting room of a room without a password', () {
    testWidgets('has the copy and hide buttons and no password row', (
      tester,
    ) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      final copied = captureClipboard(tester);
      await openApp(tester, store, '/room/$code', uid: 'owner');
      expect(key('room-password-row'), findsNothing);
      await tester.tap(key('copy-code'));
      await tester.pump();
      expect(copied, [code]);
      expect(snackText(tester), 'คัดลอกรหัสแล้ว');
      await tester.tap(key('toggle-secret'));
      await tester.pump();
      expect(tiles(tester), List.filled(6, '•'));
    });

    testWidgets('fits a narrow screen', (tester) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store, password: 'secret');
      await openApp(
        tester,
        store,
        '/room/$code',
        uid: 'owner',
        overrides: [
          roomPasswordStorageProvider.overrideWithValue(
            MemoryRoomPasswordStorage()..save(code, 'a-long-password-12345'),
          ),
        ],
      );
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the password is kept when the owner makes the room', () {
    testWidgets('with a password: it is there in the waiting room', (
      tester,
    ) async {
      final store = FakeRoomStore();
      final passwords = MemoryRoomPasswordStorage();
      await openApp(
        tester,
        store,
        '/room/create',
        uid: 'me',
        overrides: [roomPasswordStorageProvider.overrideWithValue(passwords)],
      );
      await tester.enterText(key('room-name'), 'ต้น');
      await tester.pump();
      await tester.ensureVisible(find.text('ตั้งรหัสผ่านห้อง'));
      await tester.tap(find.text('ตั้งรหัสผ่านห้อง'));
      await tester.pump();
      await tester.enterText(key('room-password'), 'abcd');
      await tester.pump();
      await tester.ensureVisible(key('create-room'));
      await tester.tap(key('create-room'));
      await tester.pumpAndSettle();
      expect(key('room-password-row'), findsOneWidget);
      expect(find.textContaining('abcd'), findsOneWidget);
    });

    testWidgets('without a password: nothing is kept', (tester) async {
      final store = FakeRoomStore();
      final json = MemoryJsonStore();
      final passwords = RoomPasswordStorage(json);
      await openApp(
        tester,
        store,
        '/room/create',
        uid: 'me',
        overrides: [roomPasswordStorageProvider.overrideWithValue(passwords)],
      );
      await tester.enterText(key('room-name'), 'ต้น');
      await tester.pump();
      await tester.ensureVisible(key('create-room'));
      await tester.tap(key('create-room'));
      await tester.pumpAndSettle();
      expect(key('room-password-row'), findsNothing);
      expect(json.read(RoomPasswordStorage.key), isNull);
    });
  });

  testWidgets('deleting the waiting room forgets its password', (tester) async {
    final store = FakeRoomStore();
    final passwords = MemoryRoomPasswordStorage();
    final code = await makeRoom(store, password: 'secret');
    passwords.save(code, 'secret');
    await openApp(
      tester,
      store,
      '/room/$code',
      uid: 'owner',
      overrides: [roomPasswordStorageProvider.overrideWithValue(passwords)],
    );
    await tester.tap(find.textContaining('ลบห้องนี้').first);
    await tester.pumpAndSettle();
    await tester.tap(key('delete-room-confirm'));
    await tester.pumpAndSettle();
    expect(passwords.read(code), isNull);
  });
}
