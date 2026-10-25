import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/splash/splash_screen.dart';

const _gone = 'ห้องนี้จบแล้วหรือไม่มีอยู่';

Future<String> _makeRoom(FakeRoomStore store) async {
  final meta = await FakeRoomRepository(store, FakeAuthService('owner'))
      .createRoom(
        settings: const RoomSettings(startingCash: 1500, goAmount: 200),
        name: 'เจ้าของ',
        color: 1,
      );
  return meta.code;
}

Future<void> _open(
  WidgetTester tester,
  FakeRoomStore store,
  String location,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        roomRepositoryProvider.overrideWithValue(
          FakeRoomRepository(store, FakeAuthService('visitor')),
        ),
      ],
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

  testWidgets('a room link opens the join screen with that code', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await _makeRoom(store);
    await _open(tester, store, '/room/$code');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('join-code'))).data,
      code,
    );
    expect(find.text(_gone), findsNothing);
  });

  testWidgets('opening a room link skips the splash', (tester) async {
    final store = FakeRoomStore();
    final code = await _makeRoom(store);
    await _open(tester, store, '/room/$code');
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('a lower case code with spaces and dashes is normalised', (
    tester,
  ) async {
    final store = FakeRoomStore();
    final code = await _makeRoom(store);
    final typed = '${code.substring(0, 3)}-${code.substring(3)}'.toLowerCase();
    await _open(tester, store, '/room/${Uri.encodeComponent(typed)}');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('join-code'))).data,
      code,
    );
  });

  testWidgets('a code that cannot be a code shows the not-found message', (
    tester,
  ) async {
    final store = FakeRoomStore();
    await _open(tester, store, '/room/hello');
    expect(find.text(_gone), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('a room that does not exist shows the not-found message', (
    tester,
  ) async {
    final store = FakeRoomStore();
    await _open(tester, store, '/room/ABC234');
    expect(find.text(_gone), findsOneWidget);
  });
}
