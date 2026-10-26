import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

const _settings = RoomSettings(
  startingCash: 1500,
  goAmount: 200,
  maxPlayers: 4,
);

/// The people of a started room of two, the first of them being 'owner'.
class _Game {
  _Game(this.store, this.code);

  final FakeRoomStore store;
  final String code;

  FakeRoomRepository repo(String uid) =>
      FakeRoomRepository(store, FakeAuthService(uid));

  ProviderContainer as_(String uid, {FakeRoomRepository? using}) {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuthService(uid)),
        roomRepositoryProvider.overrideWithValue(using ?? repo(uid)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(roomGameProvider(code), (_, _) {});
    return container;
  }
}

Future<_Game> _game({RoomSettings settings = _settings}) async {
  final store = FakeRoomStore();
  final owner = FakeRoomRepository(store, FakeAuthService('owner'));
  final meta = await owner.createRoom(
    settings: settings,
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

/// Lets the streams deliver until the view has data.
Future<RoomGameView> _view(ProviderContainer c, String code) async {
  for (var i = 0; i < 50; i++) {
    final v = c.read(roomGameProvider(code));
    if (v.hasValue) return v.requireValue;
    await Future<void>.delayed(Duration.zero);
  }
  fail('the view never had data: ${c.read(roomGameProvider(code))}');
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

/// A repository showing a tampered picture of the state or the history.
class _Seen extends FakeRoomRepository {
  _Seen(super.store, super.auth, {this.state, this.entries});

  final RoomState Function(RoomState)? state;
  final List<RoomEntry> Function(List<RoomEntry>)? entries;

  @override
  Stream<RoomState?> watchState(String code) => super
      .watchState(code)
      .map((s) => s == null || state == null ? s : state!(s));

  @override
  Stream<List<RoomEntry>> watchEntries(String code) =>
      super.watchEntries(code).map((e) => entries == null ? e : entries!(e));
}

/// A repository that answers "who am I" only when told to.
class _SlowMe extends FakeRoomRepository {
  _SlowMe(super.store, super.auth);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<Member?> readMyMember(String code) async {
    await _gate.future;
    return super.readMyMember(code);
  }
}

void main() {
  test('my balance is the one of my seat and follows the game live', () async {
    final g = await _game();
    final c = g.as_('owner');
    var view = await _view(c, g.code);
    expect(view.mySeat, 'p1');
    expect(view.isSpectator, isFalse);
    expect(view.myBalance, 1500);
    await g
        .repo('owner')
        .submitEntry(g.code, EntryDraft.receive(300, 'ค่าเช่า'));
    await _tick();
    await _tick();
    view = await _view(c, g.code);
    expect(view.myBalance, 1800);
    expect(view.balances['p2'], 1500);
  });

  test('another player has their own seat and balance', () async {
    final g = await _game();
    final view = await _view(g.as_('u2'), g.code);
    expect(view.mySeat, 'p2');
    expect(view.myBalance, 1500);
  });

  test('names and colours come from the people at the seats', () async {
    final g = await _game();
    final view = await _view(g.as_('owner'), g.code);
    expect(view.nameOf('p1'), 'ต้น');
    expect(view.nameOf('p2'), 'แพร');
    expect(view.colorOf('p1'), 0xFF3D5AFE);
    expect(view.colorOf('p2'), 0xFFE11D48);
    expect(view.nameOf('p9'), 'p9');
    expect(view.colorOf('p9'), isNull);
  });

  test('only the people at the seats have names, spectators do not', () async {
    final g = await _game();
    await g.repo('s1').joinAsSpectator(code: g.code, name: 'ดู', color: 3);
    final view = await _view(g.as_('owner'), g.code);
    expect(view.names, {'p1': 'ต้น', 'p2': 'แพร'});
    expect(view.colors, {'p1': 0xFF3D5AFE, 'p2': 0xFFE11D48});
  });

  test('the view waits until it is known which seat is mine', () async {
    final g = await _game();
    final slow = _SlowMe(g.store, FakeAuthService('owner'));
    final c = g.as_('owner', using: slow);
    for (var i = 0; i < 10; i++) {
      await _tick();
    }
    expect(c.read(roomGameProvider(g.code)).isLoading, isTrue);
    slow.release();
    final view = await _view(c, g.code);
    expect(view.mySeat, 'p1');
  });

  test('the balances are listed in the order of the seats', () async {
    final g = await _game();
    final view = await _view(g.as_('owner'), g.code);
    expect(view.seats, ['p1', 'p2']);
  });

  test('a spectator sees everything and has no seat to press for', () async {
    final g = await _game();
    await g.repo('s1').joinAsSpectator(code: g.code, name: 'ดู', color: 3);
    final c = g.as_('s1');
    final view = await _view(c, g.code);
    expect(view.isSpectator, isTrue);
    expect(view.mySeat, isNull);
    expect(view.myBalance, isNull);
    expect(view.balances, {'p1': 1500, 'p2': 1500});
    expect(view.block, PressBlock.spectator);
  });

  group('the check of the balances', () {
    test('is ok while the history adds up', () async {
      final g = await _game();
      await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
      final view = await _view(g.as_('u2'), g.code);
      expect(view.check, BalanceCheck.ok);
    });

    test(
      'says mismatch when the balances are not what the history makes',
      () async {
        final g = await _game();
        await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
        final tampered = _Seen(
          g.store,
          FakeAuthService('u2'),
          state: (s) => RoomState(
            seq: s.seq,
            seats: s.seats,
            balances: {...s.balances, 'p2': s.balances['p2']! + 1},
            bankrupt: s.bankrupt,
            bankerSeat: s.bankerSeat,
            status: s.status,
          ),
        );
        final view = await _view(g.as_('u2', using: tampered), g.code);
        expect(view.check, BalanceCheck.mismatch);
        expect(view.block, PressBlock.mismatch);
      },
    );

    test('says syncing, not mismatch, while the history is behind', () async {
      final g = await _game();
      await g.repo('owner').submitEntry(g.code, EntryDraft.passGo());
      final behind = _Seen(
        g.store,
        FakeAuthService('u2'),
        entries: (_) => const [],
      );
      final view = await _view(g.as_('u2', using: behind), g.code);
      expect(view.check, BalanceCheck.syncing);
      expect(view.block, PressBlock.none);
    });
  });

  group('the connection', () {
    test('is online at first and offline when it is cut', () async {
      final g = await _game();
      final c = g.as_('owner');
      var view = await _view(c, g.code);
      expect(view.online, isTrue);
      expect(view.block, PressBlock.none);
      g.store.setOnline(false);
      await _tick();
      await _tick();
      view = await _view(c, g.code);
      expect(view.online, isFalse);
      expect(view.block, PressBlock.offline);
      g.store.setOnline(true);
      await _tick();
      await _tick();
      view = await _view(c, g.code);
      expect(view.online, isTrue);
      expect(view.block, PressBlock.none);
    });
  });

  group('why the buttons are off', () {
    test(
      'a press that just went in makes them rest, then they are free',
      () async {
        final g = await _game();
        final c = g.as_('owner');
        await _view(c, g.code);
        await c
            .read(pressControllerProvider(g.code).notifier)
            .press(EntryDraft.passGo());
        final view = await _view(c, g.code);
        expect(view.block, PressBlock.cooling);
      },
    );

    test('for a seat that went bankrupt it says so', () async {
      final g = await _game();
      final out = _Seen(
        g.store,
        FakeAuthService('owner'),
        state: (s) => RoomState(
          seq: s.seq,
          seats: s.seats,
          balances: s.balances,
          bankrupt: const ['p1'],
          bankerSeat: null,
          status: s.status,
        ),
      );
      final view = await _view(g.as_('owner', using: out), g.code);
      expect(view.seatActive, isFalse);
      expect(view.block, PressBlock.out);
    });
  });

  group('while it is not all there', () {
    test('the view is loading until the game has started', () async {
      final store = FakeRoomStore();
      final owner = FakeRoomRepository(store, FakeAuthService('owner'));
      final meta = await owner.createRoom(
        settings: _settings,
        name: 'ต้น',
        color: 1,
      );
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(FakeAuthService('owner')),
          roomRepositoryProvider.overrideWithValue(owner),
        ],
      );
      addTearDown(container.dispose);
      container.listen(roomGameProvider(meta.code), (_, _) {});
      for (var i = 0; i < 10; i++) {
        await _tick();
      }
      expect(container.read(roomGameProvider(meta.code)).isLoading, isTrue);
    });

    test('a room that does not exist is an error, not a spinner', () async {
      final store = FakeRoomStore();
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(FakeAuthService('owner')),
          roomRepositoryProvider.overrideWithValue(
            FakeRoomRepository(store, FakeAuthService('owner')),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(roomGameProvider('ZZZZZZ'), (_, _) {});
      for (var i = 0; i < 10; i++) {
        await _tick();
      }
      expect(container.read(roomGameProvider('ZZZZZZ')).hasError, isTrue);
    });
  });
}
