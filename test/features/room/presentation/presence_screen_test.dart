import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';

import 'room_test_app.dart';

void main() {
  late DateTime clock;
  late FakeRoomStore store;
  late String code;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    clock = DateTime.utc(2026, 10, 25, 12);
    store = FakeRoomStore(now: () => clock);
    code = await makeRoom(store);
  });

  /// Lets [time] pass for the app's timers and for the room's clock.
  Future<void> wait(WidgetTester tester, Duration time) async {
    clock = clock.add(time);
    await tester.pump(time);
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('a member in the waiting room beats at once and every minute', (
    tester,
  ) async {
    clock = clock.add(const Duration(minutes: 10));
    final opened = clock;
    await openApp(tester, store, '/room/$code', uid: 'owner');
    expect(store.lastSeen(code, 'owner'), opened);
    await wait(tester, const Duration(seconds: 59));
    expect(store.lastSeen(code, 'owner'), opened);
    await wait(tester, const Duration(seconds: 1));
    expect(store.lastSeen(code, 'owner'), clock);
    final second = clock;
    await wait(tester, const Duration(seconds: 60));
    expect(store.lastSeen(code, 'owner'), isNot(second));
    expect(store.lastSeen(code, 'owner'), clock);
    await leave(tester);
  });

  testWidgets('someone who has not joined sends no beats', (tester) async {
    await openApp(tester, store, '/room/$code', uid: 'visitor');
    await wait(tester, const Duration(minutes: 3));
    expect(store.lastSeen(code, 'visitor'), isNull);
    await leave(tester);
  });

  testWidgets('a spectator beats too', (tester) async {
    await repoOn(
      store,
      's1',
    ).joinAsSpectator(code: code, name: 'ดู', color: 0xFF2E9E57);
    clock = clock.add(const Duration(minutes: 5));
    final opened = clock;
    await openApp(tester, store, '/room/$code', uid: 's1');
    expect(store.lastSeen(code, 's1'), opened);
    await wait(tester, const Duration(seconds: 61));
    expect(store.lastSeen(code, 's1'), clock);
    await leave(tester);
  });

  testWidgets('the beats go on after the game starts', (tester) async {
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await openApp(tester, store, '/room/$code', uid: 'u2');
    await repoOn(store, 'owner').startGame(code);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('room-playing')), findsOneWidget);
    await wait(tester, const Duration(seconds: 61));
    expect(store.lastSeen(code, 'u2'), clock);
    await leave(tester);
  });

  testWidgets('coming back to the app beats at once', (tester) async {
    await openApp(tester, store, '/room/$code', uid: 'owner');
    // The phone slept: no timer fired, the clock moved on.
    clock = clock.add(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(store.lastSeen(code, 'owner'), clock);
    await leave(tester);
  });

  testWidgets('a person whose seat was taken over is told, not left staring', (
    tester,
  ) async {
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await openApp(tester, store, '/room/$code', uid: 'u2');
    expect(find.byKey(const ValueKey('ticket')), findsOneWidget);
    // u2 is silent for 3 minutes (a locked phone) and somebody sits in p2.
    clock = clock.add(const Duration(minutes: 3));
    await repoOn(store, 'u9').claimSeat(code: code, seatId: 'p2');
    // u2's phone wakes up.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket')), findsNothing);
    await leave(tester);
  });

  testWidgets('the same happens on the next regular beat', (tester) async {
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await openApp(tester, store, '/room/$code', uid: 'u2');
    clock = clock.add(const Duration(minutes: 3));
    await repoOn(store, 'u9').claimSeat(code: code, seatId: 'p2');
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('join-seat')), findsOneWidget);
    await leave(tester);
  });

  testWidgets('leaving the room stops the beats and leaves no timer', (
    tester,
  ) async {
    await openApp(tester, store, '/room/$code', uid: 'owner');
    await leave(tester);
    final before = store.lastSeen(code, 'owner');
    await wait(tester, const Duration(minutes: 5));
    expect(store.lastSeen(code, 'owner'), before);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
