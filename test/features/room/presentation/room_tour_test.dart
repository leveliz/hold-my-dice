import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';

import 'room_test_app.dart';

Finder key(String k) => find.byKey(ValueKey(k));

/// The tour's hand never stops moving, so the page cannot "settle".
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String title(WidgetTester tester) =>
    tester.widget<Text>(key('tour-title')).data!;
String count(WidgetTester tester) =>
    tester.widget<Text>(key('tour-step')).data!;
Rect spot(WidgetTester tester) => tester.getRect(key('tour-spot-0'));

Future<void> next(WidgetTester tester) async {
  await tester.tap(key('tour-next'));
  await settle(tester);
}

/// Opens [location] as [uid] with the tours of [tours] (none seen by default).
Future<TourStorage> open(
  WidgetTester tester,
  FakeRoomStore store,
  String location, {
  String uid = 'owner',
  TourStorage? tours,
}) async {
  final storage = tours ?? MemoryTourStorage();
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await openApp(
    tester,
    store,
    location,
    uid: uid,
    overrides: [tourStorageProvider.overrideWithValue(storage)],
    animated: true,
  );
  await settle(tester);
  return storage;
}

void main() {
  late FakeRoomStore store;
  late String code;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    store = FakeRoomStore();
    code = await makeRoom(store);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
  });

  group('the tour of the waiting room', () {
    testWidgets('opens for the owner with five steps', (tester) async {
      await open(tester, store, '/room/$code');
      expect(key('tour-card'), findsOneWidget);
      expect(title(tester), 'รหัสห้อง');
      expect(count(tester), '1/5');
    });

    testWidgets('lights up the code, the buttons, the QR, the seats, start', (
      tester,
    ) async {
      await open(tester, store, '/room/$code');
      final lit = <String, Finder>{
        'รหัสห้อง': key('code-tiles'),
        'คัดลอกและซ่อนรหัส': key('copy-code'),
        'QR และลิงก์': key('room-qr'),
        'ที่นั่ง': key('seat-count'),
        'เริ่มเกม': key('start-room'),
      };
      for (final entry in lit.entries) {
        expect(title(tester), entry.key);
        expect(
          spot(tester).contains(tester.getCenter(entry.value)),
          isTrue,
          reason: entry.key,
        );
        if (entry.key != 'เริ่มเกม') await next(tester);
      }
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
    });

    testWidgets('a guest has no start step', (tester) async {
      await open(tester, store, '/room/$code', uid: 'u2');
      expect(count(tester), '1/4');
      for (var i = 0; i < 3; i++) {
        await next(tester);
      }
      expect(title(tester), 'ที่นั่ง');
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
    });

    testWidgets('does not open for someone who has seen it', (tester) async {
      await open(
        tester,
        store,
        '/room/$code',
        tours: MemoryTourStorage()..markSeen([TourIds.roomLobby]),
      );
      expect(key('tour-card'), findsNothing);
    });

    testWidgets('finishing it remembers it', (tester) async {
      final tours = await open(tester, store, '/room/$code');
      for (var i = 0; i < 4; i++) {
        await next(tester);
      }
      await next(tester);
      expect(key('tour-card'), findsNothing);
      expect(tours.isSeen(TourIds.roomLobby), isTrue);
      expect(tours.isSeen(TourIds.roomPlay), isFalse);
    });

    testWidgets('skipping it remembers it too', (tester) async {
      final tours = await open(tester, store, '/room/$code');
      await tester.tap(key('tour-skip'));
      await settle(tester);
      expect(key('tour-card'), findsNothing);
      expect(tours.isSeen(TourIds.roomLobby), isTrue);
    });

    testWidgets('fits a small screen', (tester) async {
      await open(tester, store, '/room/$code');
      tester.view.physicalSize = const Size(320, 640);
      await settle(tester);
      // Whatever does not fit is left out of the tour; the rest still runs.
      expect(key('tour-card'), findsOneWidget);
      for (var i = 0; i < 6 && key('tour-next').evaluate().isNotEmpty; i++) {
        await next(tester);
      }
      expect(key('tour-card'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the tour of the game', () {
    Future<void> started() async {
      await repoOn(store, 'owner').startGame(code);
    }

    testWidgets('opens for a player with five steps', (tester) async {
      await started();
      await open(tester, store, '/room/$code', uid: 'u2');
      expect(key('tour-card'), findsOneWidget);
      expect(title(tester), 'ยอดของฉัน');
      expect(count(tester), '1/5');
    });

    testWidgets('lights up the balance, the buttons, a friend, history, end', (
      tester,
    ) async {
      await started();
      await open(tester, store, '/room/$code', uid: 'u2');
      final lit = <String, Finder>{
        'ยอดของฉัน': key('my-balance-card'),
        'รับ จ่าย และ GO': key('press-go'),
        'โอนและเรียกเก็บ': key('friend-p1'),
        'ประวัติ': key('history-strip'),
        'จบเกม': key('end-game'),
      };
      for (final entry in lit.entries) {
        expect(title(tester), entry.key);
        expect(
          spot(tester).contains(tester.getCenter(entry.value)),
          isTrue,
          reason: entry.key,
        );
        if (entry.key != 'จบเกม') await next(tester);
      }
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
    });

    testWidgets('a watcher is shown only what a watcher has', (tester) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      await started();
      await open(tester, store, '/room/$code', uid: 's1');
      expect(count(tester), '1/2');
      expect(title(tester), 'โอนและเรียกเก็บ');
      await next(tester);
      expect(title(tester), 'ประวัติ');
      expect(find.text('เข้าใจแล้ว'), findsOneWidget);
    });

    testWidgets('does not open for someone who has seen it', (tester) async {
      await started();
      await open(
        tester,
        store,
        '/room/$code',
        uid: 'u2',
        tours: MemoryTourStorage()..markSeen([TourIds.roomPlay]),
      );
      expect(key('tour-card'), findsNothing);
    });

    testWidgets('does not come back once it was finished', (tester) async {
      await started();
      final tours = await open(tester, store, '/room/$code', uid: 'u2');
      for (var i = 0; i < 4; i++) {
        await next(tester);
      }
      await next(tester);
      expect(tours.isSeen(TourIds.roomPlay), isTrue);
      await open(tester, store, '/room/$code', uid: 'u2', tours: tours);
      expect(key('tour-card'), findsNothing);
    });

    testWidgets('fits a small screen', (tester) async {
      await started();
      await open(tester, store, '/room/$code', uid: 'u2');
      tester.view.physicalSize = const Size(320, 640);
      await settle(tester);
      expect(key('tour-card'), findsOneWidget);
      for (var i = 0; i < 6 && key('tour-next').evaluate().isNotEmpty; i++) {
        await next(tester);
      }
      expect(key('tour-card'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the tours can be shown again', () {
    test('the settings page resets them with those of Pocket Banker', () {
      expect(
        TourIds.of('bank'),
        containsAll([TourIds.roomLobby, TourIds.roomPlay]),
      );
    });
  });
}
