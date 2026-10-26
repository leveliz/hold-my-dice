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
import 'package:hold_my_dice/features/room/domain/room_request.dart';

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

  /// When set, a press is answered "not sure" and the attempt is said to be
  /// still running until this completes.
  Completer<void>? stillRunning;

  /// The same for taking a press back.
  Completer<void>? undoStillRunning;
  bool undoThenLose = false;
  Completer<void>? undoHold;

  @override
  Future<void> undoEntry(String code, int seq) async {
    calls++;
    await undoHold?.future;
    if (undoStillRunning case final running?) {
      throw UnsureException(running.future);
    }
    await super.undoEntry(code, seq);
    if (undoThenLose) {
      for (var i = 0; i < 10; i++) {
        await Future<void>.value();
      }
      throw const RoomException(RoomError.unsure);
    }
  }

  @override
  Future<void> submitEntry(String code, EntryDraft draft) async {
    calls++;
    await hold?.future;
    if (failWithSomethingElse) throw StateError('not a room error');
    if (failWith case final e?) throw RoomException(e);
    if (loseWithoutWriting) throw const RoomException(RoomError.unsure);
    if (stillRunning case final running?) {
      throw UnsureException(running.future);
    }
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

  /// Taking a press back, to its end.
  RoomError? undoNow(int seq) => finish(controller.undo(seq));
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

      _inWorld('a press whose attempt is still running stays unsure past the '
          'usual wait, and is settled when the attempt ends', (async, w) {
        final running = Completer<void>();
        w.repo.stillRunning = running;
        final draft = EntryDraft.passGo();
        expect(w.pressNow(draft), RoomError.unsure);
        expect(w.press.unsureCid, draft.cid);
        async.elapse(const Duration(minutes: 5));
        expect(
          w.press.unsureCid,
          draft.cid,
          reason: 'the clock alone does not end it',
        );
        running.complete();
        async.flushMicrotasks();
        expect(w.press.unsureCid, isNull);
      });

      _inWorld('a press can be taken back, and the buttons rest after it', (
        async,
        w,
      ) {
        expect(w.pressNow(EntryDraft.passGo()), isNull);
        async.elapse(const Duration(seconds: 2));
        expect(w.undoNow(0), isNull);
        expect(w.press.cooling, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(w.press.cooling, isFalse);
      });

      _inWorld('taking back works during the rest that follows a press', (
        async,
        w,
      ) {
        expect(w.pressNow(EntryDraft.passGo()), isNull);
        expect(w.press.cooling, isTrue);
        expect(w.undoNow(0), isNull, reason: 'not ignored');
        expect(w.repo.calls, 2);
      });

      _inWorld('taking back what cannot be taken back says why', (async, w) {
        expect(w.undoNow(7), RoomError.tooLate);
        expect(w.press.sending, isFalse);
        expect(w.press.unsureCid, isNull);
      });

      _inWorld('a second action while one is on its way is left alone', (
        async,
        w,
      ) {
        w.repo.undoHold = Completer<void>();
        unawaited(w.controller.undo(0));
        async.flushMicrotasks();
        expect(w.press.sending, isTrue);
        expect(w.undoNow(0), isNull);
        expect(w.repo.calls, 1);
        w.repo.undoHold!.complete();
        async.flushMicrotasks();
      });

      _inWorld(
        'a take-back that is still running holds the buttons until it ends',
        (async, w) {
          expect(w.pressNow(EntryDraft.passGo()), isNull);
          async.elapse(const Duration(seconds: 2));
          final running = Completer<void>();
          w.repo.undoStillRunning = running;
          expect(w.undoNow(0), RoomError.unsure);
          expect(w.press.unsureCid, 'undo-0');
          async.elapse(const Duration(minutes: 5));
          expect(w.press.unsureCid, 'undo-0');
          running.complete();
          async.flushMicrotasks();
          expect(w.press.unsureCid, isNull);
        },
      );

      _inWorld('a take-back whose answer was lost is settled by the history', (
        async,
        w,
      ) {
        expect(w.pressNow(EntryDraft.passGo()), isNull);
        async.elapse(const Duration(seconds: 2));
        w.repo.undoThenLose = true;
        expect(w.undoNow(0), RoomError.unsure);
        async.flushMicrotasks();
        expect(w.press.unsureCid, isNull, reason: 'the entry shows as undone');
      });

      _inWorld('a request can be paid with a mortgage', (async, w) {
        expect(w.pressNow(EntryDraft.payBank(1400)), isNull);
        async.elapse(const Duration(seconds: 2));
        w.finish(
          FakeRoomRepository(
            w.store,
            FakeAuthService('u2'),
          ).requestMoney(w.code, fromSeat: 'p1', amount: 700),
        );
        expect(
          w.finish(w.controller.payRequest('p2_p1', mortgage: 650)),
          isNull,
        );
        final entries = w.container.read(roomEntriesProvider(w.code)).value!;
        expect(entries.last.amount, 700);
        expect(entries.last.mortgage, 650);
      });

      _inWorld('a request can be paid, and the buttons rest after it', (
        async,
        w,
      ) {
        w.finish(
          FakeRoomRepository(
            w.store,
            FakeAuthService('u2'),
          ).requestMoney(w.code, fromSeat: 'p1', amount: 300),
        );
        expect(w.finish(w.controller.payRequest('p2_p1')), isNull);
        expect(w.press.cooling, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(w.press.cooling, isFalse);
        final entries = w.container.read(roomEntriesProvider(w.code)).value!;
        expect(entries.single.amount, 300);
        expect(entries.single.reason, requestReason);
      });

      _inWorld('a request that is not there says so', (async, w) {
        expect(
          w.finish(w.controller.payRequest('p2_p1')),
          RoomError.requestGone,
        );
        expect(w.press.sending, isFalse);
      });

      _inWorld('a request that costs more than I have is refused in words', (
        async,
        w,
      ) {
        w.finish(
          FakeRoomRepository(
            w.store,
            FakeAuthService('u2'),
          ).requestMoney(w.code, fromSeat: 'p1', amount: 2000),
        );
        expect(
          w.finish(w.controller.payRequest('p2_p1')),
          RoomError.insufficientFunds,
        );
        expect(w.press.unsureCid, isNull);
      });

      _inWorld('a payment whose answer was lost is settled by the history', (
        async,
        w,
      ) {
        w.finish(
          FakeRoomRepository(
            w.store,
            FakeAuthService('u2'),
          ).requestMoney(w.code, fromSeat: 'p1', amount: 300),
        );
        w.repo.writeThenLose = true;
        expect(w.finish(w.controller.payRequest('p2_p1')), RoomError.unsure);
        async.flushMicrotasks();
        expect(
          w.press.unsureCid,
          isNull,
          reason: 'its entry is in the history',
        );
      });

      _inWorld('a payment is left alone while another action is on its way', (
        async,
        w,
      ) {
        w.finish(
          FakeRoomRepository(
            w.store,
            FakeAuthService('u2'),
          ).requestMoney(w.code, fromSeat: 'p1', amount: 300),
        );
        w.repo.hold = Completer<void>();
        unawaited(w.controller.press(EntryDraft.passGo()));
        async.flushMicrotasks();
        expect(w.finish(w.controller.payRequest('p2_p1')), isNull);
        w.repo.hold!.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
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
