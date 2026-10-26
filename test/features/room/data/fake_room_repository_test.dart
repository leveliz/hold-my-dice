import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

import 'room_repository_contract.dart';

class FakeHarness implements RoomHarness {
  FakeHarness() {
    store = FakeRoomStore(now: () => clock, random: Random(1));
  }

  late final FakeRoomStore store;
  var clock = DateTime.utc(2026, 10, 25, 12);

  @override
  RoomRepository repoFor(String uid) =>
      FakeRoomRepository(store, FakeAuthService(uid));

  @override
  Future<void> advance(Duration time) async => clock = clock.add(time);

  @override
  Future<DateTime?> lastSeen(String code, String uid) async =>
      store.lastSeen(code, uid);
}

void main() {
  roomRepositoryContract(FakeHarness.new);

  group('the fake', () {
    test('rooms made by different calls have different codes', () async {
      final h = FakeHarness();
      const settings = RoomSettings(startingCash: 1500, goAmount: 200);
      final codes = <String>{};
      for (var i = 0; i < 50; i++) {
        final meta = await h
            .repoFor('owner$i')
            .createRoom(settings: settings, name: 'x', color: 1);
        codes.add(meta.code);
      }
      expect(codes.length, 50);
    });

    test('the default providers give a working repository for tests', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final meta = await c
          .read(roomRepositoryProvider)
          .createRoom(
            settings: const RoomSettings(startingCash: 1500, goAmount: 200),
            name: 'x',
            color: 1,
          );
      expect(meta.ownerUid, await c.read(authServiceProvider).ensureSignedIn());
    });

    test('the connection can be cut and restored for every person', () async {
      final h = FakeHarness();
      const settings = RoomSettings(startingCash: 1500, goAmount: 200);
      final meta = await h
          .repoFor('owner')
          .createRoom(settings: settings, name: 'x', color: 1);
      final says = <bool>[];
      final sub = h.repoFor('owner').watchOnline(meta.code).listen(says.add);
      await Future<void>.delayed(Duration.zero);
      h.store.setOnline(false);
      h.store.setOnline(true);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(says, [true, false, true]);
    });

    test('the auth service gives back the uid it was made with', () async {
      expect(await FakeAuthService('abc').ensureSignedIn(), 'abc');
    });

    test('a code already in use is not handed out again', () async {
      final h = FakeHarness();
      const settings = RoomSettings(startingCash: 1500, goAmount: 200);
      // A random source that repeats itself: every code it makes is the same
      // until the store is told to draw again.
      final store = FakeRoomStore(now: () => h.clock, random: _Repeating());
      final a = await FakeRoomRepository(
        store,
        FakeAuthService('a'),
      ).createRoom(settings: settings, name: 'a', color: 1);
      final b = await FakeRoomRepository(
        store,
        FakeAuthService('b'),
      ).createRoom(settings: settings, name: 'b', color: 1);
      expect(b.code, isNot(a.code));
    });
  });
}

/// Gives the same six numbers twice (the same code twice), then others.
class _Repeating implements Random {
  var _calls = 0;

  @override
  int nextInt(int max) {
    _calls++;
    return _calls <= 12 ? (((_calls - 1) % 6) * 3) % max : (_calls * 7) % max;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
