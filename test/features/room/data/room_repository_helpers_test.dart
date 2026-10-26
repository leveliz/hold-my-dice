import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';

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
}
