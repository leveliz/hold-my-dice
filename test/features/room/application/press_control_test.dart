import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

/// A repository whose presses can be held back, made to fail, or made to
/// look lost (written but answered with "not sure", or not written at all).
class _Scripted extends FakeRoomRepository {
  _Scripted(FakeRoomStore store) : super(store, FakeAuthService('owner'));

  var calls = 0;
  Completer<void>? hold;
  RoomError? failWith;
  bool failWithSomethingElse = false;
  bool writeThenLose = false;
  bool loseWithoutWriting = false;

  @override
  Future<void> submitEntry(String code, EntryDraft draft) async {
    calls++;
    await hold?.future;
    if (failWithSomethingElse) throw StateError('not a room error');
    if (failWith case final e?) throw RoomException(e);
    if (loseWithoutWriting) throw const RoomException(RoomError.unsure);
    await super.submitEntry(code, draft);
    if (writeThenLose) {
      // The entry reaches the history before the answer is given up on.
      for (var i = 0; i < 10; i++) {
        await Future<void>.value();
      }
      throw const RoomException(RoomError.unsure);
    }
  }
}

class _World {
  _World(this.async, this.store, this.code, this.repo, this.container);

  final FakeAsync async;
  final FakeRoomStore store;
  final String code;
  final _Scripted repo;
  final ProviderContainer container;

  PressState get press => container.read(pressControllerProvider(code));
  PressController get controller =>
      container.read(pressControllerProvider(code).notifier);

  /// Runs [f] to its end, with the microtasks that takes, and gives its result.
  T finish<T>(Future<T> f) {
    T? out;
    var done = false;
    unawaited(
      f.then((v) {
        out = v;
        done = true;
      }),
    );
    async.flushMicrotasks();
    expect(done, isTrue, reason: 'the future did not finish');
    return out as T;
  }

  /// A press, to its end.
  RoomError? pressNow(EntryDraft draft) => finish(controller.press(draft));
}

/// A started room of two and a container acting as 'owner' (p1).
_World _world(FakeAsync async) {
  final store = FakeRoomStore();
  const settings = RoomSettings(startingCash: 1500, goAmount: 200);
  final owner = FakeRoomRepository(store, FakeAuthService('owner'));
  late RoomMeta meta;
  void run(Future<void> Function() step) {
    var done = false;
    unawaited(step().then((_) => done = true));
    async.flushMicrotasks();
    expect(done, isTrue);
  }

  run(() async {
    meta = await owner.createRoom(settings: settings, name: 'ต้น', color: 1);
    await FakeRoomRepository(
      store,
      FakeAuthService('u2'),
    ).joinAsPlayer(code: meta.code, name: 'แพร', color: 2);
    await owner.startGame(meta.code);
  });
  final repo = _Scripted(store);
  final container = ProviderContainer(
    overrides: [roomRepositoryProvider.overrideWithValue(repo)],
  );
  container.listen(pressControllerProvider(meta.code), (_, _) {});
  async.flushMicrotasks();
  return _World(async, store, meta.code, repo, container);
}

void _inWorld(String name, void Function(FakeAsync async, _World w) body) {
  test(name, () {
    FakeAsync().run((async) {
      final w = _world(async);
      body(async, w);
      // Closing the screen must leave no timer behind, whatever happened.
      w.container.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });
}

void main() {
  group('pressBlock', () {
    PressBlock block({
      String? seat = 'p1',
      bool active = true,
      bool online = true,
      BalanceCheck check = BalanceCheck.ok,
      PressState press = const PressState(),
    }) => pressBlock(
      mySeat: seat,
      seatActive: active,
      online: online,
      check: check,
      press: press,
    );

    test('nothing in the way', () {
      expect(block(), PressBlock.none);
    });

    test(
      'while the balances are still being added up, pressing is allowed',
      () {
        expect(block(check: BalanceCheck.syncing), PressBlock.none);
      },
    );

    test('each reason on its own', () {
      expect(block(seat: null), PressBlock.spectator);
      expect(block(active: false), PressBlock.out);
      expect(block(online: false), PressBlock.offline);
      expect(block(check: BalanceCheck.mismatch), PressBlock.mismatch);
      expect(block(press: const PressState(sending: true)), PressBlock.sending);
      expect(block(press: const PressState(cooling: true)), PressBlock.cooling);
      expect(block(press: const PressState(unsureCid: 'x')), PressBlock.unsure);
    });

    test('when several apply, the most basic one is told', () {
      const everything = PressState(
        sending: true,
        cooling: true,
        unsureCid: 'x',
      );
      expect(
        block(seat: null, active: false, online: false, press: everything),
        PressBlock.spectator,
      );
      expect(
        block(active: false, online: false, press: everything),
        PressBlock.out,
      );
      expect(
        block(online: false, check: BalanceCheck.mismatch, press: everything),
        PressBlock.unsure,
      );
      expect(
        block(
          online: false,
          check: BalanceCheck.mismatch,
          press: const PressState(sending: true),
        ),
        PressBlock.offline,
      );
      expect(
        block(
          check: BalanceCheck.mismatch,
          press: const PressState(sending: true),
        ),
        PressBlock.mismatch,
      );
      expect(
        block(press: const PressState(sending: true, cooling: true)),
        PressBlock.sending,
      );
    });
  });

  group('PressController', () {
    _inWorld('a press goes in, then the buttons rest for 1.5 seconds', (
      async,
      w,
    ) {
      expect(w.press.sending, isFalse);
      expect(w.pressNow(EntryDraft.passGo()), isNull);
      expect(w.press.cooling, isTrue);
      expect(w.press.sending, isFalse);
      async.elapse(const Duration(milliseconds: 1499));
      expect(w.press.cooling, isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(w.press.cooling, isFalse);
      expect(w.repo.calls, 1);
    });

    _inWorld('while a press is on its way another is ignored', (async, w) {
      w.repo.hold = Completer<void>();
      final first = w.controller.press(EntryDraft.passGo());
      async.flushMicrotasks();
      expect(w.press.sending, isTrue);
      expect(w.pressNow(EntryDraft.passGo()), isNull);
      expect(w.repo.calls, 1);
      w.repo.hold!.complete();
      expect(w.finish(first), isNull);
      expect(w.repo.calls, 1);
    });

    _inWorld('during the rest a press is ignored, afterwards it works', (
      async,
      w,
    ) {
      w.pressNow(EntryDraft.passGo());
      expect(w.press.cooling, isTrue);
      expect(w.pressNow(EntryDraft.passGo()), isNull);
      expect(w.repo.calls, 1);
      async.elapse(const Duration(seconds: 2));
      expect(w.pressNow(EntryDraft.passGo()), isNull);
      expect(w.repo.calls, 2);
    });

    _inWorld('a refused press gives the reason and the buttons do not rest', (
      async,
      w,
    ) {
      w.repo.failWith = RoomError.insufficientFunds;
      expect(w.pressNow(EntryDraft.payBank(5)), RoomError.insufficientFunds);
      expect(w.press.sending, isFalse);
      expect(w.press.cooling, isFalse);
      expect(w.press.unsureCid, isNull);
      w.repo.failWith = null;
      expect(w.pressNow(EntryDraft.passGo()), isNull);
      expect(w.repo.calls, 2, reason: 'pressing again is possible at once');
    });

    _inWorld('the room refusing a real press is reported the same way', (
      async,
      w,
    ) {
      expect(w.pressNow(EntryDraft.payBank(5000)), RoomError.insufficientFunds);
      expect(w.press.sending, isFalse);
    });

    _inWorld('an error that is not the repository\'s own is an unknown one', (
      async,
      w,
    ) {
      w.repo.failWithSomethingElse = true;
      expect(w.pressNow(EntryDraft.passGo()), RoomError.unknown);
      expect(w.press.sending, isFalse);
      expect(w.press.cooling, isFalse);
    });

    group('when it is not known whether the press was written', () {
      _inWorld('the buttons stay off and the press code is remembered', (
        async,
        w,
      ) {
        w.repo.loseWithoutWriting = true;
        final draft = EntryDraft.passGo();
        expect(w.pressNow(draft), RoomError.unsure);
        expect(w.press.unsureCid, draft.cid);
        expect(w.press.sending, isFalse);
        expect(w.pressNow(EntryDraft.passGo()), isNull);
        expect(w.repo.calls, 1, reason: 'no new press while unsure');
      });

      _inWorld('it is settled when the history shows the press', (async, w) {
        w.repo.writeThenLose = true;
        expect(w.pressNow(EntryDraft.passGo()), RoomError.unsure);
        async.flushMicrotasks();
        expect(
          w.press.unsureCid,
          isNull,
          reason: 'its entry is in the history',
        );
        expect(w.press.cooling, isFalse);
      });

      _inWorld(
        'it is settled after 20 seconds online without the press showing',
        (async, w) {
          w.repo.loseWithoutWriting = true;
          w.pressNow(EntryDraft.passGo());
          async.elapse(const Duration(seconds: 19));
          expect(w.press.unsureCid, isNotNull);
          async.elapse(const Duration(seconds: 1));
          expect(w.press.unsureCid, isNull);
        },
      );

      _inWorld('the 20 seconds only count while online', (async, w) {
        w.store.setOnline(false);
        async.flushMicrotasks();
        w.repo.loseWithoutWriting = true;
        w.pressNow(EntryDraft.passGo());
        async.elapse(const Duration(minutes: 5));
        expect(w.press.isUnsure, isTrue, reason: 'offline: still not sure');
        w.store.setOnline(true);
        async.elapse(const Duration(seconds: 19));
        expect(w.press.isUnsure, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(w.press.isUnsure, isFalse);
      });

      _inWorld(
        'going offline in the middle stops the count, online starts it over',
        (async, w) {
          w.repo.loseWithoutWriting = true;
          w.pressNow(EntryDraft.passGo());
          async.elapse(const Duration(seconds: 10));
          w.store.setOnline(false);
          async.elapse(const Duration(minutes: 1));
          expect(w.press.isUnsure, isTrue);
          w.store.setOnline(true);
          async.elapse(const Duration(seconds: 19));
          expect(w.press.isUnsure, isTrue, reason: 'the count started over');
          async.elapse(const Duration(seconds: 1));
          expect(w.press.isUnsure, isFalse);
        },
      );

      _inWorld('a press that shows up in the history late stops the waiting', (
        async,
        w,
      ) {
        w.repo.loseWithoutWriting = true;
        final draft = EntryDraft.passGo();
        w.pressNow(draft);
        expect(w.press.unsureCid, draft.cid);
        // The press, written after all, reaches the history.
        w.finish(
          FakeRoomRepository(
            w.store,
            FakeAuthService('owner'),
          ).submitEntry(w.code, draft),
        );
        expect(w.press.unsureCid, isNull);
        expect(
          async.pendingTimers,
          isEmpty,
          reason: 'nothing left to wait for',
        );
      });

      _inWorld('after it is settled, pressing works again', (async, w) {
        w.repo.loseWithoutWriting = true;
        w.pressNow(EntryDraft.passGo());
        async.elapse(const Duration(seconds: 21));
        w.repo.loseWithoutWriting = false;
        expect(w.pressNow(EntryDraft.passGo()), isNull);
        expect(w.repo.calls, 2);
      });
    });

    _inWorld('closing the screen while unsure leaves no timer behind', (
      async,
      w,
    ) {
      w.repo.loseWithoutWriting = true;
      w.pressNow(EntryDraft.passGo());
      expect(w.press.isUnsure, isTrue);
    });

    _inWorld('closing the screen during the rest leaves no timer behind', (
      async,
      w,
    ) {
      w.pressNow(EntryDraft.passGo());
      expect(w.press.cooling, isTrue);
    });
  });
}

extension on PressState {
  bool get isUnsure => unsureCid != null;
}
