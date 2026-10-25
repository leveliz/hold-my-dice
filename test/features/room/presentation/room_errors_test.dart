import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

import 'room_test_app.dart';

const _gone = 'ห้องนี้จบแล้วหรือไม่มีอยู่';

/// A repository whose reads of the room fail with [error] until it is cleared.
class _Failing extends FakeRoomRepository {
  _Failing(FakeRoomStore store) : super(store, FakeAuthService('visitor'));

  RoomError? error;
  var memberReadFails = false;

  @override
  Stream<RoomMeta?> watchMeta(String code) async* {
    final e = error;
    if (e != null && !memberReadFails) throw RoomException(e);
    yield* super.watchMeta(code);
  }

  @override
  Future<Member?> readMyMember(String code) async {
    final e = error;
    if (e != null && memberReadFails) throw RoomException(e);
    return super.readMyMember(code);
  }
}

Future<void> _open(WidgetTester tester, _Failing repo, String location) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [roomRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light),
        routerConfig: createRouter(initialLocation: location),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('no connection is not the same as a room that has ended', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final repo = _Failing(store)..error = RoomError.offline;
    await _open(tester, repo, '/room/$code');
    expect(find.text('ออฟไลน์อยู่ ลองใหม่เมื่อมีสัญญาณ'), findsOneWidget);
    expect(find.text(_gone), findsNothing);
    expect(find.byKey(const ValueKey('room-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('gone-home')), findsNothing);
  });

  testWidgets('trying again after the signal is back opens the room', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final repo = _Failing(store)..error = RoomError.offline;
    await _open(tester, repo, '/room/$code');
    repo.error = null;
    await tester.tap(find.byKey(const ValueKey('room-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
    expect(find.byKey(const ValueKey('room-retry')), findsNothing);
  });

  testWidgets('trying again while still offline keeps saying so', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final repo = _Failing(store)..error = RoomError.offline;
    await _open(tester, repo, '/room/$code');
    await tester.tap(find.byKey(const ValueKey('room-retry')));
    await tester.pumpAndSettle();
    expect(find.text('ออฟไลน์อยู่ ลองใหม่เมื่อมีสัญญาณ'), findsOneWidget);
  });

  testWidgets('an unexpected failure says something went wrong, not gone', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final repo = _Failing(store)..error = RoomError.unknown;
    await _open(tester, repo, '/room/$code');
    expect(find.text('มีบางอย่างผิดพลาด ลองใหม่อีกครั้ง'), findsOneWidget);
    expect(find.text(_gone), findsNothing);
    expect(find.byKey(const ValueKey('room-retry')), findsOneWidget);
  });

  testWidgets('a failure to read who you are is told the same way', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final repo = _Failing(store)
      ..error = RoomError.offline
      ..memberReadFails = true;
    await _open(tester, repo, '/room/$code');
    expect(find.text('ออฟไลน์อยู่ ลองใหม่เมื่อมีสัญญาณ'), findsOneWidget);
    expect(find.text(_gone), findsNothing);
  });

  testWidgets('trying again also asks again who you are', (tester) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final repo = _Failing(store)
      ..error = RoomError.offline
      ..memberReadFails = true;
    await _open(tester, repo, '/room/$code');
    expect(find.byKey(const ValueKey('room-retry')), findsOneWidget);
    repo.error = null;
    await tester.tap(find.byKey(const ValueKey('room-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
  });

  testWidgets('a room that really is not there still says it has ended', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await makeRoom(store);
    final repo = _Failing(store)..error = RoomError.roomNotFound;
    await _open(tester, repo, '/room/$code');
    expect(find.text(_gone), findsOneWidget);
    expect(find.byKey(const ValueKey('gone-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('room-retry')), findsNothing);
  });
}
