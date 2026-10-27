import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/incoming_events.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/application/undo_offer.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

const _settings = RoomSettings(
  startingCash: 1500,
  goAmount: 200,
  maxPlayers: 4,
);

class _Game {
  _Game(this.store, this.code);

  final FakeRoomStore store;
  final String code;

  FakeRoomRepository repo(String uid) =>
      FakeRoomRepository(store, FakeAuthService(uid));

  ProviderContainer as_(String uid, {Duration? window}) {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuthService(uid)),
        roomRepositoryProvider.overrideWithValue(repo(uid)),
        if (window != null) undoOfferWindowProvider.overrideWithValue(window),
      ],
    );
    addTearDown(container.dispose);
    container.listen(roomGameProvider(code), (_, _) {});
    container.listen(undoOfferProvider(code), (_, _) {});
    container.listen(incomingEventsProvider(code), (_, _) {});
    return container;
  }
}

/// Shows every entry as if it were still on its way (no server time yet).
class _Pending extends FakeRoomRepository {
  _Pending(super.store, super.auth);

  @override
  Stream<List<RoomEntry>> watchEntries(String code) => super
      .watchEntries(code)
      .map(
        (all) => [
          for (final e in all)
            RoomEntry(
              seq: e.seq,
              kind: e.kind,
              seat: e.seat,
              by: e.by,
              cid: e.cid,
              from: e.from,
              to: e.to,
              amount: e.amount,
              reason: e.reason,
            ),
        ],
      );
}

/// Holds the news of the entries back until [release]: a slow connection.
class _Late extends FakeRoomRepository {
  _Late(super.store, super.auth);

  var _gate = Future<void>.value();
  Completer<void>? _held;

  void hold() {
    final held = Completer<void>();
    _held = held;
    _gate = held.future;
  }

  void release() {
    _held?.complete();
    _held = null;
  }

  @override
  Stream<List<RoomEntry>> watchEntries(String code) =>
      super.watchEntries(code).asyncMap((all) async {
        await _gate;
        return all;
      });
}

Future<_Game> _game() async {
  final store = FakeRoomStore();
  final owner = FakeRoomRepository(store, FakeAuthService('owner'));
  final meta = await owner.createRoom(
    settings: _settings,
    name: 'ต้น',
    color: 0xFF3D5AFE,
  );
  await FakeRoomRepository(
    store,
    FakeAuthService('u2'),
  ).joinAsPlayer(code: meta.code, name: 'แพร', color: 0xFFE11D48);
  await owner.startGame(meta.code);
  return _Game(store, meta.code);
}

Future<void> _settle(ProviderContainer c, String code) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(c.read(roomGameProvider(code)).hasValue, isTrue);
}

void main() {
  group('the offer to take back a press', () {
    test(
      'a press that was there when the screen opened is not offered',
      () async {
        final g = await _game();
        await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
        final c = g.as_('owner');
        await _settle(c, g.code);
        expect(c.read(undoOfferProvider(g.code)), isNull);
      },
    );

    test(
      'a press made while the screen is open is offered, with its entry',
      () async {
        final g = await _game();
        final c = g.as_('owner');
        await _settle(c, g.code);
        await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
        await _settle(c, g.code);
        final offer = c.read(undoOfferProvider(g.code));
        expect(offer?.seq, 0);
        expect(offer?.entry.amount, 200);
      },
    );

    test('a press that is still on its way is not offered yet', () async {
      final g = await _game();
      final c = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(FakeAuthService('owner')),
          roomRepositoryProvider.overrideWithValue(
            _Pending(g.store, FakeAuthService('owner')),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(roomGameProvider(g.code), (_, _) {});
      c.listen(undoOfferProvider(g.code), (_, _) {});
      await _settle(c, g.code);
      await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code)), isNull);
    });

    test('paying a request is not offered to be taken back', () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g.repo('u2').requestMoney(g.code, fromSeat: 'p1', amount: 300);
      await _settle(c, g.code);
      await g.repo('owner').payRequest(g.code, 'p2_p1', cid: 'cidcidcid1234');
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code)), isNull);
    });

    test('a bankruptcy is not offered to be taken back', () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g.repo('owner').submitEntry(g.code, EntryDraft.bankrupt(2000));
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code)), isNull);
    });

    test('a payment helped by a mortgage is offered like any other', () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g.repo('owner').submitEntry(g.code, EntryDraft.payBank(1400));
      await _settle(c, g.code);
      await g
          .repo('owner')
          .submitEntry(g.code, EntryDraft.payBank(700, mortgage: 600));
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code))?.entry.mortgage, 600);
    });

    test("somebody else's press is not offered to me", () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g.repo('u2').submitEntry(g.code, EntryDraft.passGo());
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code)), isNull);
    });

    test('the offer ends when its time is up', () async {
      final g = await _game();
      final c = g.as_('owner', window: const Duration(milliseconds: 60));
      await _settle(c, g.code);
      await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code)), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(c.read(undoOfferProvider(g.code)), isNull);
    });

    test('the offer ends when somebody presses after it', () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
      await _settle(c, g.code);
      await g.repo('u2').submitEntry(g.code, EntryDraft.passGo());
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code)), isNull);
    });

    test(
      'the offer ends when the press is taken back, and the next press is offered',
      () async {
        final g = await _game();
        final c = g.as_('owner');
        await _settle(c, g.code);
        await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
        await _settle(c, g.code);
        await g.repo('owner').undoEntry(g.code, 0);
        await _settle(c, g.code);
        expect(c.read(undoOfferProvider(g.code)), isNull);
        await g.repo('owner').submitEntry(g.code, EntryDraft.payBank(100));
        await _settle(c, g.code);
        expect(c.read(undoOfferProvider(g.code))?.seq, 1);
      },
    );

    test('a spectator is never offered anything', () async {
      final g = await _game();
      await g.repo('s1').joinAsSpectator(code: g.code, name: 'ดู', color: 3);
      final c = g.as_('s1');
      await _settle(c, g.code);
      await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
      await _settle(c, g.code);
      expect(c.read(undoOfferProvider(g.code)), isNull);
    });
  });

  group('what is announced to a person', () {
    test(
      'a transfer to me after opening is a batch; old ones are not',
      () async {
        final g = await _game();
        await g.repo('u2').submitEntry(g.code, EntryDraft.transfer('p1', 100));
        final c = g.as_('owner');
        await _settle(c, g.code);
        expect(c.read(incomingEventsProvider(g.code)), isNull);
        await g.repo('u2').submitEntry(g.code, EntryDraft.transfer('p1', 250));
        await _settle(c, g.code);
        final batch = c.read(incomingEventsProvider(g.code));
        expect(batch?.lines, ['แพร โอนให้คุณ +250']);
      },
    );

    test('taking the transfer back is announced after it', () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g.repo('u2').submitEntry(g.code, EntryDraft.transfer('p1', 250));
      await _settle(c, g.code);
      final first = c.read(incomingEventsProvider(g.code));
      await g.repo('u2').undoEntry(g.code, 0);
      await _settle(c, g.code);
      final second = c.read(incomingEventsProvider(g.code));
      expect(second?.lines, ['แพร ยกเลิกการโอน 250']);
      expect(second?.id, isNot(first?.id));
    });

    test('a spectator hears nothing', () async {
      final g = await _game();
      await g.repo('s1').joinAsSpectator(code: g.code, name: 'ดู', color: 3);
      final c = g.as_('s1');
      await _settle(c, g.code);
      await g.repo('u2').submitEntry(g.code, EntryDraft.transfer('p1', 250));
      await _settle(c, g.code);
      expect(c.read(incomingEventsProvider(g.code)), isNull);
    });
  });

  group('how long the offer lasts when the news comes late', () {
    // The room takes a press back until 6.5 seconds after its time (the room's
    // clock); the offer is 4 seconds from when the news arrives, less when it
    // arrives late, and not at all when too little is left to be of use.
    late DateTime clock;
    late FakeRoomStore store;
    late String code;
    late _Late repo;
    late ProviderContainer c;

    setUp(() async {
      clock = DateTime.utc(2026, 10, 27, 12);
      store = FakeRoomStore(now: () => clock);
      final owner = FakeRoomRepository(store, FakeAuthService('owner'));
      final meta = await owner.createRoom(
        settings: _settings,
        name: 'ต้น',
        color: 0xFF3D5AFE,
      );
      await FakeRoomRepository(
        store,
        FakeAuthService('u2'),
      ).joinAsPlayer(code: meta.code, name: 'แพร', color: 0xFFE11D48);
      await owner.startGame(meta.code);
      code = meta.code;
      repo = _Late(store, FakeAuthService('owner'));
      c = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(FakeAuthService('owner')),
          roomRepositoryProvider.overrideWithValue(repo),
          roomClockProvider.overrideWithValue(() => clock),
        ],
      );
      addTearDown(c.dispose);
      c.listen(roomGameProvider(code), (_, _) {});
      c.listen(undoOfferProvider(code), (_, _) {});
      await _settle(c, code);
    });

    /// Presses GO now, and lets the news arrive [late] afterwards.
    Future<UndoOffer?> pressAndHear(Duration late) async {
      repo.hold();
      await FakeRoomRepository(
        store,
        FakeAuthService('owner'),
      ).submitEntry(code, EntryDraft.passGo());
      clock = clock.add(late);
      repo.release();
      await _settle(c, code);
      return c.read(undoOfferProvider(code));
    }

    test('news at once: the full 4 seconds', () async {
      final offer = await pressAndHear(Duration.zero);
      expect(offer?.window, const Duration(seconds: 4));
    });

    test(
      'news 1 second late: still the 4 seconds (4.5 are left of the 6.5)',
      () async {
        final offer = await pressAndHear(const Duration(seconds: 1));
        expect(offer?.window, const Duration(seconds: 4));
      },
    );

    test('news 3 seconds late: only what is left of the room time', () async {
      final offer = await pressAndHear(const Duration(seconds: 3));
      expect(offer?.window, const Duration(milliseconds: 2500));
    });

    test(
      'news 4.5 seconds late: one second is the least that is offered',
      () async {
        final offer = await pressAndHear(const Duration(milliseconds: 4500));
        expect(offer?.window, const Duration(seconds: 1));
      },
    );

    test(
      'news 4.6 seconds late: too little is left, nothing is offered',
      () async {
        final offer = await pressAndHear(const Duration(milliseconds: 4600));
        expect(offer, isNull);
      },
    );

    test('news after the room time has gone: nothing is offered', () async {
      final offer = await pressAndHear(const Duration(seconds: 10));
      expect(offer, isNull);
    });

    test(
      'a clock far from the room\'s is not believed: the 4 seconds',
      () async {
        final offer = await pressAndHear(const Duration(minutes: 5));
        expect(offer?.window, const Duration(seconds: 4));
      },
    );
  });
}
