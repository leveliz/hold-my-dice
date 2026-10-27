import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

Matcher _throws(RoomError error) =>
    throwsA(isA<RoomException>().having((e) => e.error, 'error', error));

void main() {
  group('storedReason', () {
    test('a GO is stored with its own words, whatever else', () {
      expect(storedReason(EntryDraft.passGo()), 'ผ่านจุดเริ่ม');
    });

    test('a reason is trimmed', () {
      expect(storedReason(EntryDraft.receive(1, '  ค่าเช่า  ')), 'ค่าเช่า');
    });

    test('spaces in front do not use up the room of the limit', () {
      final text = '${' ' * 10}${'x' * 60}';
      expect(storedReason(EntryDraft.receive(1, text)), 'x' * 60);
    });

    test('a cut that leaves a space at the end drops the space', () {
      final text = '${'x' * 59} tail';
      expect(storedReason(EntryDraft.receive(1, text)), 'x' * 59);
    });

    test('an emoji across the limit is dropped whole', () {
      expect(storedReason(EntryDraft.receive(1, '${'x' * 59}😀')), 'x' * 59);
    });

    test('a receive without anything to say is refused', () {
      for (final r in [null, '', '   ', '	']) {
        expect(
          () => storedReason(EntryDraft.receive(1, r)),
          _throws(RoomError.reasonRequired),
        );
      }
    });

    test(
      'a receive pressed by the banker for another seat needs no reason',
      () {
        expect(
          storedReason(EntryDraft.receive(1, null).onBehalfOf('p2')),
          isNull,
        );
        expect(
          storedReason(EntryDraft.receive(1, ' ค่าเช่า ').onBehalfOf('p2')),
          'ค่าเช่า',
        );
      },
    );

    test('a payment without anything to say has no reason', () {
      expect(storedReason(EntryDraft.payBank(1)), isNull);
      expect(storedReason(EntryDraft.payBank(1, reason: '   ')), isNull);
      expect(storedReason(EntryDraft.payBank(1, reason: ' ภาษี ')), 'ภาษี');
    });
  });

  group('roomErrorOf', () {
    test('each refusal of the money rules has its own name for the person', () {
      expect(
        roomErrorOf(LedgerRejection.insufficient),
        RoomError.insufficientFunds,
      );
      expect(roomErrorOf(LedgerRejection.bankLimit), RoomError.bankEmpty);
      expect(roomErrorOf(LedgerRejection.notActive), RoomError.notAPlayer);
      expect(
        roomErrorOf(LedgerRejection.invalidAmount),
        RoomError.invalidAmount,
      );
    });

    test('a mortgage or a bankruptcy that does not hold has its own names', () {
      expect(
        roomErrorOf(LedgerRejection.invalidMortgage),
        RoomError.invalidMortgage,
      );
      expect(
        roomErrorOf(LedgerRejection.invalidBankrupt),
        RoomError.invalidBankrupt,
      );
    });

    test('money that cannot go to that person, and an undo that cannot be', () {
      expect(
        roomErrorOf(LedgerRejection.invalidParties),
        RoomError.invalidParties,
      );
      expect(roomErrorOf(LedgerRejection.notUndoable), RoomError.tooLate);
    });
  });

  group('requestRefusal: why a payment of a request was refused', () {
    final now = DateTime.utc(2026, 10, 27, 12);
    RoomRequest request({
      RequestStatus status = RequestStatus.open,
      Duration age = const Duration(seconds: 30),
      bool noTime = false,
    }) => RoomRequest(
      id: 'p2_p1',
      fromSeat: 'p1',
      toSeat: 'p2',
      amount: 300,
      status: status,
      createdAt: noTime ? null : now.subtract(age),
    );

    test('a request that is not there is gone, busy game or not', () {
      for (final moved in [true, false]) {
        expect(
          requestRefusal(null, stateMoved: moved, now: now),
          RoomError.requestGone,
        );
      }
    });

    test('a request that was taken back is gone', () {
      for (final moved in [true, false]) {
        expect(
          requestRefusal(
            request(status: RequestStatus.cancelled),
            stateMoved: moved,
            now: now,
          ),
          RoomError.requestGone,
        );
      }
    });

    test('a request that was paid is already paid', () {
      for (final moved in [true, false]) {
        expect(
          requestRefusal(
            request(status: RequestStatus.paid),
            stateMoved: moved,
            now: now,
          ),
          RoomError.alreadyPaid,
        );
      }
    });

    test('a request that ran out is gone, also when the game moved on', () {
      for (final moved in [true, false]) {
        expect(
          requestRefusal(
            request(age: requestLifetime),
            stateMoved: moved,
            now: now,
          ),
          RoomError.requestGone,
          reason: 'moved: $moved',
        );
        expect(
          requestRefusal(
            request(age: const Duration(minutes: 5)),
            stateMoved: moved,
            now: now,
          ),
          RoomError.requestGone,
        );
      }
    });

    test('one second before it runs out it still stands', () {
      final almost = request(age: requestLifetime - const Duration(seconds: 1));
      expect(requestRefusal(almost, stateMoved: true, now: now), isNull);
    });

    test('an open request in a game that moved on is a race to try again', () {
      expect(requestRefusal(request(), stateMoved: true, now: now), isNull);
    });

    test('an open request in a game that did not move is the reason', () {
      expect(
        requestRefusal(request(), stateMoved: false, now: now),
        RoomError.requestGone,
      );
    });

    test('a request the server has not stamped yet counts as fresh', () {
      expect(
        requestRefusal(request(noTime: true), stateMoved: true, now: now),
        isNull,
      );
    });
  });
}
