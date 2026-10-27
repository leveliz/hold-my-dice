import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

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

    group('the money', () {
      Future<String> started(
        RoomHarness h, {
        RoomSettings settings = _settings,
        List<String> others = const ['u2'],
      }) async {
        final meta = await _create(h, settings: settings);
        for (final uid in others) {
          await _join(h, meta.code, uid);
        }
        await h.repoFor('owner').startGame(meta.code);
        return meta.code;
      }

      Future<RoomState> state(RoomHarness h, String code) async =>
          (await h.repoFor('owner').watchState(code).first)!;

      Future<List<RoomEntry>> history(
        RoomHarness h,
        String code, [
        String uid = 'owner',
      ]) => h.repoFor(uid).watchEntries(code).first;

      test(
        'receive, pay and GO move the balances and write the entries in order',
        () async {
          final h = create();
          final code = await started(h);
          final owner = h.repoFor('owner');
          await owner.submitEntry(code, EntryDraft.receive(300, 'ค่าเช่า'));
          await h.repoFor('u2').submitEntry(code, EntryDraft.payBank(500));
          await owner.submitEntry(code, EntryDraft.passGo());
          final s = await state(h, code);
          expect(s.seq, 3);
          expect(s.balances['p1'], 2000);
          expect(s.balances['p2'], 1000);
          final entries = await history(h, code);
          expect(entries.map((e) => e.seq), [0, 1, 2]);
          expect(entries.map((e) => e.kind), [
            EntryKind.receive,
            EntryKind.payBank,
            EntryKind.passGo,
          ]);
          expect(entries.map((e) => e.seat), ['p1', 'p2', 'p1']);
          expect(entries.map((e) => e.amount), [300, 500, 200]);
          expect(entries.map((e) => e.reason), ['ค่าเช่า', null, goReason]);
          expect(entries.map((e) => e.from), ['bank', 'p2', 'bank']);
          expect(entries.map((e) => e.to), ['p1', 'bank', 'p1']);
        },
      );

      test('an entry says who pressed it and carries the press code', () async {
        final h = create();
        final code = await started(h);
        final draft = EntryDraft.payBank(50);
        await h.repoFor('u2').submitEntry(code, draft);
        final e = (await history(h, code)).single;
        expect(e.by, 'u2');
        expect(e.seat, 'p2');
        expect(e.cid, draft.cid);
        expect(e.at, isNotNull);
        expect(e.voided, isFalse);
      });

      group('what is refused writes nothing', () {
        Future<void> refused(
          Future<void> Function(RoomHarness h, String code) press,
          RoomError error, {
          RoomSettings settings = _settings,
          bool begin = true,
        }) async {
          final h = create();
          final code = begin
              ? await started(h, settings: settings)
              : (await _create(h, settings: settings)).code;
          await expectLater(press(h, code), _throws(error));
          if (begin) {
            expect(await history(h, code), isEmpty);
            final s = await state(h, code);
            expect(s.seq, 0);
            expect(s.balances['p1'], settings.startingCash);
          }
        }

        test('paying more than the seat has', () {
          return refused(
            (h, c) =>
                h.repoFor('owner').submitEntry(c, EntryDraft.payBank(1501)),
            RoomError.insufficientFunds,
          );
        });

        for (final amount in [0, -5, 1000000000]) {
          test('an amount of $amount', () {
            return refused(
              (h, c) => h
                  .repoFor('owner')
                  .submitEntry(c, EntryDraft.receive(amount, 'ค่าเช่า')),
              RoomError.invalidAmount,
            );
          });
        }

        test('a payment of 0', () {
          return refused(
            (h, c) => h.repoFor('owner').submitEntry(c, EntryDraft.payBank(0)),
            RoomError.invalidAmount,
          );
        });

        for (final reason in [null, '', '   ']) {
          test(
            'a receive without a reason (${reason == null ? 'null' : '"$reason"'})',
            () {
              return refused(
                (h, c) => h
                    .repoFor('owner')
                    .submitEntry(c, EntryDraft.receive(10, reason)),
                RoomError.reasonRequired,
              );
            },
          );
        }

        test('a receive of more than a limited bank holds', () {
          return refused(
            (h, c) => h
                .repoFor('owner')
                .submitEntry(c, EntryDraft.receive(150, 'ขาย')),
            RoomError.bankEmpty,
            settings: const RoomSettings(
              startingCash: 1500,
              goAmount: 200,
              maxPlayers: 4,
              bankLimit: 100,
            ),
          );
        });

        test('a spectator', () {
          return refused((h, c) async {
            await h
                .repoFor('s1')
                .joinAsSpectator(code: c, name: 'ดู', color: 3);
            await h.repoFor('s1').submitEntry(c, EntryDraft.passGo());
          }, RoomError.notAPlayer);
        });

        test('somebody who is not in the room', () {
          return refused(
            (h, c) => h.repoFor('stranger').submitEntry(c, EntryDraft.passGo()),
            RoomError.notAMember,
          );
        });

        test('a room whose game has not started', () {
          return refused(
            (h, c) => h.repoFor('owner').submitEntry(c, EntryDraft.passGo()),
            RoomError.notStarted,
            begin: false,
          );
        });
      });

      test('a limited bank pays and receives the same amounts', () async {
        final h = create();
        final code = await started(
          h,
          settings: const RoomSettings(
            startingCash: 1500,
            goAmount: 200,
            maxPlayers: 4,
            bankLimit: 1000,
          ),
        );
        final owner = h.repoFor('owner');
        await owner.submitEntry(code, EntryDraft.receive(300, 'ขาย'));
        expect((await state(h, code)).balances['bank'], 700);
        await owner.submitEntry(code, EntryDraft.payBank(100));
        expect((await state(h, code)).balances['bank'], 800);
        await owner.submitEntry(code, EntryDraft.passGo());
        expect((await state(h, code)).balances['bank'], 600);
      });

      test('eight presses at once all go through, in order', () async {
        final h = create();
        final code = await started(h, others: const ['u2', 'u3', 'u4']);
        final who = ['owner', 'u2', 'u3', 'u4', 'owner', 'u2', 'u3', 'u4'];
        await Future.wait([
          for (final (i, uid) in who.indexed)
            h
                .repoFor(uid)
                .submitEntry(code, EntryDraft.receive(10 + i, 'ค่าเช่า')),
        ]);
        final entries = await history(h, code);
        expect(entries.map((e) => e.seq), [0, 1, 2, 3, 4, 5, 6, 7]);
        final s = await state(h, code);
        expect(s.seq, 8);
        expect(
          s.balances.values.fold<int>(0, (a, b) => a + b),
          4 * 1500 +
              [
                for (var i = 0; i < 8; i++) 10 + i,
              ].fold<int>(0, (a, b) => a + b),
        );
      });

      test('the history is in the order of the seq, 10 after 9', () async {
        final h = create();
        final code = await started(h);
        for (var i = 0; i < 12; i++) {
          await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
        }
        expect((await history(h, code)).map((e) => e.seq), [
          for (var i = 0; i < 12; i++) i,
        ]);
      });

      test(
        'a listener hears the new entry and has already the old ones',
        () async {
          final h = create();
          final code = await started(h);
          await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
          final lengths = <int>[];
          final sub = h
              .repoFor('u2')
              .watchEntries(code)
              .listen((l) => lengths.add(l.length));
          await Future<void>.delayed(Duration.zero);
          await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
          await Future<void>.delayed(Duration.zero);
          await sub.cancel();
          expect(lengths, [1, 2]);
        },
      );

      test(
        'a long game is listened to only as far back as the window',
        () async {
          final h = create();
          final code = await started(h);
          final owner = h.repoFor('owner');
          for (var i = 0; i < historyWindow + 5; i++) {
            await owner.submitEntry(code, EntryDraft.passGo());
          }
          final entries = await history(h, code);
          expect(entries, hasLength(historyWindow));
          expect(entries.first.seq, 5);
          expect(entries.last.seq, historyWindow + 4);
          expect((await state(h, code)).seq, historyWindow + 5);
        },
      );

      test(
        'a transfer moves money between two players and is written down',
        () async {
          final h = create();
          final code = await started(h, others: const ['u2', 'u3']);
          await h
              .repoFor('owner')
              .submitEntry(code, EntryDraft.transfer('p3', 700));
          final balances = (await state(h, code)).balances;
          expect(balances, {'p1': 800, 'p2': 1500, 'p3': 2200});
          final entry = (await history(h, code)).single;
          expect(entry.kind, EntryKind.transfer);
          expect(entry.seat, 'p1');
          expect(entry.from, 'p1');
          expect(entry.to, 'p3');
          expect(entry.amount, 700);
        },
      );

      test(
        'a transfer cannot go to oneself, to the bank or to nobody',
        () async {
          final h = create();
          final code = await started(h);
          final owner = h.repoFor('owner');
          for (final to in ['p1', 'bank', 'p9']) {
            await expectLater(
              owner.submitEntry(code, EntryDraft.transfer(to, 100)),
              _throws(RoomError.invalidParties),
              reason: to,
            );
          }
          expect(await history(h, code), isEmpty);
        },
      );

      test('a transfer of more than the giver has is refused', () async {
        final h = create();
        final code = await started(h);
        await expectLater(
          h.repoFor('owner').submitEntry(code, EntryDraft.transfer('p2', 1501)),
          _throws(RoomError.insufficientFunds),
        );
        expect((await state(h, code)).balances, {'p1': 1500, 'p2': 1500});
      });

      test('taking back gives the balances back and marks the entry', () async {
        final h = create();
        final code = await started(h);
        final owner = h.repoFor('owner');
        await owner.submitEntry(code, EntryDraft.receive(300, 'ค่าเช่า'));
        await owner.undoEntry(code, 0);
        final entry = (await history(h, code)).single;
        expect(entry.voided, isTrue);
        final s = await state(h, code);
        expect(s.balances['p1'], 1500);
        expect(s.seq, 1, reason: 'the counter does not move');
      });

      test(
        'taking back a transfer takes the money from the receiver',
        () async {
          final h = create();
          final code = await started(h);
          final owner = h.repoFor('owner');
          await owner.submitEntry(code, EntryDraft.transfer('p2', 700));
          await owner.undoEntry(code, 0);
          expect((await state(h, code)).balances, {'p1': 1500, 'p2': 1500});
        },
      );

      test('after taking back, the next press gets the next number', () async {
        final h = create();
        final code = await started(h);
        await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
        await h.repoFor('owner').undoEntry(code, 0);
        await h.repoFor('u2').submitEntry(code, EntryDraft.passGo());
        final entries = await history(h, code);
        expect(entries.map((e) => (e.seq, e.voided)), [(0, true), (1, false)]);
        expect((await state(h, code)).balances, {'p1': 1500, 'p2': 1700});
      });

      test('taking back the same entry twice is quietly the same', () async {
        final h = create();
        final code = await started(h);
        final owner = h.repoFor('owner');
        await owner.submitEntry(code, EntryDraft.passGo());
        await owner.undoEntry(code, 0);
        await owner.undoEntry(code, 0);
        expect((await state(h, code)).balances['p1'], 1500);
      });

      test('only your own entry can be taken back', () async {
        final h = create();
        final code = await started(h);
        await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
        await expectLater(
          h.repoFor('u2').undoEntry(code, 0),
          _throws(RoomError.tooLate),
        );
        expect((await state(h, code)).balances['p1'], 1700);
      });

      test('an entry with another one after it cannot be taken back', () async {
        final h = create();
        final code = await started(h);
        await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
        await h.repoFor('u2').submitEntry(code, EntryDraft.passGo());
        await expectLater(
          h.repoFor('owner').undoEntry(code, 0),
          _throws(RoomError.tooLate),
        );
        expect((await state(h, code)).balances, {'p1': 1700, 'p2': 1700});
      });

      test('an entry cannot be taken back after the time is up', () async {
        final h = create();
        final code = await started(h);
        final owner = h.repoFor('owner');
        await owner.submitEntry(code, EntryDraft.passGo());
        await h.advance(const Duration(seconds: 6));
        await owner.undoEntry(code, 0);
        await owner.submitEntry(code, EntryDraft.passGo());
        await h.advance(const Duration(seconds: 7));
        await expectLater(owner.undoEntry(code, 1), _throws(RoomError.tooLate));
        expect((await state(h, code)).balances['p1'], 1700);
      });

      test('a bank with a limit gets its money back too', () async {
        final h = create();
        final code = await started(
          h,
          settings: const RoomSettings(
            startingCash: 1500,
            goAmount: 200,
            maxPlayers: 4,
            bankLimit: 5000,
          ),
        );
        final owner = h.repoFor('owner');
        await owner.submitEntry(code, EntryDraft.receive(300, 'ค่าเช่า'));
        await owner.undoEntry(code, 0);
        expect((await state(h, code)).balances['bank'], 5000);
      });

      test('taking back an entry that does not exist is too late', () async {
        final h = create();
        final code = await started(h);
        await expectLater(
          h.repoFor('owner').undoEntry(code, 5),
          _throws(RoomError.tooLate),
        );
      });

      group('a mortgage with a payment and bankruptcy', () {
        /// p1 has 100 left after paying 1,400 to the bank.
        Future<String> poor(
          RoomHarness h, {
          RoomSettings settings = _settings,
          List<String> others = const ['u2'],
        }) async {
          final code = await started(h, settings: settings, others: others);
          await h.repoFor('owner').submitEntry(code, EntryDraft.payBank(1400));
          return code;
        }

        const limited = RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          maxPlayers: 4,
          bankLimit: 5000,
        );

        test('a payment to the bank helped by a mortgage', () async {
          final h = create();
          final code = await poor(h);
          await h
              .repoFor('owner')
              .submitEntry(code, EntryDraft.payBank(700, mortgage: 600));
          final s = await state(h, code);
          expect(s.balances['p1'], 0);
          expect(s.seq, 2);
          final e = (await history(h, code)).last;
          expect(e.kind, EntryKind.payBank);
          expect(e.amount, 700);
          expect(e.mortgage, 600);
        });

        test(
          'a transfer helped by a mortgage pays the receiver in full',
          () async {
            final h = create();
            final code = await poor(h);
            await h
                .repoFor('owner')
                .submitEntry(
                  code,
                  EntryDraft.transfer('p2', 700, mortgage: 650),
                );
            final s = await state(h, code);
            expect(s.balances['p1'], 50);
            expect(s.balances['p2'], 2200);
          },
        );

        test(
          'the bank with a limit pays the mortgage and takes the payment',
          () async {
            final h = create();
            final code = await poor(h, settings: limited);
            await h
                .repoFor('owner')
                .submitEntry(code, EntryDraft.payBank(700, mortgage: 600));
            expect(
              (await state(h, code)).balances['bank'],
              5000 + 1400 - 600 + 700,
            );
          },
        );

        test('it is taken back like any other entry', () async {
          final h = create();
          final code = await poor(h, settings: limited);
          final before = (await state(h, code)).balances;
          await h
              .repoFor('owner')
              .submitEntry(code, EntryDraft.transfer('p2', 700, mortgage: 650));
          await h.repoFor('owner').undoEntry(code, 1);
          expect((await state(h, code)).balances, before);
        });

        group('is refused, and writes nothing', () {
          Future<void> refused(
            Future<void> Function(RoomHarness h, String code) press,
            RoomError error,
          ) async {
            final h = create();
            final code = await poor(h);
            await expectLater(press(h, code), _throws(error));
            expect((await history(h, code)).length, 1);
            expect((await state(h, code)).seq, 1);
          }

          test('when the cash covers the payment', () {
            return refused(
              (h, c) => h
                  .repoFor('u2')
                  .submitEntry(c, EntryDraft.payBank(700, mortgage: 100)),
              RoomError.invalidMortgage,
            );
          });

          test('when more is left over than half the starting cash', () {
            return refused(
              (h, c) => h
                  .repoFor('owner')
                  .submitEntry(c, EntryDraft.payBank(700, mortgage: 1351)),
              RoomError.invalidMortgage,
            );
          });

          test('when it does not cover what is missing', () {
            return refused(
              (h, c) => h
                  .repoFor('owner')
                  .submitEntry(c, EntryDraft.payBank(700, mortgage: 599)),
              RoomError.insufficientFunds,
            );
          });

          test('on a transfer to somebody who is out', () async {
            final h = create();
            final code = await poor(h, others: const ['u2', 'u3']);
            await h.repoFor('u2').submitEntry(code, EntryDraft.payBank(1450));
            await h.repoFor('u2').submitEntry(code, EntryDraft.bankrupt(1000));
            await expectLater(
              h
                  .repoFor('owner')
                  .submitEntry(code, EntryDraft.transfer('p2', 50)),
              _throws(RoomError.invalidParties),
            );
          });
        });

        test(
          'bankruptcy owing a player: the player is paid in full, the seat is out, it is the banker',
          () async {
            final h = create();
            final code = await poor(h);
            await h
                .repoFor('owner')
                .submitEntry(
                  code,
                  EntryDraft.bankrupt(500, creditorSeat: 'p2'),
                );
            final s = await state(h, code);
            expect(s.balances['p1'], 0);
            expect(s.balances['p2'], 2000);
            expect(s.bankrupt, ['p1']);
            expect(s.bankerSeat, 'p1');
            expect(s.seq, 2);
            final e = (await history(h, code)).last;
            expect(e.kind, EntryKind.bankrupt);
            expect(e.bankrupt!.cash, 100);
            expect(e.bankrupt!.owed, 500);
            expect(e.bankrupt!.creditorSeat, 'p2');
            expect(e.amount, isNull);
          },
        );

        test(
          'bankruptcy owing the bank: the cash goes back to the bank',
          () async {
            final h = create();
            final code = await poor(h, settings: limited);
            await h
                .repoFor('owner')
                .submitEntry(code, EntryDraft.bankrupt(500));
            final s = await state(h, code);
            expect(s.balances['bank'], 5000 + 1400 + 100);
            expect(s.balances['p1'], 0);
          },
        );

        test('a seat that is out can press nothing and gets nothing', () async {
          final h = create();
          final code = await poor(h);
          await h.repoFor('owner').submitEntry(code, EntryDraft.bankrupt(500));
          await expectLater(
            h.repoFor('owner').submitEntry(code, EntryDraft.passGo()),
            _throws(RoomError.notAPlayer),
          );
          await expectLater(
            h.repoFor('u2').submitEntry(code, EntryDraft.transfer('p1', 10)),
            _throws(RoomError.invalidParties),
          );
        });

        test('the second to go out does not take the banker over', () async {
          final h = create();
          final code = await started(h, others: const ['u2', 'u3']);
          await h.repoFor('u2').submitEntry(code, EntryDraft.payBank(1400));
          await h.repoFor('owner').submitEntry(code, EntryDraft.payBank(1450));
          await h
              .repoFor('u2')
              .submitEntry(code, EntryDraft.bankrupt(500, creditorSeat: 'p3'));
          await h
              .repoFor('owner')
              .submitEntry(code, EntryDraft.bankrupt(500, creditorSeat: 'p3'));
          final s = await state(h, code);
          expect(s.bankrupt, ['p2', 'p1']);
          expect(s.bankerSeat, 'p2');
        });

        group('is refused, and writes nothing (bankruptcy)', () {
          Future<void> refused(
            Future<void> Function(RoomHarness h, String code) press,
            RoomError error,
          ) async {
            final h = create();
            final code = await poor(h, others: const ['u2', 'u3']);
            await h.repoFor('u3').submitEntry(code, EntryDraft.payBank(1450));
            await h.repoFor('u3').submitEntry(code, EntryDraft.bankrupt(1000));
            final seq = (await state(h, code)).seq;
            await expectLater(press(h, code), _throws(error));
            expect((await state(h, code)).seq, seq);
            expect((await state(h, code)).bankrupt, ['p3']);
          }

          test('when the cash pays the debt', () {
            return refused(
              (h, c) =>
                  h.repoFor('u2').submitEntry(c, EntryDraft.bankrupt(1500)),
              RoomError.invalidBankrupt,
            );
          });

          test('when the debt is over ten times the starting cash', () {
            return refused(
              (h, c) =>
                  h.repoFor('u2').submitEntry(c, EntryDraft.bankrupt(15001)),
              RoomError.invalidBankrupt,
            );
          });

          test('owing yourself', () {
            return refused(
              (h, c) => h
                  .repoFor('u2')
                  .submitEntry(
                    c,
                    EntryDraft.bankrupt(2000, creditorSeat: 'p2'),
                  ),
              RoomError.invalidParties,
            );
          });

          test('owing somebody who is out', () {
            return refused(
              (h, c) => h
                  .repoFor('u2')
                  .submitEntry(
                    c,
                    EntryDraft.bankrupt(2000, creditorSeat: 'p3'),
                  ),
              RoomError.creditorOut,
            );
          });

          test('by somebody who is out', () {
            return refused(
              (h, c) =>
                  h.repoFor('u3').submitEntry(c, EntryDraft.bankrupt(2000)),
              RoomError.notAPlayer,
            );
          });
        });

        test('a bankruptcy is not taken back', () async {
          final h = create();
          final code = await poor(h);
          await h.repoFor('owner').submitEntry(code, EntryDraft.bankrupt(500));
          await expectLater(
            h.repoFor('owner').undoEntry(code, 1),
            _throws(RoomError.tooLate),
          );
          expect((await state(h, code)).bankrupt, ['p1']);
        });

        test('a request is paid with a mortgage', () async {
          final h = create();
          final code = await poor(h);
          await h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 700);
          await h
              .repoFor('owner')
              .payRequest(
                code,
                'p2_p1',
                cid: 'cid-for-request-1',
                mortgage: 650,
              );
          final s = await state(h, code);
          expect(s.balances['p1'], 50);
          expect(s.balances['p2'], 2200);
          final r = (await h.repoFor('owner').watchRequests(code).first).single;
          expect(r.status, RequestStatus.paid);
        });
      });

      group('the banker', () {
        /// Three players; p3 goes out first and is the banker.
        Future<String> withBanker(RoomHarness h) async {
          final code = await started(h, others: const ['u2', 'u3']);
          await h.repoFor('u3').submitEntry(code, EntryDraft.payBank(1400));
          await h.repoFor('u3').submitEntry(code, EntryDraft.bankrupt(500));
          return code;
        }

        EntryDraft forP1(EntryDraft d) => d.onBehalfOf('p1');

        test(
          'the first to go out is the banker, and presses for the others',
          () async {
            final h = create();
            final code = await withBanker(h);
            expect((await state(h, code)).bankerSeat, 'p3');
            final banker = h.repoFor('u3');
            await banker.submitEntry(
              code,
              forP1(EntryDraft.receive(300, null)),
            );
            await banker.submitEntry(
              code,
              EntryDraft.passGo().onBehalfOf('p2'),
            );
            await banker.submitEntry(code, forP1(EntryDraft.payBank(100)));
            final s = await state(h, code);
            expect(s.balances['p1'], 1700);
            expect(s.balances['p2'], 1700);
            final e = (await history(
              h,
              code,
            )).where((e) => e.by == 'u3' && e.kind == EntryKind.receive).single;
            expect(
              e.seat,
              'p1',
              reason: 'the seat is the one whose money moved',
            );
            expect(e.reason, isNull);
          },
        );

        test(
          'a payment helped by a mortgage is pressed for the one who cannot pay',
          () async {
            final h = create();
            final code = await withBanker(h);
            await h
                .repoFor('u3')
                .submitEntry(code, forP1(EntryDraft.payBank(1400)));
            await h
                .repoFor('u3')
                .submitEntry(
                  code,
                  forP1(EntryDraft.payBank(700, mortgage: 600)),
                );
            expect((await state(h, code)).balances['p1'], 0);
          },
        );

        test(
          'a bankruptcy owed to the bank is declared by the banker, who stays the banker',
          () async {
            final h = create();
            final code = await withBanker(h);
            await h
                .repoFor('u3')
                .submitEntry(code, EntryDraft.bankrupt(2000).onBehalfOf('p2'));
            final s = await state(h, code);
            expect(s.bankrupt, ['p3', 'p2']);
            expect(s.bankerSeat, 'p3');
            expect(s.balances['p2'], 0);
          },
        );

        test('what the banker pressed is taken back by the banker', () async {
          final h = create();
          final code = await withBanker(h);
          await h
              .repoFor('u3')
              .submitEntry(code, forP1(EntryDraft.receive(300, null)));
          final seq = (await state(h, code)).seq - 1;
          await h.repoFor('u3').undoEntry(code, seq);
          expect((await state(h, code)).balances['p1'], 1500);
        });

        test(
          'a press of the banker that is sent again is written once',
          () async {
            final h = create();
            final code = await withBanker(h);
            final d = forP1(EntryDraft.receive(300, null));
            await h.repoFor('u3').submitEntry(code, d);
            await h.repoFor('u3').submitEntry(code, d);
            expect((await state(h, code)).balances['p1'], 1800);
          },
        );

        group('is refused, and writes nothing', () {
          Future<void> refused(
            Future<void> Function(RoomHarness h, String code) press,
            RoomError error,
          ) async {
            final h = create();
            final code = await withBanker(h);
            final seq = (await state(h, code)).seq;
            await expectLater(press(h, code), _throws(error));
            expect((await state(h, code)).seq, seq);
          }

          test(
            'a player pressing the bank\'s buttons for their own seat',
            () async {
              for (final d in [
                EntryDraft.receive(10, 'x'),
                EntryDraft.passGo(),
                EntryDraft.payBank(10),
              ]) {
                await refused(
                  (h, c) => h.repoFor('u2').submitEntry(c, d),
                  RoomError.bankerPresses,
                );
              }
            },
          );

          test('a payment of a player helped by a mortgage', () {
            return refused(
              (h, c) => h
                  .repoFor('u2')
                  .submitEntry(
                    c,
                    EntryDraft.transfer('p1', 2000, mortgage: 600),
                  ),
              RoomError.bankerPresses,
            );
          });

          test('a player pressing for somebody else', () {
            return refused(
              (h, c) => h
                  .repoFor('u2')
                  .submitEntry(c, forP1(EntryDraft.receive(10, null))),
              RoomError.notBanker,
            );
          });

          test('the banker pressing a transfer for somebody else', () {
            return refused(
              (h, c) => h
                  .repoFor('u3')
                  .submitEntry(
                    c,
                    EntryDraft.transfer('p2', 10).onBehalfOf('p1'),
                  ),
              RoomError.notBanker,
            );
          });

          test('the banker declaring a bankruptcy owed to a player', () {
            return refused(
              (h, c) => h
                  .repoFor('u3')
                  .submitEntry(
                    c,
                    EntryDraft.bankrupt(
                      2000,
                      creditorSeat: 'p1',
                    ).onBehalfOf('p2'),
                  ),
              RoomError.notBanker,
            );
          });

          test('the banker pressing for a seat that is out', () {
            return refused(
              (h, c) => h
                  .repoFor('u3')
                  .submitEntry(c, EntryDraft.passGo().onBehalfOf('p3')),
              RoomError.notAPlayer,
            );
          });

          test('the banker pressing for a seat that is not in the game', () {
            return refused(
              (h, c) => h
                  .repoFor('u3')
                  .submitEntry(c, EntryDraft.passGo().onBehalfOf('p8')),
              RoomError.notAPlayer,
            );
          });
        });

        test(
          'a player can still give a friend money, and ask for it',
          () async {
            final h = create();
            final code = await withBanker(h);
            await h
                .repoFor('u2')
                .submitEntry(code, EntryDraft.transfer('p1', 100));
            expect((await state(h, code)).balances['p1'], 1600);
          },
        );

        /// As [withBanker], and p2 is out too (declared by the banker): the
        /// banker p3 has another seat that is out to hand the seat to.
        Future<String> withTwoOut(RoomHarness h) async {
          final code = await withBanker(h);
          await h
              .repoFor('u3')
              .submitEntry(code, EntryDraft.bankrupt(2000).onBehalfOf('p2'));
          return code;
        }

        group('handing it on', () {
          test('to another seat that is out, who presses next', () async {
            final h = create();
            final code = await withTwoOut(h);
            await h.repoFor('u3').passBanker(code, 'p2');
            expect((await state(h, code)).bankerSeat, 'p2');
            await h
                .repoFor('u2')
                .submitEntry(code, EntryDraft.passGo().onBehalfOf('p1'));
            await expectLater(
              h
                  .repoFor('u3')
                  .submitEntry(code, EntryDraft.passGo().onBehalfOf('p1')),
              _throws(RoomError.notBanker),
            );
          });

          test('not to a seat that still plays', () async {
            final h = create();
            final code = await withTwoOut(h);
            await expectLater(
              h.repoFor('u3').passBanker(code, 'p1'),
              _throws(RoomError.bankerMustBeOut),
            );
            expect((await state(h, code)).bankerSeat, 'p3');
          });

          test(
            'the only one who is out has nobody to hand it to, as a player still plays',
            () async {
              final h = create();
              final code = await withBanker(h);
              for (final seat in ['p1', 'p2']) {
                await expectLater(
                  h.repoFor('u3').passBanker(code, seat),
                  _throws(RoomError.bankerMustBeOut),
                  reason: seat,
                );
              }
            },
          );

          test('only the banker, only to another seat of the game', () async {
            final h = create();
            final code = await withTwoOut(h);
            await expectLater(
              h.repoFor('u2').passBanker(code, 'p2'),
              _throws(RoomError.notBanker),
            );
            await expectLater(
              h.repoFor('u3').passBanker(code, 'p3'),
              _throws(RoomError.invalidParties),
            );
            await expectLater(
              h.repoFor('u3').passBanker(code, 'p8'),
              _throws(RoomError.invalidParties),
            );
            expect((await state(h, code)).bankerSeat, 'p3');
          });

          test(
            'there is nothing to hand on before somebody goes out',
            () async {
              final h = create();
              final code = await started(h, others: const ['u2']);
              await expectLater(
                h.repoFor('owner').passBanker(code, 'p2'),
                _throws(RoomError.notBanker),
              );
            },
          );
        });

        group('taking it over', () {
          test(
            'a player who is out, from a banker not seen for 2 minutes, which also counts the taker as seen',
            () async {
              final h = create();
              final code = await withTwoOut(h);
              await h.repoFor('u3').heartbeat(code);
              await h.advance(const Duration(minutes: 3));
              final before = await h.lastSeen(code, 'u2');
              await h.repoFor('u2').takeOverBanker(code);
              expect((await state(h, code)).bankerSeat, 'p2');
              expect((await h.lastSeen(code, 'u2'))!.isAfter(before!), isTrue);
            },
          );

          test(
            'is refused while the banker was seen less than 2 minutes ago',
            () async {
              final h = create();
              final code = await withTwoOut(h);
              await h.repoFor('u3').heartbeat(code);
              await h.advance(const Duration(seconds: 90));
              await expectLater(
                h.repoFor('u2').takeOverBanker(code),
                _throws(RoomError.bankerStillActive),
              );
              expect((await state(h, code)).bankerSeat, 'p3');
            },
          );

          test(
            'a player who still plays cannot, however long the banker has been gone',
            () async {
              final h = create();
              final code = await withBanker(h);
              await h.repoFor('u3').heartbeat(code);
              await h.advance(const Duration(minutes: 3));
              for (final uid in ['owner', 'u2']) {
                await expectLater(
                  h.repoFor(uid).takeOverBanker(code),
                  _throws(RoomError.bankerMustBeOut),
                  reason: uid,
                );
              }
              expect((await state(h, code)).bankerSeat, 'p3');
            },
          );

          test(
            'is refused for the banker, a watcher and somebody who is not in the room',
            () async {
              final h = create();
              final code = await withBanker(h);
              await h.repoFor('u3').heartbeat(code);
              await h.advance(const Duration(minutes: 3));
              await expectLater(
                h.repoFor('u3').takeOverBanker(code),
                _throws(RoomError.invalidParties),
              );
              await h
                  .repoFor('s1')
                  .joinAsSpectator(code: code, name: 'ดู', color: 3);
              await expectLater(
                h.repoFor('s1').takeOverBanker(code),
                _throws(RoomError.notAPlayer),
              );
              await expectLater(
                h.repoFor('stranger').takeOverBanker(code),
                _throws(RoomError.notAMember),
              );
            },
          );

          test('is refused when there is no banker', () async {
            final h = create();
            final code = await started(h, others: const ['u2']);
            await h.advance(const Duration(minutes: 3));
            await expectLater(
              h.repoFor('u2').takeOverBanker(code),
              _throws(RoomError.notBanker),
            );
          });
        });

        group('giving it up', () {
          test(
            'the banker may at any time: nobody is the banker, and the players press for themselves',
            () async {
              final h = create();
              final code = await withBanker(h);
              await h.repoFor('u3').releaseBanker(code);
              expect((await state(h, code)).bankerSeat, isNull);
              expect((await state(h, code)).bankrupt, ['p3']);
              await h.repoFor('u2').submitEntry(code, EntryDraft.passGo());
              expect((await state(h, code)).balances['p2'], 1700);
              // The one who is out has nothing to press for.
              await expectLater(
                h.repoFor('u3').submitEntry(code, EntryDraft.passGo()),
                _throws(RoomError.notAPlayer),
              );
            },
          );

          test(
            'a player who still plays, when the banker has been gone for 2 minutes, which also counts them as seen',
            () async {
              final h = create();
              final code = await withBanker(h);
              await h.repoFor('u3').heartbeat(code);
              await h.advance(const Duration(minutes: 3));
              final before = await h.lastSeen(code, 'u2');
              await h.repoFor('u2').releaseBanker(code);
              expect((await state(h, code)).bankerSeat, isNull);
              expect((await h.lastSeen(code, 'u2'))!.isAfter(before!), isTrue);
            },
          );

          test(
            'is refused while the banker was seen less than 2 minutes ago',
            () async {
              final h = create();
              final code = await withBanker(h);
              await h.repoFor('u3').heartbeat(code);
              await h.advance(const Duration(seconds: 90));
              await expectLater(
                h.repoFor('u2').releaseBanker(code),
                _throws(RoomError.bankerStillActive),
              );
              expect((await state(h, code)).bankerSeat, 'p3');
            },
          );

          test(
            'is refused for a watcher and for somebody who is not in the room',
            () async {
              final h = create();
              final code = await withBanker(h);
              await h.advance(const Duration(minutes: 3));
              await h
                  .repoFor('s1')
                  .joinAsSpectator(code: code, name: 'ดู', color: 3);
              await expectLater(
                h.repoFor('s1').releaseBanker(code),
                _throws(RoomError.notAPlayer),
              );
              await expectLater(
                h.repoFor('stranger').releaseBanker(code),
                _throws(RoomError.notAMember),
              );
            },
          );

          test('is refused when there is no banker', () async {
            final h = create();
            final code = await started(h, others: const ['u2']);
            await expectLater(
              h.repoFor('u2').releaseBanker(code),
              _throws(RoomError.notBanker),
            );
          });

          test('the next to go out is the banker', () async {
            final h = create();
            final code = await withBanker(h);
            await h.repoFor('u3').releaseBanker(code);
            await h.repoFor('u2').submitEntry(code, EntryDraft.payBank(1400));
            await h.repoFor('u2').submitEntry(code, EntryDraft.bankrupt(500));
            expect((await state(h, code)).bankerSeat, 'p2');
          });
        });
      });

      group('requests to pay', () {
        Future<List<RoomRequest>> requests(
          RoomHarness h,
          String code, [
          String uid = 'owner',
        ]) => h.repoFor(uid).watchRequests(code).first;

        Future<String> twoPlayers(RoomHarness h) =>
            started(h, others: const ['u2', 'u3']);

        test('there are none at first', () async {
          final h = create();
          final code = await twoPlayers(h);
          expect(await requests(h, code), isEmpty);
        });

        test('asking leaves an open request that every player sees', () async {
          final h = create();
          final code = await twoPlayers(h);
          await h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 300);
          for (final uid in ['owner', 'u2', 'u3']) {
            final r = (await requests(h, code, uid)).single;
            expect(r.id, 'p2_p1', reason: uid);
            expect(r.fromSeat, 'p1');
            expect(r.toSeat, 'p2');
            expect(r.amount, 300);
            expect(r.isOpen, isTrue);
            expect(r.createdAt, isNotNull);
          }
        });

        test(
          'asking yourself, nobody, or for a bad amount is refused',
          () async {
            final h = create();
            final code = await twoPlayers(h);
            final u2 = h.repoFor('u2');
            await expectLater(
              u2.requestMoney(code, fromSeat: 'p2', amount: 10),
              _throws(RoomError.invalidParties),
            );
            await expectLater(
              u2.requestMoney(code, fromSeat: 'p9', amount: 10),
              _throws(RoomError.invalidParties),
            );
            await expectLater(
              u2.requestMoney(code, fromSeat: 'p1', amount: 0),
              _throws(RoomError.invalidAmount),
            );
            await expectLater(
              u2.requestMoney(code, fromSeat: 'p1', amount: 1000000000),
              _throws(RoomError.invalidAmount),
            );
            expect(await requests(h, code), isEmpty);
          },
        );

        test('asking while the first ask is still open is refused', () async {
          final h = create();
          final code = await twoPlayers(h);
          final u2 = h.repoFor('u2');
          await u2.requestMoney(code, fromSeat: 'p1', amount: 300);
          await expectLater(
            u2.requestMoney(code, fromSeat: 'p1', amount: 50),
            _throws(RoomError.requestOpen),
          );
          expect((await requests(h, code)).single.amount, 300);
        });

        test('another person asked is another place', () async {
          final h = create();
          final code = await twoPlayers(h);
          final u2 = h.repoFor('u2');
          await u2.requestMoney(code, fromSeat: 'p1', amount: 300);
          await u2.requestMoney(code, fromSeat: 'p3', amount: 20);
          expect((await requests(h, code)).map((r) => r.id).toSet(), {
            'p2_p1',
            'p2_p3',
          });
        });

        test(
          'asking again after it was closed or ran out replaces it',
          () async {
            final h = create();
            final code = await twoPlayers(h);
            final u2 = h.repoFor('u2');
            await u2.requestMoney(code, fromSeat: 'p1', amount: 300);
            await u2.cancelRequest(code, 'p2_p1');
            await u2.requestMoney(code, fromSeat: 'p1', amount: 50);
            var r = (await requests(h, code)).single;
            expect((r.amount, r.status), (50, RequestStatus.open));
            await h.advance(const Duration(minutes: 3));
            await u2.requestMoney(code, fromSeat: 'p1', amount: 70);
            r = (await requests(h, code)).single;
            expect(r.amount, 70);
          },
        );

        test(
          'the asker or the payer can close it, and closing twice is quiet',
          () async {
            final h = create();
            final code = await twoPlayers(h);
            await h
                .repoFor('u2')
                .requestMoney(code, fromSeat: 'p1', amount: 300);
            await h.repoFor('owner').cancelRequest(code, 'p2_p1');
            expect(
              (await requests(h, code)).single.status,
              RequestStatus.cancelled,
            );
            await h.repoFor('owner').cancelRequest(code, 'p2_p1');
            await h
                .repoFor('u2')
                .requestMoney(code, fromSeat: 'p1', amount: 80);
            await h.repoFor('u2').cancelRequest(code, 'p2_p1');
            expect(
              (await requests(h, code)).single.status,
              RequestStatus.cancelled,
            );
          },
        );

        test(
          'a third player cannot close it, and a missing one is gone',
          () async {
            final h = create();
            final code = await twoPlayers(h);
            await h
                .repoFor('u2')
                .requestMoney(code, fromSeat: 'p1', amount: 300);
            await expectLater(
              h.repoFor('u3').cancelRequest(code, 'p2_p1'),
              _throws(RoomError.notAPlayer),
            );
            expect((await requests(h, code)).single.isOpen, isTrue);
            await expectLater(
              h.repoFor('u2').cancelRequest(code, 'p2_p3'),
              _throws(RoomError.requestGone),
            );
          },
        );

        test(
          'the payer pays: the money moves, the history says so, the request is paid',
          () async {
            final h = create();
            final code = await twoPlayers(h);
            await h
                .repoFor('u2')
                .requestMoney(code, fromSeat: 'p1', amount: 300);
            await h
                .repoFor('owner')
                .payRequest(code, 'p2_p1', cid: 'cidcidcid1234');
            expect((await state(h, code)).balances, {
              'p1': 1200,
              'p2': 1800,
              'p3': 1500,
            });
            final entry = (await history(h, code)).single;
            expect(entry.kind, EntryKind.transfer);
            expect((entry.from, entry.to, entry.amount), ('p1', 'p2', 300));
            expect(entry.reason, requestReason);
            expect(entry.cid, 'cidcidcid1234');
            final r = (await requests(h, code)).single;
            expect(r.status, RequestStatus.paid);
            expect(r.paidSeq, entry.seq);
          },
        );

        test('paying with the same code twice is paying once', () async {
          final h = create();
          final code = await twoPlayers(h);
          await h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 300);
          await h
              .repoFor('owner')
              .payRequest(code, 'p2_p1', cid: 'cidcidcid1234');
          await h
              .repoFor('owner')
              .payRequest(code, 'p2_p1', cid: 'cidcidcid1234');
          expect((await state(h, code)).balances['p1'], 1200);
          expect(await history(h, code), hasLength(1));
        });

        test('a request that is already paid cannot be paid again', () async {
          final h = create();
          final code = await twoPlayers(h);
          await h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 300);
          await h
              .repoFor('owner')
              .payRequest(code, 'p2_p1', cid: 'cidcidcid1234');
          await expectLater(
            h.repoFor('owner').payRequest(code, 'p2_p1', cid: 'cidcidcid9999'),
            _throws(RoomError.alreadyPaid),
          );
          expect((await state(h, code)).balances['p1'], 1200);
        });

        test('only the one who is asked can pay', () async {
          final h = create();
          final code = await twoPlayers(h);
          await h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 300);
          for (final uid in ['u2', 'u3']) {
            await expectLater(
              h.repoFor(uid).payRequest(code, 'p2_p1', cid: 'cidcidcid1234'),
              _throws(RoomError.notAPlayer),
              reason: uid,
            );
          }
          expect(await history(h, code), isEmpty);
        });

        test(
          'a request that was cancelled, ran out or does not exist cannot be paid',
          () async {
            final h = create();
            final code = await twoPlayers(h);
            final owner = h.repoFor('owner');
            await h
                .repoFor('u2')
                .requestMoney(code, fromSeat: 'p1', amount: 300);
            await h.repoFor('u2').cancelRequest(code, 'p2_p1');
            await expectLater(
              owner.payRequest(code, 'p2_p1', cid: 'cidcidcid1234'),
              _throws(RoomError.requestGone),
            );
            await h
                .repoFor('u2')
                .requestMoney(code, fromSeat: 'p1', amount: 300);
            await h.advance(const Duration(minutes: 3));
            await expectLater(
              owner.payRequest(code, 'p2_p1', cid: 'cidcidcid1234'),
              _throws(RoomError.requestGone),
            );
            await expectLater(
              owner.payRequest(code, 'p2_p9', cid: 'cidcidcid1234'),
              _throws(RoomError.requestGone),
            );
            expect(await history(h, code), isEmpty);
          },
        );

        test(
          'paying more than you hold is refused and the request stays open',
          () async {
            final h = create();
            final code = await twoPlayers(h);
            await h
                .repoFor('u2')
                .requestMoney(code, fromSeat: 'p1', amount: 2000);
            await expectLater(
              h
                  .repoFor('owner')
                  .payRequest(code, 'p2_p1', cid: 'cidcidcid1234'),
              _throws(RoomError.insufficientFunds),
            );
            expect((await requests(h, code)).single.isOpen, isTrue);
            expect((await state(h, code)).balances['p1'], 1500);
          },
        );

        test('a request that was paid cannot be cancelled', () async {
          final h = create();
          final code = await twoPlayers(h);
          await h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 300);
          await h
              .repoFor('owner')
              .payRequest(code, 'p2_p1', cid: 'cidcidcid1234');
          for (final uid in ['u2', 'owner']) {
            await expectLater(
              h.repoFor(uid).cancelRequest(code, 'p2_p1'),
              _throws(RoomError.alreadyPaid),
              reason: uid,
            );
          }
          expect((await requests(h, code)).single.status, RequestStatus.paid);
        });

        test('a payment of a request cannot be taken back', () async {
          final h = create();
          final code = await twoPlayers(h);
          await h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 300);
          await h
              .repoFor('owner')
              .payRequest(code, 'p2_p1', cid: 'cidcidcid1234');
          await expectLater(
            h.repoFor('owner').undoEntry(code, 0),
            _throws(RoomError.tooLate),
          );
          expect((await state(h, code)).balances['p1'], 1200);
          expect((await requests(h, code)).single.status, RequestStatus.paid);
        });

        test('a player who is out cannot be asked, nor ask', () async {
          final h = create();
          final code = await twoPlayers(h);
          // Only the owner of the room can go out in the fake: the first slice
          // has no bankruptcy, so the state is the only way to see this case.
          // The parties are checked against the seats of the game instead.
          await expectLater(
            h.repoFor('u2').requestMoney(code, fromSeat: 'p4', amount: 10),
            _throws(RoomError.invalidParties),
          );
        });
      });

      test('a press sent twice with the same code is written once', () async {
        final h = create();
        final code = await started(h);
        final draft = EntryDraft.receive(100, 'ค่าเช่า');
        await h.repoFor('owner').submitEntry(code, draft);
        await h.repoFor('owner').submitEntry(code, draft);
        expect(await history(h, code), hasLength(1));
        expect((await state(h, code)).balances['p1'], 1600);
      });

      test('the same code from another seat is another press', () async {
        final h = create();
        final code = await started(h);
        await h
            .repoFor('owner')
            .submitEntry(
              code,
              EntryDraft.receive(100, 'ก', cid: 'samesamesame'),
            );
        await h
            .repoFor('u2')
            .submitEntry(
              code,
              EntryDraft.receive(100, 'ก', cid: 'samesamesame'),
            );
        expect(await history(h, code), hasLength(2));
      });

      test('a reason is cut to 60 units and never inside an emoji', () async {
        final h = create();
        final code = await started(h);
        final owner = h.repoFor('owner');
        await owner.submitEntry(code, EntryDraft.receive(10, '${'x' * 59}😀'));
        await owner.submitEntry(code, EntryDraft.receive(10, 'ก' * 70));
        final entries = await history(h, code);
        expect(entries[0].reason, 'x' * 59);
        expect(entries[1].reason, 'ก' * 60);
      });

      test(
        'a reason is trimmed, and a payment with a blank one has none',
        () async {
          final h = create();
          final code = await started(h);
          final owner = h.repoFor('owner');
          await owner.submitEntry(code, EntryDraft.receive(10, '  ค่าเช่า  '));
          await owner.submitEntry(code, EntryDraft.payBank(10, reason: '   '));
          await owner.submitEntry(
            code,
            EntryDraft.payBank(10, reason: ' ภาษี '),
          );
          final entries = await history(h, code);
          expect(entries.map((e) => e.reason), ['ค่าเช่า', null, 'ภาษี']);
        },
      );

      test(
        'GO pays the amount the room was made with, whatever was asked',
        () async {
          final h = create();
          final code = await started(
            h,
            settings: const RoomSettings(
              startingCash: 1500,
              goAmount: 500,
              maxPlayers: 4,
            ),
          );
          await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
          expect((await state(h, code)).balances['p1'], 2000);
          expect((await history(h, code)).single.amount, 500);
        },
      );

      test('spectators read the history, strangers do not', () async {
        final h = create();
        final code = await started(h);
        await h.repoFor('owner').submitEntry(code, EntryDraft.passGo());
        await h.repoFor('s1').joinAsSpectator(code: code, name: 'ดู', color: 3);
        expect(await history(h, code, 's1'), hasLength(1));
        await expectLater(
          history(h, code, 'stranger'),
          _throws(RoomError.notAMember),
        );
      });

      test('the history of a room that does not exist', () async {
        final h = create();
        await expectLater(
          history(h, 'ZZZZZZ', 'u2'),
          _throws(RoomError.roomNotFound),
        );
      });
    });

    group('ending a game', () {
      /// Three players, started; p3 is the banker if [banker].
      Future<String> game(RoomHarness h, {bool banker = false}) async {
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await _join(h, meta.code, 'u3');
        await h.repoFor('owner').startGame(meta.code);
        await h.repoFor('owner').submitEntry(meta.code, EntryDraft.passGo());
        if (banker) {
          await h
              .repoFor('u3')
              .submitEntry(meta.code, EntryDraft.bankrupt(2000));
        }
        return meta.code;
      }

      Future<RoomMeta?> metaOf(RoomHarness h, String code) =>
          h.repoFor('owner').watchMeta(code).first;

      test(
        'the owner ends it: everybody sees it ended, with the money as it was',
        () async {
          final h = create();
          final code = await game(h);
          await h.repoFor('owner').endGame(code);
          for (final uid in ['owner', 'u2', 'u3']) {
            final meta = await h.repoFor(uid).watchMeta(code).first;
            expect(meta?.status, RoomStatus.ended, reason: uid);
            expect(meta?.endedAt, isNotNull, reason: uid);
            final s = await h.repoFor(uid).watchState(code).first;
            expect(s?.status, RoomStatus.ended, reason: uid);
            expect(s?.balances['p1'], 1700, reason: uid);
            expect(s?.seq, 1);
            expect(
              (await h.repoFor(uid).watchMembers(code).first).length,
              3,
              reason: uid,
            );
            expect((await h.repoFor(uid).watchEntries(code).first).length, 1);
          }
        },
      );

      test(
        'a member can still read themselves in an ended game, a stranger cannot',
        () async {
          final h = create();
          final code = await game(h);
          await h.repoFor('owner').endGame(code);
          expect((await h.repoFor('u2').readMyMember(code))?.seat, 'p2');
          expect(await h.repoFor('stranger').readMyMember(code), isNull);
        },
      );

      test('the banker ends it', () async {
        final h = create();
        final code = await game(h, banker: true);
        await h.repoFor('u3').endGame(code);
        expect((await metaOf(h, code))?.status, RoomStatus.ended);
      });

      test('nothing can be pressed once it has ended', () async {
        final h = create();
        final code = await game(h);
        await h.repoFor('owner').endGame(code);
        await expectLater(
          h.repoFor('u2').submitEntry(code, EntryDraft.payBank(10)),
          _throws(RoomError.roomNotFound),
        );
        await expectLater(
          h.repoFor('owner').undoEntry(code, 0),
          _throws(RoomError.roomNotFound),
        );
        await expectLater(
          h.repoFor('u2').requestMoney(code, fromSeat: 'p1', amount: 10),
          _throws(RoomError.roomNotFound),
        );
      });

      test('ending it twice is fine', () async {
        final h = create();
        final code = await game(h);
        await h.repoFor('owner').endGame(code);
        await h.repoFor('owner').endGame(code);
        await h.repoFor('u2').endGame(code);
        expect((await metaOf(h, code))?.status, RoomStatus.ended);
      });

      test('a player cannot while the owner was seen a moment ago', () async {
        final h = create();
        final code = await game(h);
        await expectLater(
          h.repoFor('u2').endGame(code),
          _throws(RoomError.notAllowed),
        );
        expect((await metaOf(h, code))?.status, RoomStatus.playing);
      });

      test(
        'a player can once the owner has been gone for over 10 minutes',
        () async {
          final h = create();
          final code = await game(h);
          await h.advance(const Duration(minutes: 9));
          await expectLater(
            h.repoFor('u2').endGame(code),
            _throws(RoomError.notAllowed),
          );
          await h.repoFor('u2').heartbeat(code);
          await h.advance(const Duration(minutes: 2));
          await h.repoFor('u2').endGame(code);
          expect((await metaOf(h, code))?.status, RoomStatus.ended);
        },
      );

      test(
        'with a banker both the owner and the banker must have been gone',
        () async {
          final h = create();
          final code = await game(h, banker: true);
          await h.advance(const Duration(minutes: 8));
          await h.repoFor('u3').heartbeat(code);
          await h.advance(const Duration(minutes: 4));
          // The owner has been gone for 12 minutes, the banker for 4.
          await expectLater(
            h.repoFor('u2').endGame(code),
            _throws(RoomError.notAllowed),
          );
          await h.advance(const Duration(minutes: 7));
          await h.repoFor('u2').endGame(code);
          expect((await metaOf(h, code))?.status, RoomStatus.ended);
        },
      );

      test(
        'checkEndGame: the owner and the banker are told they may',
        () async {
          final h = create();
          final code = await game(h, banker: true);
          for (final uid in ['owner', 'u3']) {
            final v = await h.repoFor(uid).checkEndGame(code);
            expect(v.allowed, isTrue, reason: uid);
          }
        },
      );

      test('checkEndGame: a player is told who is in the way', () async {
        final h = create();
        final code = await game(h, banker: true);
        var v = await h.repoFor('u2').checkEndGame(code);
        expect(v.allowed, isFalse);
        expect([v.ownerHere, v.bankerHere], [true, true]);
        await h.advance(const Duration(minutes: 8));
        await h.repoFor('u3').heartbeat(code);
        await h.advance(const Duration(minutes: 4));
        v = await h.repoFor('u2').checkEndGame(code);
        expect(v.allowed, isFalse);
        expect([v.ownerHere, v.bankerHere], [false, true]);
        await h.advance(const Duration(minutes: 7));
        v = await h.repoFor('u2').checkEndGame(code);
        expect(v.allowed, isTrue);
      });

      test('checkEndGame says what endGame would do', () async {
        final h = create();
        final code = await game(h);
        expect((await h.repoFor('u2').checkEndGame(code)).allowed, isFalse);
        await expectLater(
          h.repoFor('u2').endGame(code),
          _throws(RoomError.notAllowed),
        );
        await h.advance(const Duration(minutes: 11));
        expect((await h.repoFor('u2').checkEndGame(code)).allowed, isTrue);
        await h.repoFor('u2').endGame(code);
      });

      test('checkEndGame: a stranger is no member', () async {
        final h = create();
        final code = await game(h);
        await expectLater(
          h.repoFor('stranger').checkEndGame(code),
          _throws(RoomError.notAMember),
        );
      });

      test(
        'a watcher cannot, a stranger is not a member, and a game not started cannot end',
        () async {
          final h = create();
          final code = await game(h);
          await h.advance(const Duration(minutes: 11));
          await h
              .repoFor('s1')
              .joinAsSpectator(code: code, name: 'ดู', color: 3);
          await expectLater(
            h.repoFor('s1').endGame(code),
            _throws(RoomError.notAllowed),
          );
          await expectLater(
            h.repoFor('stranger').endGame(code),
            _throws(RoomError.notAMember),
          );
          final lobby = await _create(h, uid: 'owner2');
          await expectLater(
            h.repoFor('owner2').endGame(lobby.code),
            _throws(RoomError.notStarted),
          );
        },
      );
    });

    group('closing a game that ended', () {
      /// Three players, played a little, ended by the owner.
      Future<String> ended(RoomHarness h) async {
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await _join(h, meta.code, 'u3');
        await h.repoFor('owner').startGame(meta.code);
        await h.repoFor('owner').submitEntry(meta.code, EntryDraft.passGo());
        await h.repoFor('u2').submitEntry(meta.code, EntryDraft.passGo());
        await h.repoFor('owner').endGame(meta.code);
        return meta.code;
      }

      test('the owner takes it down at once: nobody can find it', () async {
        final h = create();
        final code = await ended(h);
        await h.repoFor('owner').closeRoom(code);
        for (final uid in ['owner', 'u2', 'u3', 'stranger']) {
          expect(
            await h.repoFor(uid).watchMeta(code).first,
            isNull,
            reason: uid,
          );
        }
        await expectLater(
          h.repoFor('u2').readSeats(code),
          _throws(RoomError.roomNotFound),
        );
        await expectLater(
          h.repoFor('u2').readMyMember(code),
          _throws(RoomError.roomNotFound),
        );
      });

      test('somebody who is watching the summary is told it is gone', () async {
        final h = create();
        final code = await ended(h);
        final seen = <RoomMeta?>[];
        final sub = h.repoFor('u2').watchMeta(code).listen(seen.add);
        addTearDown(sub.cancel);
        await Future<void>.delayed(Duration.zero);
        expect(seen.last?.status, RoomStatus.ended);
        await h.repoFor('owner').closeRoom(code);
        await Future<void>.delayed(Duration.zero);
        expect(seen.last, isNull);
      });

      test(
        'a player cannot before 5 minutes have gone by, and can after',
        () async {
          final h = create();
          final code = await ended(h);
          await h.advance(const Duration(minutes: 4));
          await expectLater(
            h.repoFor('u2').closeRoom(code),
            _throws(RoomError.notAllowed),
          );
          expect(
            (await h.repoFor('u2').watchMeta(code).first)?.status,
            RoomStatus.ended,
          );
          await h.advance(const Duration(minutes: 2));
          await h.repoFor('u2').closeRoom(code);
          expect(await h.repoFor('owner').watchMeta(code).first, isNull);
        },
      );

      test('the banker has no more right than another player', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.repoFor('owner').startGame(meta.code);
        await h.repoFor('u2').submitEntry(meta.code, EntryDraft.bankrupt(2000));
        await h.repoFor('owner').endGame(meta.code);
        await expectLater(
          h.repoFor('u2').closeRoom(meta.code),
          _throws(RoomError.notAllowed),
        );
      });

      test('a watcher cannot, even long after the end', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h
            .repoFor('s1')
            .joinAsSpectator(code: meta.code, name: 'ดู', color: 3);
        await h.repoFor('owner').startGame(meta.code);
        await h.repoFor('owner').endGame(meta.code);
        await h.advance(const Duration(hours: 1));
        await expectLater(
          h.repoFor('s1').closeRoom(meta.code),
          _throws(RoomError.notAllowed),
        );
      });

      test('a stranger is no member, and a lobby has not ended', () async {
        final h = create();
        final code = await ended(h);
        await h.advance(const Duration(hours: 1));
        await expectLater(
          h.repoFor('stranger').closeRoom(code),
          _throws(RoomError.notAMember),
        );
        final lobby = await _create(h, uid: 'owner2');
        await expectLater(
          h.repoFor('owner2').closeRoom(lobby.code),
          _throws(RoomError.notStarted),
        );
      });

      test(
        'a game that is still played cannot be closed, not by its owner',
        () async {
          final h = create();
          final meta = await _create(h);
          await _join(h, meta.code, 'u2');
          await h.repoFor('owner').startGame(meta.code);
          await expectLater(
            h.repoFor('owner').closeRoom(meta.code),
            _throws(RoomError.notStarted),
          );
        },
      );

      test('closing what is gone is fine', () async {
        final h = create();
        final code = await ended(h);
        await h.repoFor('owner').closeRoom(code);
        await h.repoFor('owner').closeRoom(code);
        await h.repoFor('u2').closeRoom(code);
      });
    });

    group('playing again', () {
      Future<String> ended(RoomHarness h, {String? password}) async {
        final meta = await _create(h, password: password);
        await _join(h, meta.code, 'u2', password: password);
        await h.repoFor('owner').startGame(meta.code);
        await h.repoFor('owner').endGame(meta.code);
        return meta.code;
      }

      test(
        'the owner opens a lobby with the same settings, and sits there',
        () async {
          final h = create();
          final code = await ended(h);
          final next = await h.repoFor('owner').playAgain(code);
          expect(next.code, isNot(code));
          expect(next.status, RoomStatus.lobby);
          expect(next.ownerUid, 'owner');
          expect(next.settings.startingCash, 1500);
          expect(next.settings.maxPlayers, 4);
          final me = await h.repoFor('owner').readMyMember(next.code);
          expect(me?.name, 'เจ้าของ');
          expect(me?.seat, 'p1');
        },
      );

      test('everybody in the old room is told where it is', () async {
        final h = create();
        final code = await ended(h);
        final next = await h.repoFor('owner').playAgain(code);
        for (final uid in ['owner', 'u2']) {
          final meta = await h.repoFor(uid).watchMeta(code).first;
          expect(meta?.nextCode, next.code, reason: uid);
        }
        await _join(h, next.code, 'u2');
        expect((await h.repoFor('u2').readMyMember(next.code))?.seat, 'p2');
      });

      test('asking again gives the same room', () async {
        final h = create();
        final code = await ended(h);
        final a = await h.repoFor('owner').playAgain(code);
        final b = await h.repoFor('owner').playAgain(code);
        expect(b.code, a.code);
      });

      test('when that lobby has been taken down, it opens another', () async {
        final h = create();
        final code = await ended(h);
        final a = await h.repoFor('owner').playAgain(code);
        await h.repoFor('owner').deleteRoom(a.code);
        final b = await h.repoFor('owner').playAgain(code);
        expect(b.code, isNot(a.code));
        expect((await h.repoFor('u2').watchMeta(code).first)?.nextCode, b.code);
      });

      test('when that room has started, the next try opens another', () async {
        final h = create();
        final code = await ended(h);
        final a = await h.repoFor('owner').playAgain(code);
        await _join(h, a.code, 'u2');
        await h.repoFor('owner').startGame(a.code);
        final b = await h.repoFor('owner').playAgain(code);
        expect(b.code, isNot(a.code));
        expect(b.status, RoomStatus.lobby);
      });

      test('only the owner, and only of a game that ended', () async {
        final h = create();
        final code = await ended(h);
        await expectLater(
          h.repoFor('u2').playAgain(code),
          _throws(RoomError.notOwner),
        );
        final lobby = await _create(h, uid: 'owner2');
        await expectLater(
          h.repoFor('owner2').playAgain(lobby.code),
          _throws(RoomError.notStarted),
        );
      });

      test('a room with a password needs it again, and keeps it', () async {
        final h = create();
        final code = await ended(h, password: 'secret');
        await expectLater(
          h.repoFor('owner').playAgain(code),
          _throws(RoomError.wrongPassword),
        );
        final next = await h
            .repoFor('owner')
            .playAgain(code, password: 'newone');
        expect(next.hasPassword, isTrue);
        await expectLater(
          _join(h, next.code, 'u2', password: 'secret'),
          _throws(RoomError.wrongPassword),
        );
        await _join(h, next.code, 'u2', password: 'newone');
      });

      test('taking the old room down leaves the new one alone', () async {
        final h = create();
        final code = await ended(h);
        final next = await h.repoFor('owner').playAgain(code);
        await h.repoFor('owner').closeRoom(code);
        expect(
          (await h.repoFor('u2').watchMeta(next.code).first)?.status,
          RoomStatus.lobby,
        );
      });
    });

    group('deleting a room that has not started', () {
      test('the owner takes it down: nobody can find it any more', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.repoFor('owner').deleteRoom(meta.code);
        expect(await h.repoFor('u2').watchMeta(meta.code).first, isNull);
        await expectLater(
          h.repoFor('someone').readSeats(meta.code),
          _throws(RoomError.roomNotFound),
        );
        await expectLater(
          _join(h, meta.code, 'u3'),
          _throws(RoomError.roomNotFound),
        );
      });

      test('somebody who is watching the room is told it is gone', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        final seen = <RoomMeta?>[];
        final sub = h.repoFor('u2').watchMeta(meta.code).listen(seen.add);
        addTearDown(sub.cancel);
        await Future<void>.delayed(Duration.zero);
        expect(seen.last, isNotNull);
        await h.repoFor('owner').deleteRoom(meta.code);
        await Future<void>.delayed(Duration.zero);
        expect(seen.last, isNull);
      });

      test('a room with only its owner can go too', () async {
        final h = create();
        final meta = await _create(h);
        await h.repoFor('owner').deleteRoom(meta.code);
        expect(await h.repoFor('owner').watchMeta(meta.code).first, isNull);
      });

      test('a player cannot', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await expectLater(
          h.repoFor('u2').deleteRoom(meta.code),
          _throws(RoomError.notOwner),
        );
        expect(await h.repoFor('u2').watchMeta(meta.code).first, isNotNull);
      });

      test('a stranger cannot', () async {
        final h = create();
        final meta = await _create(h);
        await expectLater(
          h.repoFor('stranger').deleteRoom(meta.code),
          _throws(RoomError.notOwner),
        );
      });

      test('nobody can once the game has started', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.repoFor('owner').startGame(meta.code);
        await expectLater(
          h.repoFor('owner').deleteRoom(meta.code),
          _throws(RoomError.alreadyStarted),
        );
        expect(await h.repoFor('u2').watchMeta(meta.code).first, isNotNull);
      });

      test('a room that is not there is not found', () async {
        final h = create();
        await expectLater(
          h.repoFor('owner').deleteRoom('ZZZZZZ'),
          _throws(RoomError.roomNotFound),
        );
      });

      test('the one who took the room over can', () async {
        final h = create();
        final meta = await _create(h);
        await _join(h, meta.code, 'u2');
        await h.repoFor('owner').heartbeat(meta.code);
        await h.advance(const Duration(minutes: 3));
        await h.repoFor('u2').claimOwnership(meta.code);
        await h.repoFor('u2').deleteRoom(meta.code);
        expect(await h.repoFor('u2').watchMeta(meta.code).first, isNull);
      });
    });

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
