import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

const testSettings = RoomSettings(
  startingCash: 1500,
  goAmount: 200,
  maxPlayers: 4,
);

/// A repository acting as the person [uid] on [store].
FakeRoomRepository repoOn(FakeRoomStore store, String uid) =>
    FakeRoomRepository(store, FakeAuthService(uid));

/// Makes a room as 'owner' and returns its code.
Future<String> makeRoom(
  FakeRoomStore store, {
  RoomSettings settings = testSettings,
  String? password,
}) async => (await repoOn(store, 'owner').createRoom(
  settings: settings,
  password: password,
  name: 'ต้น',
  color: 0xFF3D5AFE,
)).code;

/// Opens the app at [location] as the person [uid], on rooms in [store].
Future<void> openApp(
  WidgetTester tester,
  FakeRoomStore store,
  String location, {
  String uid = 'visitor',
  bool enabled = true,
  List<Override> overrides = const [],
  RoomRepository? repo,

  /// Something on the page never stops moving (a tour's hand), so it cannot
  /// settle: give it a few frames instead.
  bool animated = false,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: roomRetry,
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuthService(uid)),
        roomRepositoryProvider.overrideWithValue(repo ?? repoOn(store, uid)),
        multiDeviceEnabledProvider.overrideWithValue(enabled),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light),
        routerConfig: createRouter(initialLocation: location),
      ),
    ),
  );
  if (animated) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  } else {
    await tester.pumpAndSettle();
  }
}

/// The text of the snack bar on screen, or null.
String? snackText(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );
  return finder.evaluate().isEmpty
      ? null
      : tester.widget<Text>(finder.first).data;
}

Matcher throwsRoom(RoomError e) =>
    throwsA(isA<RoomException>().having((x) => x.error, 'error', e));

/// The room document as [store] holds it now.
Future<RoomMeta?> metaOf(
  WidgetTester tester,
  FakeRoomStore store,
  String code,
) async {
  RoomMeta? meta;
  var got = false;
  final sub = repoOn(store, 'owner').watchMeta(code).listen((m) {
    meta = m;
    got = true;
  });
  for (var i = 0; i < 5 && !got; i++) {
    await tester.pump();
  }
  unawaited(sub.cancel());
  return meta;
}

/// Types [text] into the text field inside the widget with [key].
Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pump();
}

bool isEnabled(WidgetTester tester, String key) {
  final w = tester.widget(find.byKey(ValueKey(key)));
  return switch (w) {
    ButtonStyleButton() => w.onPressed != null,
    _ => throw ArgumentError('not a button: $key'),
  };
}
