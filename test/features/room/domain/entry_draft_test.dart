import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

void main() {
  group('EntryDraft', () {
    test('a receive carries the amount and the reason', () {
      final d = EntryDraft.receive(300, 'ค่าเช่า');
      expect(d.kind, EntryKind.receive);
      expect(d.amount, 300);
      expect(d.reason, 'ค่าเช่า');
    });

    test('a pass over GO has no amount of its own: the room decides it', () {
      final d = EntryDraft.passGo();
      expect(d.kind, EntryKind.passGo);
      expect(d.amount, isNull);
      expect(d.reason, isNull);
    });

    test('a payment carries the amount and may carry a reason', () {
      final d = EntryDraft.payBank(150);
      expect(d.kind, EntryKind.payBank);
      expect(d.amount, 150);
      expect(d.reason, isNull);
      expect(EntryDraft.payBank(150, reason: 'ภาษี').reason, 'ภาษี');
    });

    test('a transfer names who gets the money and carries no reason', () {
      final d = EntryDraft.transfer('p2', 200);
      expect(d.kind, EntryKind.transfer);
      expect(d.toSeat, 'p2');
      expect(d.amount, 200);
      expect(d.reason, isNull);
      expect(EntryDraft.transfer('p2', 200, reason: 'x').reason, 'x');
    });

    test('the other drafts have no one to give the money to', () {
      expect(EntryDraft.receive(1, 'a').toSeat, isNull);
      expect(EntryDraft.passGo().toSeat, isNull);
      expect(EntryDraft.payBank(1).toSeat, isNull);
    });

    test('every draft has a press code of 20 letters and digits', () {
      final d = EntryDraft.passGo();
      expect(d.cid.length, 20);
      expect(d.cid, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
    });

    test('two presses never share a code', () {
      final codes = {for (var i = 0; i < 200; i++) EntryDraft.passGo().cid};
      expect(codes.length, 200);
    });

    test(
      'a code can be given, so a press can be told apart from its repeat',
      () {
        expect(
          EntryDraft.passGo(cid: 'fixedfixedfixedfixed').cid,
          'fixedfixedfixedfixed',
        );
        expect(EntryDraft.receive(1, 'x', cid: 'abc').cid, 'abc');
        expect(EntryDraft.payBank(1, cid: 'abc').cid, 'abc');
      },
    );

    test('the code comes from the random source it is given', () {
      expect(
        EntryDraft.passGo(random: Random(1)).cid,
        EntryDraft.passGo(random: Random(1)).cid,
      );
      expect(
        EntryDraft.passGo(random: Random(1)).cid,
        isNot(EntryDraft.passGo(random: Random(2)).cid),
      );
    });
  });
}
