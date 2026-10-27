import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

import 'room_test_app.dart';

/// A repository that reads every room as one of a newer layout, and counts how
/// often it was asked.
class _NewerLayout extends FakeRoomRepository {
  _NewerLayout(super.store, super.auth);

  var asked = 0;

  @override
  Stream<RoomMeta?> watchMeta(String code) {
    asked++;
    return Stream.error(const RoomException(RoomError.unsupportedVersion));
  }
}

void main() {
  late FakeRoomStore store;
  late String code;
  late _NewerLayout repo;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    store = FakeRoomStore();
    code = await makeRoom(store);
    repo = _NewerLayout(store, FakeAuthService('u2'));
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('a room of a newer layout says the app must be updated', (
    tester,
  ) async {
    await openApp(tester, store, '/room/$code', uid: 'u2', repo: repo);
    expect(find.text('ต้องอัปเดตแอพก่อนเข้าห้องนี้'), findsOneWidget);
    expect(key('room-retry'), findsNothing);
    expect(key('gone-home'), findsOneWidget);
    expect(find.textContaining('ชวนคุณเข้าห้อง'), findsNothing);
  });

  testWidgets('the app does not keep asking while the page stays open', (
    tester,
  ) async {
    await openApp(tester, store, '/room/$code', uid: 'u2', repo: repo);
    final first = repo.asked;
    expect(first, 1);
    await tester.pump(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 10));
    expect(repo.asked, first);
  });

  testWidgets('a room that is not there is still told apart', (tester) async {
    await openApp(tester, store, '/room/ZZZZZZ', uid: 'u2');
    expect(find.text('ห้องนี้จบแล้วหรือไม่มีอยู่'), findsOneWidget);
    expect(find.text('ต้องอัปเดตแอพก่อนเข้าห้องนี้'), findsNothing);
  });

  testWidgets('going home from there works', (tester) async {
    await openApp(tester, store, '/room/$code', uid: 'u2', repo: repo);
    await tester.tap(key('gone-home'));
    await tester.pumpAndSettle();
    expect(find.text('ต้องอัปเดตแอพก่อนเข้าห้องนี้'), findsNothing);
  });
}
