import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/core/widgets/dashed_line.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'room_test_app.dart';

Finder inSeat(String id, Finder what) =>
    find.descendant(of: find.byKey(ValueKey('seat-$id')), matching: what);

String seatCount(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('seat-count')),
        matching: find.byType(Text),
      ),
    )
    .data!;

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

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the owner sees the ticket, the seats and who is who', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'owner');
    expect(find.text('ห้องรอ'), findsOneWidget);
    expect(find.text('ห้องของ ต้น'), findsOneWidget);
    for (final letter in code.split('')) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('code-tiles')),
          matching: find.text(letter),
        ),
        findsWidgets,
      );
    }
    expect(find.byType(QrImageView), findsOneWidget);
    expect(inSeat('p1', find.text('ต้น')), findsOneWidget);
    expect(inSeat('p1', find.text('เจ้าของห้อง')), findsOneWidget);
    expect(inSeat('p1', find.text('คุณ')), findsOneWidget);
    expect(seatCount(tester), '1 / 4');
    for (final id in ['p2', 'p3', 'p4']) {
      expect(inSeat(id, find.text('ว่าง')), findsOneWidget, reason: id);
    }
    expect(find.byKey(const ValueKey('seat-p5')), findsNothing);
    expect(find.text('สด'), findsOneWidget);
  });

  testWidgets('the ticket is notched on both sides at the perforation', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'owner');
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const ValueKey('ticket')),
                    matching: find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is TicketPainter,
                    ),
                  ),
                )
                .painter!
            as TicketPainter;
    final line = tester.getTopLeft(
      find.descendant(
        of: find.byKey(const ValueKey('ticket')),
        matching: find.byType(DashedLine),
      ),
    );
    final top = tester.getTopLeft(find.byKey(const ValueKey('ticket')));
    // The notches are centred on the dashed line (1.5 thick).
    expect(painter.notchY, closeTo(line.dy - top.dy + 0.75, 0.5));
    expect(painter.notchRadius, greaterThan(0));
  });

  testWidgets('only the owner wears the owner chip', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await openApp(tester, store, '/room/$code', uid: 'u2');
    expect(inSeat('p1', find.text('เจ้าของห้อง')), findsOneWidget);
    expect(inSeat('p2', find.text('เจ้าของห้อง')), findsNothing);
    expect(find.text('เจ้าของห้อง'), findsOneWidget);
  });

  testWidgets('the QR carries the link of the room', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'owner');
    expect(
      tester.widget<RoomQr>(find.byType(RoomQr)).data,
      roomShareLink(code),
    );
    expect(roomShareLink(code), 'https://hold-my-dice.pages.dev/room/$code');
  });

  testWidgets('copying the link and the code puts them on the clipboard', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final copied = captureClipboard(tester);
    await openApp(tester, store, '/room/$code', uid: 'owner');
    await tester.tap(find.byKey(const ValueKey('copy-link')));
    await tester.pump();
    expect(copied, [roomShareLink(code)]);
    expect(snackText(tester), 'คัดลอกลิงก์แล้ว');
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('code-tiles')));
    await tester.pumpAndSettle();
    expect(copied.last, code);
    expect(snackText(tester), 'คัดลอกรหัสแล้ว');
  });

  testWidgets('a newcomer appears in the list at once', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'owner');
    expect(inSeat('p2', find.text('แพร')), findsNothing);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await tester.pumpAndSettle();
    expect(inSeat('p2', find.text('แพร')), findsOneWidget);
    expect(inSeat('p2', find.text('คุณ')), findsNothing);
    expect(seatCount(tester), '2 / 4');
  });

  testWidgets(
    'the owner starts only with two players and then the game opens',
    (tester) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      await openApp(tester, store, '/room/$code', uid: 'owner');
      expect(find.text('เริ่มเกม (1 คน)'), findsOneWidget);
      expect(isEnabled(tester, 'start-room'), isFalse);
      await repoOn(
        store,
        'u2',
      ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
      await tester.pumpAndSettle();
      expect(find.text('เริ่มเกม (2 คน)'), findsOneWidget);
      expect(isEnabled(tester, 'start-room'), isTrue);
      await tester.tap(find.byKey(const ValueKey('start-room')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-playing')), findsOneWidget);
      expect((await metaOf(tester, store, code))?.status, RoomStatus.playing);
    },
  );

  testWidgets('another player waits for the owner and cannot start', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await openApp(tester, store, '/room/$code', uid: 'u2');
    expect(find.text('รอเจ้าของห้องเริ่มเกม'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-room')), findsNothing);
    expect(inSeat('p2', find.text('คุณ')), findsOneWidget);
    expect(inSeat('p1', find.text('คุณ')), findsNothing);
  });

  group('an owner who is gone', () {
    late DateTime clock;
    late FakeRoomStore store;
    late String code;

    setUp(() async {
      clock = DateTime.utc(2026, 10, 25, 12);
      store = FakeRoomStore(now: () => clock);
      code = await makeRoom(store);
      await repoOn(
        store,
        'u2',
      ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    });

    testWidgets('a member is refused while the owner is still there', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: 'u2');
      clock = clock.add(const Duration(seconds: 30));
      await tester.tap(find.byKey(const ValueKey('claim-owner')));
      await tester.pumpAndSettle();
      expect(snackText(tester), contains('เจ้าของห้องยังอยู่'));
      expect(find.byKey(const ValueKey('start-room')), findsNothing);
    });

    testWidgets('a member takes the room after 2 minutes and can start', (
      tester,
    ) async {
      await openApp(tester, store, '/room/$code', uid: 'u2');
      clock = clock.add(const Duration(minutes: 3));
      await tester.tap(find.byKey(const ValueKey('claim-owner')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('start-room')), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-owner')), findsNothing);
      expect(inSeat('p2', find.text('เจ้าของห้อง')), findsOneWidget);
      expect(inSeat('p1', find.text('เจ้าของห้อง')), findsNothing);
    });

    testWidgets('the owner has no such button', (tester) async {
      await openApp(tester, store, '/room/$code', uid: 'owner');
      expect(find.byKey(const ValueKey('claim-owner')), findsNothing);
    });
  });

  testWidgets('everybody is taken to the game when the owner starts it', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await openApp(tester, store, '/room/$code', uid: 'u2');
    await repoOn(store, 'owner').startGame(code);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('room-playing')), findsOneWidget);
  });

  testWidgets('spectators are counted, not seated', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await openApp(tester, store, '/room/$code', uid: 'owner');
    expect(find.byKey(const ValueKey('spectator-count')), findsNothing);
    await repoOn(
      store,
      's1',
    ).joinAsSpectator(code: code, name: 'ดู', color: 0xFF2E9E57);
    await tester.pumpAndSettle();
    expect(find.text('ผู้ชม 1 คน'), findsOneWidget);
    expect(seatCount(tester), '1 / 4');
  });

  testWidgets('a room that has started shows the game to its members', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await repoOn(store, 'owner').startGame(code);
    await openApp(tester, store, '/room/$code', uid: 'u2');
    expect(find.byKey(const ValueKey('room-playing')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket')), findsNothing);
  });

  group('taking the room down', () {
    testWidgets('only the owner is offered it', (tester) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      await repoOn(store, 'u2').joinAsPlayer(code: code, name: 'แพร', color: 1);
      await openApp(tester, store, '/room/$code', uid: 'u2');
      expect(find.byKey(const ValueKey('delete-room')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await openApp(tester, store, '/room/$code', uid: 'owner');
      expect(find.byKey(const ValueKey('delete-room')), findsOneWidget);
    });

    testWidgets('asks first, and backing out leaves the room as it was', (
      tester,
    ) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      await openApp(tester, store, '/room/$code', uid: 'owner');
      await tester.ensureVisible(find.byKey(const ValueKey('delete-room')));
      await tester.tap(find.byKey(const ValueKey('delete-room')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delete-room-dialog')), findsOneWidget);
      expect(find.textContaining('เอากลับมาไม่ได้'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-room-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delete-room-dialog')), findsNothing);
      expect(find.text('ห้องรอ'), findsOneWidget);
      expect(await metaOf(tester, store, code), isNotNull);
    });

    testWidgets('confirming deletes the room and leaves the waiting room', (
      tester,
    ) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      await openApp(tester, store, '/room/$code', uid: 'owner');
      await tester.ensureVisible(find.byKey(const ValueKey('delete-room')));
      await tester.tap(find.byKey(const ValueKey('delete-room')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-room-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('ห้องรอ'), findsNothing);
      expect(
        find.text('ห้องนี้จบแล้วหรือไม่มีอยู่'),
        findsNothing,
        reason: 'the owner goes home, not to the "gone" page',
      );
      expect(await metaOf(tester, store, code), isNull);
    });

    testWidgets('the others in the waiting room are told it is gone', (
      tester,
    ) async {
      final store = FakeRoomStore();
      final code = await makeRoom(store);
      await repoOn(store, 'u2').joinAsPlayer(code: code, name: 'แพร', color: 1);
      await openApp(tester, store, '/room/$code', uid: 'u2');
      expect(find.text('ห้องรอ'), findsOneWidget);
      await tester.runAsync(() => repoOn(store, 'owner').deleteRoom(code));
      await tester.pumpAndSettle();
      expect(find.text('ห้องนี้จบแล้วหรือไม่มีอยู่'), findsOneWidget);
    });
  });
}
