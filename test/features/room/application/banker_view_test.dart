import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/entry_text.dart';
import 'package:hold_my_dice/features/room/application/incoming_events.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
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

  ProviderContainer as_(String uid) {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(FakeAuthService(uid)),
        roomRepositoryProvider.overrideWithValue(repo(uid)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(roomGameProvider(code), (_, _) {});
    container.listen(undoOfferProvider(code), (_, _) {});
    container.listen(incomingEventsProvider(code), (_, _) {});
    return container;
  }
}

/// Three players (owner p1 'ต้น', u2 p2 'แพร', u3 p3 'มด'); p3 went out first
/// and is the banker.
Future<_Game> _game() async {
  final store = FakeRoomStore();
  final owner = FakeRoomRepository(store, FakeAuthService('owner'));
  final meta = await owner.createRoom(
    settings: _settings,
    name: 'ต้น',
    color: 0xFF3D5AFE,
  );
  for (final (uid, name) in [('u2', 'แพร'), ('u3', 'มด')]) {
    await FakeRoomRepository(
      store,
      FakeAuthService(uid),
    ).joinAsPlayer(code: meta.code, name: name, color: 0xFFE11D48);
  }
  await owner.startGame(meta.code);
  final g = _Game(store, meta.code);
  await g.repo('u3').submitEntry(g.code, EntryDraft.payBank(1400));
  await g.repo('u3').submitEntry(g.code, EntryDraft.bankrupt(500));
  return g;
}

Future<void> _settle(ProviderContainer c, String code) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(c.read(roomGameProvider(code)).hasValue, isTrue);
}

RoomGameView _view(ProviderContainer c, String code) =>
    c.read(roomGameProvider(code)).value!;

void main() {
  group('the view of a game with a banker', () {
    test('says who the banker is, and who I am', () async {
      final g = await _game();
      final banker = g.as_('u3');
      final player = g.as_('u2');
      await _settle(banker, g.code);
      await _settle(player, g.code);
      expect(_view(banker, g.code).bankerSeat, 'p3');
      expect(_view(banker, g.code).iAmBanker, isTrue);
      expect(_view(banker, g.code).myUid, 'u3');
      expect(_view(player, g.code).iAmBanker, isFalse);
      expect(_view(player, g.code).myUid, 'u2');
      expect(_view(player, g.code).bankerSeat, 'p3');
    });

    test(
      'lets the banker press although they are out, and nobody else who is out',
      () async {
        final g = await _game();
        await g.repo('u2').submitEntry(g.code, EntryDraft.bankrupt(2000));
        final banker = g.as_('u3');
        final out = g.as_('u2');
        await _settle(banker, g.code);
        await _settle(out, g.code);
        expect(_view(banker, g.code).block, PressBlock.none);
        expect(_view(out, g.code).block, PressBlock.out);
      },
    );

    test(
      'names who pressed an entry for somebody else, and nobody for an own press',
      () async {
        final g = await _game();
        await g
            .repo('u3')
            .submitEntry(
              g.code,
              EntryDraft.receive(300, null).onBehalfOf('p1'),
            );
        await g.repo('u2').submitEntry(g.code, EntryDraft.transfer('p1', 10));
        final c = g.as_('owner');
        await _settle(c, g.code);
        final v = _view(c, g.code);
        final byBanker = v.entries.firstWhere(
          (e) => e.kind == EntryKind.receive,
        );
        final own = v.entries.firstWhere((e) => e.kind == EntryKind.transfer);
        expect(v.pressedByOther(byBanker), 'มด');
        expect(v.pressedByOther(own), isNull);
        final earlier = v.entries.firstWhere(
          (e) => e.kind == EntryKind.payBank,
        );
        expect(v.pressedByOther(earlier), isNull);
      },
    );
  });

  group('taking back a press of the banker', () {
    test(
      'is offered to the banker, not to the one it was pressed for',
      () async {
        final g = await _game();
        final banker = g.as_('u3');
        final target = g.as_('owner');
        await _settle(banker, g.code);
        await _settle(target, g.code);
        await g
            .repo('u3')
            .submitEntry(g.code, EntryDraft.passGo().onBehalfOf('p1'));
        await _settle(banker, g.code);
        await _settle(target, g.code);
        expect(banker.read(undoOfferProvider(g.code))?.entry.seat, 'p1');
        expect(target.read(undoOfferProvider(g.code)), isNull);
      },
    );
  });

  group('telling the one the banker pressed for', () {
    test(
      'a receive, a GO and a payment each have words, naming the banker',
      () async {
        final g = await _game();
        final c = g.as_('owner');
        await _settle(c, g.code);
        final banker = g.repo('u3');
        await banker.submitEntry(
          g.code,
          EntryDraft.receive(300, null).onBehalfOf('p1'),
        );
        await _settle(c, g.code);
        expect(c.read(incomingEventsProvider(g.code))?.lines, [
          'นายธนาคาร มด ให้คุณ +300',
        ]);
        await banker.submitEntry(g.code, EntryDraft.passGo().onBehalfOf('p1'));
        await _settle(c, g.code);
        expect(c.read(incomingEventsProvider(g.code))?.lines, [
          'นายธนาคาร มด กด GO ให้คุณ +200',
        ]);
        await banker.submitEntry(
          g.code,
          EntryDraft.payBank(100).onBehalfOf('p1'),
        );
        await _settle(c, g.code);
        expect(c.read(incomingEventsProvider(g.code))?.lines, [
          'นายธนาคาร มด หักจากคุณ -100',
        ]);
      },
    );

    test(
      'a payment helped by a mortgage says how much was mortgaged',
      () async {
        final g = await _game();
        final c = g.as_('owner');
        await _settle(c, g.code);
        final banker = g.repo('u3');
        await banker.submitEntry(
          g.code,
          EntryDraft.payBank(1400).onBehalfOf('p1'),
        );
        await _settle(c, g.code);
        await banker.submitEntry(
          g.code,
          EntryDraft.payBank(700, mortgage: 600).onBehalfOf('p1'),
        );
        await _settle(c, g.code);
        expect(c.read(incomingEventsProvider(g.code))?.lines, [
          'นายธนาคาร มด หักจากคุณ -700 (จำนอง 600)',
        ]);
      },
    );

    test(
      'being declared bankrupt by the banker is told to the one it happens to',
      () async {
        final g = await _game();
        final c = g.as_('owner');
        await _settle(c, g.code);
        await g
            .repo('u3')
            .submitEntry(g.code, EntryDraft.bankrupt(2000).onBehalfOf('p1'));
        await _settle(c, g.code);
        expect(c.read(incomingEventsProvider(g.code))?.lines, [
          'นายธนาคาร มด ประกาศให้คุณล้มละลาย',
        ]);
      },
    );

    test('going bankrupt oneself is not told to oneself', () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g.repo('owner').submitEntry(g.code, EntryDraft.bankrupt(2000));
      await _settle(c, g.code);
      expect(c.read(incomingEventsProvider(g.code)), isNull);
    });

    test('a press for somebody else is not told to me', () async {
      final g = await _game();
      final c = g.as_('owner');
      await _settle(c, g.code);
      await g
          .repo('u3')
          .submitEntry(g.code, EntryDraft.receive(300, null).onBehalfOf('p2'));
      await _settle(c, g.code);
      expect(c.read(incomingEventsProvider(g.code)), isNull);
    });

    test('my own press is not told to me', () async {
      final g = await _game();
      final c = g.as_('u2');
      await _settle(c, g.code);
      await g.repo('u2').submitEntry(g.code, EntryDraft.transfer('p1', 10));
      await _settle(c, g.code);
      expect(c.read(incomingEventsProvider(g.code)), isNull);
    });
  });

  group('the history text', () {
    String name(String s) => {'p1': 'ต้น', 'p2': 'แพร', 'p3': 'มด'}[s] ?? s;

    test('says the banker pressed it, when somebody else did', () {
      const e = RoomEntry(
        seq: 0,
        kind: EntryKind.receive,
        seat: 'p1',
        from: 'bank',
        to: 'p1',
        amount: 300,
        reason: 'ค่าเช่า',
      );
      final label = describeRoomEntry(e, name, pressedBy: 'มด');
      expect(label.title, 'รับจากธนาคาร ต้น +300');
      expect(label.subtitle, 'ค่าเช่า · โดยนายธนาคาร มด');
      expect(describeRoomEntry(e, name).subtitle, 'ค่าเช่า');
    });

    test('and without a reason says only that', () {
      const e = RoomEntry(
        seq: 0,
        kind: EntryKind.passGo,
        seat: 'p1',
        from: 'bank',
        to: 'p1',
        amount: 200,
        reason: goReason,
      );
      expect(
        describeRoomEntry(e, name, pressedBy: 'มด').subtitle,
        'โดยนายธนาคาร มด',
      );
    });
  });
}
