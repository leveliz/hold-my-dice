import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/requests_control.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

const _settings = RoomSettings(
  startingCash: 1500,
  goAmount: 200,
  maxPlayers: 4,
);

/// Shows every request as if the server had not given it a time yet.
class _NoTime extends FakeRoomRepository {
  _NoTime(super.store, super.auth);

  @override
  Stream<List<RoomRequest>> watchRequests(String code) => super
      .watchRequests(code)
      .map(
        (all) => [
          for (final r in all)
            RoomRequest(
              id: r.id,
              fromSeat: r.fromSeat,
              toSeat: r.toSeat,
              amount: r.amount,
              status: r.status,
            ),
        ],
      );
}

class _World {
  _World(this.async, this.store, this.code, this.container, this.clock);

  final FakeAsync async;
  final FakeRoomStore store;
  final String code;
  final ProviderContainer container;
  final DateTime Function() clock;

  FakeRoomRepository repo(String uid) =>
      FakeRoomRepository(store, FakeAuthService(uid));

  RequestsState get now => container.read(requestsControllerProvider(code));
  RequestsController get controller =>
      container.read(requestsControllerProvider(code).notifier);

  /// Runs [f] to its end.
  void run(Future<void> Function() f) {
    var done = false;
    Object? error;
    unawaited(f().then((_) => done = true, onError: (Object e) => error = e));
    async.flushMicrotasks();
    if (error != null) throw error!;
    expect(done, isTrue, reason: 'the future did not finish');
  }

  void ask(String uid, String from, int amount) {
    run(() => repo(uid).requestMoney(code, fromSeat: from, amount: amount));
    async.elapse(const Duration(milliseconds: 1));
  }
}

/// A started room of four ('owner' p1, u2 p2, u3 p3, u4 p4) and a container
/// acting as [uid].
void _inWorld(
  String name,
  void Function(FakeAsync async, _World w) body, {
  String uid = 'owner',
  bool noTime = false,
}) {
  test(name, () {
    FakeAsync().run((async) {
      // A clock that moves with the fake time of the test.
      final fakeClock = async.getClock(DateTime.utc(2026, 10, 26, 12));
      DateTime clock() => fakeClock.now();
      final store = FakeRoomStore(now: clock);
      void setup(Future<void> Function() step) {
        var done = false;
        unawaited(step().then((_) => done = true));
        async.flushMicrotasks();
        expect(done, isTrue);
      }

      late String code;
      setup(() async {
        final owner = FakeRoomRepository(store, FakeAuthService('owner'));
        final meta = await owner.createRoom(
          settings: _settings,
          name: 'ต้น',
          color: 1,
        );
        code = meta.code;
        for (final u in ['u2', 'u3', 'u4']) {
          await FakeRoomRepository(
            store,
            FakeAuthService(u),
          ).joinAsPlayer(code: code, name: 'คน $u', color: 2);
        }
        await owner.startGame(code);
        await FakeRoomRepository(
          store,
          FakeAuthService('s1'),
        ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      });
      final repo = noTime
          ? _NoTime(store, FakeAuthService(uid))
          : FakeRoomRepository(store, FakeAuthService(uid));
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(FakeAuthService(uid)),
          roomRepositoryProvider.overrideWithValue(repo),
          roomClockProvider.overrideWithValue(clock),
        ],
      );
      container.listen(roomGameProvider(code), (_, _) {});
      container.listen(requestsControllerProvider(code), (_, _) {});
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      final w = _World(async, store, code, container, clock);
      body(async, w);
      container.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty, reason: 'no timer left behind');
    });
  });
}

void main() {
  group('requestIsStale', () {
    final t = DateTime.utc(2026, 10, 26, 12);

    test('a request of a moment ago is not', () {
      expect(
        requestIsStale(createdAt: t, newestServerTime: t, now: t),
        isFalse,
      );
    });

    test('one that the server clock has left behind by over 2 minutes is', () {
      expect(
        requestIsStale(
          createdAt: t,
          newestServerTime: t.add(const Duration(minutes: 2, seconds: 1)),
          now: t,
        ),
        isTrue,
        reason: 'a later entry says so, whatever this phone thinks',
      );
      expect(
        requestIsStale(
          createdAt: t,
          newestServerTime: t.add(const Duration(minutes: 1, seconds: 59)),
          now: t,
        ),
        isFalse,
      );
    });

    test(
      'with nothing newer to go by, this phone\'s clock decides, with slack',
      () {
        expect(
          requestIsStale(
            createdAt: t,
            newestServerTime: null,
            now: t.add(const Duration(minutes: 3)),
          ),
          isFalse,
          reason: 'a minute of slack for a clock that is a little off',
        );
        expect(
          requestIsStale(
            createdAt: t,
            newestServerTime: null,
            now: t.add(const Duration(minutes: 3, seconds: 1)),
          ),
          isTrue,
        );
      },
    );
  });

  _inWorld(
    'a request of somebody who went out is not offered, nor waited for',
    (async, w) {
      w.ask('u3', 'p1', 300);
      w.ask('owner', 'p2', 200);
      expect(w.now.incoming.map((p) => p.request.id), ['p3_p1']);
      expect(w.now.outgoing.map((p) => p.request.id), ['p1_p2']);
      w.run(() => w.repo('u3').submitEntry(w.code, EntryDraft.bankrupt(2000)));
      async.elapse(const Duration(milliseconds: 1));
      expect(w.now.incoming, isEmpty);
      w.run(() => w.repo('u2').submitEntry(w.code, EntryDraft.bankrupt(2000)));
      async.elapse(const Duration(milliseconds: 1));
      expect(w.now.outgoing, isEmpty);
      expect(
        w.now.notice,
        isNull,
        reason: 'it did not "run out", the asked left',
      );
    },
  );

  _inWorld('nothing is asked at first', (async, w) {
    async.flushMicrotasks();
    expect(w.now.incoming, isEmpty);
    expect(w.now.outgoing, isEmpty);
    expect(w.now.notice, isNull);
  });

  _inWorld('a request made of me waits for my answer, for 2 minutes', (
    async,
    w,
  ) {
    w.ask('u2', 'p1', 300);
    async.flushMicrotasks();
    final p = w.now.incoming.single;
    expect(p.request.id, 'p2_p1');
    expect(p.request.amount, 300);
    final left = p.deadline.difference(w.clock());
    expect(left, lessThanOrEqualTo(const Duration(minutes: 2)));
    expect(left, greaterThan(const Duration(minutes: 1, seconds: 59)));
    expect(w.now.outgoing, isEmpty);
  });

  _inWorld('a request I made waits for the answer of the other', (async, w) {
    w.ask('owner', 'p2', 80);
    async.flushMicrotasks();
    expect(w.now.outgoing.single.request.id, 'p1_p2');
    expect(w.now.incoming, isEmpty);
  });

  _inWorld('requests between other people are not mine', (async, w) {
    w.ask('u3', 'p4', 10);
    async.flushMicrotasks();
    expect(w.now.incoming, isEmpty);
    expect(w.now.outgoing, isEmpty);
  });

  _inWorld('a spectator has nothing to answer and nothing waiting', (async, w) {
    w.ask('u2', 'p1', 300);
    async.flushMicrotasks();
    expect(w.now.incoming, isEmpty);
    expect(w.now.outgoing, isEmpty);
  }, uid: 's1');

  _inWorld('requests come in the order they were first seen', (async, w) {
    w.ask('u3', 'p1', 30);
    async.flushMicrotasks();
    async.elapse(const Duration(seconds: 10));
    w.ask('u2', 'p1', 20);
    async.flushMicrotasks();
    expect(w.now.incoming.map((p) => p.request.id), ['p3_p1', 'p2_p1']);
  });

  _inWorld('after 2 minutes a request is no longer offered', (async, w) {
    w.ask('u2', 'p1', 300);
    async.flushMicrotasks();
    async.elapse(const Duration(minutes: 1, seconds: 59));
    expect(w.now.incoming, hasLength(1));
    async.elapse(const Duration(seconds: 2));
    expect(w.now.incoming, isEmpty);
    expect(w.now.notice, isNull, reason: 'it was not mine');
  });

  _inWorld('a request of mine that runs out says so', (async, w) {
    w.ask('owner', 'p2', 80);
    async.flushMicrotasks();
    async.elapse(const Duration(minutes: 2, seconds: 1));
    expect(w.now.outgoing, isEmpty);
    expect(w.now.notice?.text, 'คำขอหมดอายุ');
  });

  _inWorld('a request of mine that the other cancels says so', (async, w) {
    w.ask('owner', 'p2', 80);
    async.flushMicrotasks();
    w.run(() => w.repo('u2').cancelRequest(w.code, 'p1_p2'));
    async.flushMicrotasks();
    expect(w.now.outgoing, isEmpty);
    expect(w.now.notice?.text, 'คำขอถูกยกเลิก');
  });

  _inWorld('a request of mine that I cancel myself says so too', (async, w) {
    w.ask('owner', 'p2', 80);
    async.flushMicrotasks();
    w.run(() => w.repo('owner').cancelRequest(w.code, 'p1_p2'));
    async.flushMicrotasks();
    expect(w.now.notice?.text, 'คำขอถูกยกเลิก');
  });

  _inWorld('a request of mine that is paid is not announced here', (async, w) {
    w.ask('owner', 'p2', 80);
    async.flushMicrotasks();
    w.run(() => w.repo('u2').payRequest(w.code, 'p1_p2', cid: 'cidcidcid1234'));
    async.flushMicrotasks();
    expect(w.now.outgoing, isEmpty);
    expect(w.now.notice, isNull, reason: 'the money arriving says it');
  });

  _inWorld('one I answered is gone from my list', (async, w) {
    w.ask('u2', 'p1', 300);
    async.flushMicrotasks();
    w.run(() => w.repo('owner').cancelRequest(w.code, 'p2_p1'));
    async.flushMicrotasks();
    expect(w.now.incoming, isEmpty);
  });

  _inWorld('asking again after it was closed starts a new wait', (async, w) {
    w.ask('u2', 'p1', 300);
    async.flushMicrotasks();
    async.elapse(const Duration(seconds: 90));
    w.run(() => w.repo('u2').cancelRequest(w.code, 'p2_p1'));
    w.ask('u2', 'p1', 50);
    async.flushMicrotasks();
    final p = w.now.incoming.single;
    expect(p.request.amount, 50);
    final left = p.deadline.difference(w.clock());
    expect(left, lessThanOrEqualTo(const Duration(minutes: 2)));
    expect(left, greaterThan(const Duration(minutes: 1, seconds: 59)));
  });

  _inWorld('a request the room says is gone can be put away', (async, w) {
    w.ask('u2', 'p1', 300);
    async.flushMicrotasks();
    w.controller.dismiss('p2_p1');
    expect(w.now.incoming, isEmpty);
  });

  _inWorld('what was closed before the screen opened is not news', (async, w) {
    // (the room has no requests yet; closed ones are made below, then a new
    // controller is looked at)
    w.ask('owner', 'p2', 80);
    async.flushMicrotasks();
    w.run(() => w.repo('u2').cancelRequest(w.code, 'p1_p2'));
    async.flushMicrotasks();
    expect(w.now.notice?.text, 'คำขอถูกยกเลิก');
    final fresh = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuthService('owner')),
        roomRepositoryProvider.overrideWithValue(w.repo('owner')),
        roomClockProvider.overrideWithValue(w.clock),
      ],
    );
    fresh.listen(roomGameProvider(w.code), (_, _) {});
    fresh.listen(requestsControllerProvider(w.code), (_, _) {});
    async.flushMicrotasks();
    expect(fresh.read(requestsControllerProvider(w.code)).notice, isNull);
    fresh.dispose();
    async.flushMicrotasks();
  });

  _inWorld(
    'an open request that ran out long ago is not offered again on reopening',
    (async, w) {
      w.ask('u2', 'p1', 300);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 10));
      final fresh = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(FakeAuthService('owner')),
          roomRepositoryProvider.overrideWithValue(w.repo('owner')),
          roomClockProvider.overrideWithValue(w.clock),
        ],
      );
      fresh.listen(roomGameProvider(w.code), (_, _) {});
      fresh.listen(requestsControllerProvider(w.code), (_, _) {});
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      final state = fresh.read(requestsControllerProvider(w.code));
      expect(state.incoming, isEmpty);
      expect(state.notice, isNull);
      fresh.dispose();
      async.flushMicrotasks();
    },
  );

  _inWorld('a request that has no server time yet is not offered', (async, w) {
    w.ask('u2', 'p1', 300);
    async.flushMicrotasks();
    expect(w.now.incoming, isEmpty);
  }, noTime: true);
}
