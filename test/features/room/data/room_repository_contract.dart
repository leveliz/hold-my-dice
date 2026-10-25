import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

/// What a [RoomRepository] test needs besides the repository itself: the
/// same room seen by several people, a way to let time pass, and a look at
/// the presence of a person.
abstract class RoomHarness {
  /// A repository acting as the person with [uid]; all of them share rooms.
  RoomRepository repoFor(String uid);

  /// Lets [time] pass for the people in the rooms (their presence ages).
  Future<void> advance(Duration time);

  Future<DateTime?> lastSeen(String code, String uid);
}

const _settings = RoomSettings(
  startingCash: 1500,
  goAmount: 200,
  maxPlayers: 4,
);

Future<RoomMeta> _create(
  RoomHarness h, {
  RoomSettings settings = _settings,
  String? password,
  String uid = 'owner',
}) => h
    .repoFor(uid)
    .createRoom(
      settings: settings,
      password: password,
      name: 'เจ้าของ',
      color: 1,
    );

Future<Seat> _join(
  RoomHarness h,
  String code,
  String uid, {
  String? password,
}) => h
    .repoFor(uid)
    .joinAsPlayer(code: code, name: 'คน $uid', color: 2, password: password);

Matcher _throws(RoomError error) =>
    throwsA(isA<RoomException>().having((e) => e.error, 'error', error));

/// The behaviour every [RoomRepository] must have, the fake and the real one.
void roomRepositoryContract(RoomHarness Function() create) {
  group('a room repository', () {
    test(
      'creating a room gives a code and a lobby that can be watched',
      () async {
        final h = create();
        final meta = await _create(h);
        expect(meta.code.length, 6);
        expect(meta.ownerUid, 'owner');
        expect(meta.status, RoomStatus.lobby);
        expect(meta.hasPassword, isFalse);
        expect(meta.settings.maxPlayers, 4);
        final seen = await h.repoFor('someone').watchMeta(meta.code).first;
        expect(seen?.code, meta.code);
        expect(seen?.status, RoomStatus.lobby);
      },
    );

    test('readMyMember is null until joining, then the member', () async {
      final h = create();
      final meta = await _create(h);
      expect(await h.repoFor('u2').readMyMember(meta.code), isNull);
      await _join(h, meta.code, 'u2');
      final me = await h.repoFor('u2').readMyMember(meta.code);
      expect(me?.uid, 'u2');
      expect(me?.seat, 'p2');
      expect(me?.role, MemberRole.player);
      expect((await h.repoFor('owner').readMyMember(meta.code))?.seat, 'p1');
    });

    test(
      'readMyMember of a room that does not exist is roomNotFound',
      () async {
        final h = create();
        await expectLater(
          h.repoFor('u2').readMyMember('ZZZZZZ'),
          throwsA(
            isA<RoomException>().having(
              (e) => e.error,
              'error',
              RoomError.roomNotFound,
            ),
          ),
        );
      },
    );

    group('when the owner is gone', () {
      test('a member cannot take the room while the owner is around', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.advance(const Duration(seconds: 30));
        await expectLater(
          h.repoFor('u2').claimOwnership(meta.code),
          _throws(RoomError.ownerStillActive),
        );
      });

      test('a member takes the lobby after 2 minutes and all see it', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.advance(const Duration(minutes: 3));
        await h.repoFor('u2').claimOwnership(meta.code);
        final seen = await h.repoFor('u2').watchMeta(meta.code).first;
        expect(seen?.ownerUid, 'u2');
        // The new owner can start the game, the old one no longer can.
        await expectLater(
          h.repoFor('owner').startGame(meta.code),
          _throws(RoomError.notOwner),
        );
        await h.repoFor('u2').startGame(meta.code);
      });

      test('somebody who is not in the room cannot claim it', () async {
        final h = create();
        final meta = await _create(h);
        await h.advance(const Duration(minutes: 3));
        await expectLater(
          h.repoFor('stranger').claimOwnership(meta.code),
          _throws(RoomError.notAMember),
        );
      });

      test('the owner claiming their own room changes nothing', () async {
        final h = create();
        final meta = await _create(h);
        await h.repoFor('owner').claimOwnership(meta.code);
        final seen = await h.repoFor('owner').watchMeta(meta.code).first;
        expect(seen?.ownerUid, 'owner');
      });

      test('after the start the room can no longer change hands', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.repoFor('owner').startGame(meta.code);
        await h.advance(const Duration(minutes: 3));
        await expectLater(
          h.repoFor('u2').claimOwnership(meta.code),
          _throws(RoomError.alreadyStarted),
        );
      });

      test(
        'taking over the owner\'s seat makes the newcomer the owner',
        () async {
          final h = create();
          final meta = await _create(h);
          await _join(h, meta.code, 'u2');
          await h.advance(const Duration(minutes: 3));
          await h.repoFor('u9').claimSeat(code: meta.code, seatId: 'p1');
          final seen = await h.repoFor('u9').watchMeta(meta.code).first;
          expect(seen?.ownerUid, 'u9');
          await h.repoFor('u9').startGame(meta.code);
        },
      );

      test(
        'after the start taking over the owner\'s seat keeps the owner',
        () async {
          final h = create();
          final meta = await _create(h);
          await _join(h, meta.code, 'u2');
          await h.repoFor('owner').startGame(meta.code);
          await h.advance(const Duration(minutes: 3));
          await h.repoFor('u9').claimSeat(code: meta.code, seatId: 'p1');
          final seen = await h.repoFor('u9').watchMeta(meta.code).first;
          expect(seen?.ownerUid, 'owner');
        },
      );

      test('taking over another seat leaves the owner alone', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.advance(const Duration(minutes: 3));
        await h.repoFor('u9').claimSeat(code: meta.code, seatId: 'p2');
        final seen = await h.repoFor('u9').watchMeta(meta.code).first;
        expect(seen?.ownerUid, 'owner');
      });
    });

    test('the owner sits at p1 and is the first member', () async {
      final h = create();
      final meta = await _create(h);
      final seats = await h.repoFor('owner').readSeats(meta.code);
      expect(seats.length, 8);
      expect(seats[0]?.id, 'p1');
      expect(seats[0]?.uid, 'owner');
      expect(seats.skip(1).every((s) => s == null), isTrue);
      final members = await h.repoFor('owner').watchMembers(meta.code).first;
      expect(members.single.uid, 'owner');
      expect(members.single.role, MemberRole.player);
      expect(members.single.seat, 'p1');
    });

    test('a joining player takes the lowest free seat', () async {
      final h = create();
      final meta = await _create(h);
      expect((await _join(h, meta.code, 'u2')).id, 'p2');
      expect((await _join(h, meta.code, 'u3')).id, 'p3');
      final seats = await h.repoFor('u2').readSeats(meta.code);
      expect(
        [for (final s in seats) s?.uid],
        ['owner', 'u2', 'u3', null, null, null, null, null],
      );
    });

    test('two players joining at once get different seats', () async {
      final h = create();
      final meta = await _create(h);
      final both = await Future.wait([
        _join(h, meta.code, 'u2'),
        _join(h, meta.code, 'u3'),
      ]);
      expect({both[0].id, both[1].id}, {'p2', 'p3'});
    });

    test('joining a full room says roomFull', () async {
      final h = create();
      final meta = await _create(
        h,
        settings: const RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          maxPlayers: 2,
        ),
      );
      await _join(h, meta.code, 'u2');
      await expectLater(_join(h, meta.code, 'u3'), _throws(RoomError.roomFull));
    });

    test(
      'a wrong or missing password says wrongPassword, the right one joins',
      () async {
        final h = create();
        final meta = await _create(h, password: 'secret');
        expect(meta.hasPassword, isTrue);
        await expectLater(
          _join(h, meta.code, 'u2'),
          _throws(RoomError.wrongPassword),
        );
        await expectLater(
          _join(h, meta.code, 'u2', password: 'nope'),
          _throws(RoomError.wrongPassword),
        );
        expect((await _join(h, meta.code, 'u2', password: 'secret')).id, 'p2');
      },
    );

    test('an unknown room says roomNotFound', () async {
      final h = create();
      await expectLater(
        _join(h, 'ZZZZZZ', 'u2'),
        _throws(RoomError.roomNotFound),
      );
      await expectLater(
        h.repoFor('u2').readSeats('ZZZZZZ'),
        _throws(RoomError.roomNotFound),
      );
      expect(await h.repoFor('u2').watchMeta('ZZZZZZ').first, isNull);
    });

    test('after the start players cannot join but a spectator can', () async {
      final h = create();
      final meta = await _create(h);
      await _join(h, meta.code, 'u2');
      await h.repoFor('owner').startGame(meta.code);
      await expectLater(
        _join(h, meta.code, 'u3'),
        _throws(RoomError.alreadyStarted),
      );
      await h
          .repoFor('s1')
          .joinAsSpectator(code: meta.code, name: 'ผู้ชม', color: 3);
      final members = await h.repoFor('owner').watchMembers(meta.code).first;
      final spectator = members.singleWhere((m) => m.uid == 's1');
      expect(spectator.role, MemberRole.spectator);
      expect(spectator.seat, isNull);
    });

    test('a spectator is refused when the room does not allow them', () async {
      final h = create();
      final meta = await _create(
        h,
        settings: const RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          maxPlayers: 4,
          allowSpectators: false,
        ),
      );
      await expectLater(
        h
            .repoFor('s1')
            .joinAsSpectator(code: meta.code, name: 'ผู้ชม', color: 3),
        _throws(RoomError.spectatorsNotAllowed),
      );
    });

    test('joining twice with the same identity keeps the same seat', () async {
      final h = create();
      final meta = await _create(h);
      final first = await _join(h, meta.code, 'u2');
      final again = await _join(h, meta.code, 'u2');
      expect(again.id, first.id);
      final members = await h.repoFor('u2').watchMembers(meta.code).first;
      expect(members.where((m) => m.uid == 'u2').length, 1);
      expect(members.length, 2);
    });

    test('a name longer than 20 characters is cut to 20', () async {
      final h = create();
      final meta = await _create(h);
      final seat = await h
          .repoFor('u2')
          .joinAsPlayer(code: meta.code, name: 'ก' * 30, color: 2);
      expect(seat.name.runes.length, 20);
      final members = await h.repoFor('u2').watchMembers(meta.code).first;
      expect(members.singleWhere((m) => m.uid == 'u2').name.runes.length, 20);
    });

    test(
      'a seat can be claimed once its holder has been quiet for 2 minutes',
      () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.advance(const Duration(minutes: 3));
        final seat = await h
            .repoFor('u9')
            .claimSeat(code: meta.code, seatId: 'p2');
        expect(seat.uid, 'u9');
        expect(seat.id, 'p2');
        final seats = await h.repoFor('u9').readSeats(meta.code);
        expect(seats[1]?.uid, 'u9');
        final members = await h.repoFor('u9').watchMembers(meta.code).first;
        expect(members.singleWhere((m) => m.uid == 'u9').seat, 'p2');
        // The identity that was lost no longer shows as a second person.
        expect(members.any((m) => m.uid == 'u2'), isFalse);
      },
    );

    test('a seat whose holder was seen recently cannot be claimed', () async {
      final h = create();
      final meta = await _create(h);
      await _join(h, meta.code, 'u2');
      await h.advance(const Duration(seconds: 30));
      await expectLater(
        h.repoFor('u9').claimSeat(code: meta.code, seatId: 'p2'),
        _throws(RoomError.seatStillActive),
      );
      expect((await h.repoFor('u2').readSeats(meta.code))[1]?.uid, 'u2');
    });

    test('a heartbeat keeps a seat from being claimed', () async {
      final h = create();
      final meta = await _create(h);
      await _join(h, meta.code, 'u2');
      await h.advance(const Duration(minutes: 3));
      await h.repoFor('u2').heartbeat(meta.code);
      await expectLater(
        h.repoFor('u9').claimSeat(code: meta.code, seatId: 'p2'),
        _throws(RoomError.seatStillActive),
      );
    });

    test('claiming a seat needs the room password', () async {
      final h = create();
      final meta = await _create(h, password: 'secret');
      await _join(h, meta.code, 'u2', password: 'secret');
      await h.advance(const Duration(minutes: 3));
      await expectLater(
        h.repoFor('u9').claimSeat(code: meta.code, seatId: 'p2'),
        _throws(RoomError.wrongPassword),
      );
      final seat = await h
          .repoFor('u9')
          .claimSeat(code: meta.code, seatId: 'p2', password: 'secret');
      expect(seat.uid, 'u9');
    });

    test('only the owner can start, and only with two players', () async {
      final h = create();
      final meta = await _create(h);
      await expectLater(
        h.repoFor('owner').startGame(meta.code),
        _throws(RoomError.notEnoughPlayers),
      );
      await _join(h, meta.code, 'u2');
      await expectLater(
        h.repoFor('u2').startGame(meta.code),
        _throws(RoomError.notOwner),
      );
      await h.repoFor('owner').startGame(meta.code);
    });

    test(
      'starting creates the state with every seat at the starting cash',
      () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await _join(h, meta.code, 'u3');
        await h.repoFor('owner').startGame(meta.code);
        final state = await h.repoFor('u2').watchState(meta.code).first;
        expect(state, isNotNull);
        expect(state!.status, RoomStatus.playing);
        expect(state.seq, 0);
        expect(state.seats, ['p1', 'p2', 'p3']);
        expect(state.balances, {'p1': 1500, 'p2': 1500, 'p3': 1500});
        expect(state.bankrupt, isEmpty);
        expect(state.bankerSeat, isNull);
        final seen = await h.repoFor('u2').watchMeta(meta.code).first;
        expect(seen?.status, RoomStatus.playing);
        await expectLater(
          h.repoFor('owner').startGame(meta.code),
          _throws(RoomError.alreadyStarted),
        );
      },
    );

    test('a bank limit appears in the starting balances', () async {
      final h = create();
      final meta = await _create(
        h,
        settings: const RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          maxPlayers: 4,
          bankLimit: 20000,
        ),
      );
      await _join(h, meta.code, 'u2');
      await h.repoFor('owner').startGame(meta.code);
      final state = await h.repoFor('owner').watchState(meta.code).first;
      expect(state!.balances, {'p1': 1500, 'p2': 1500, 'bank': 20000});
    });

    test(
      'the state is empty before the game starts and appears after',
      () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        final states = <RoomState?>[];
        final sub = h.repoFor('u2').watchState(meta.code).listen(states.add);
        await Future<void>.delayed(Duration.zero);
        await h.repoFor('owner').startGame(meta.code);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(states.first, isNull);
        expect(states.last?.status, RoomStatus.playing);
      },
    );

    test('the member list changes as people join', () async {
      final h = create();
      final meta = await _create(h);
      final counts = <int>[];
      final sub = h
          .repoFor('owner')
          .watchMembers(meta.code)
          .listen((m) => counts.add(m.length));
      await Future<void>.delayed(Duration.zero);
      await _join(h, meta.code, 'u2');
      await _join(h, meta.code, 'u3');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(counts.first, 1);
      expect(counts.last, 3);
    });

    test(
      'a person who is not in the room cannot watch its members or state',
      () async {
        final h = create();
        final meta = await _create(h);
        await expectLater(
          h.repoFor('stranger').watchMembers(meta.code),
          emitsError(
            isA<RoomException>().having(
              (e) => e.error,
              'error',
              RoomError.notAMember,
            ),
          ),
        );
        await expectLater(
          h.repoFor('stranger').watchState(meta.code),
          emitsError(
            isA<RoomException>().having(
              (e) => e.error,
              'error',
              RoomError.notAMember,
            ),
          ),
        );
      },
    );

    test(
      'a heartbeat updates only the presence of the one who sent it',
      () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        final ownerBefore = await h.lastSeen(meta.code, 'owner');
        final u2Before = await h.lastSeen(meta.code, 'u2');
        await h.advance(const Duration(minutes: 1));
        await h.repoFor('u2').heartbeat(meta.code);
        final u2After = await h.lastSeen(meta.code, 'u2');
        expect(u2After!.isAfter(u2Before!), isTrue);
        expect(await h.lastSeen(meta.code, 'owner'), ownerBefore);
      },
    );

    test('a heartbeat from outside the room is refused', () async {
      final h = create();
      final meta = await _create(h);
      await expectLater(
        h.repoFor('stranger').heartbeat(meta.code),
        _throws(RoomError.notAMember),
      );
    });
  });
}
