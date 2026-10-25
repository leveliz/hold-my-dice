import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

const _serverTime = Object();

RoomEntry _entry(
  EntryKind kind, {
  int seq = 3,
  String seat = 'p2',
  String? from,
  String? to,
  int amount = 200,
  String? reason,
  String cid = 'abcdefghij0123456789',
}) => RoomEntry(
  seq: seq,
  kind: kind,
  seat: seat,
  by: 'uid-of-p2',
  from: from,
  to: to,
  amount: amount,
  reason: reason,
  cid: cid,
);

Map<String, Object?> _stored(RoomEntry e) => {
  ...e.toMap(DateTime.utc(2026, 10, 26, 12)),
};

void main() {
  group('RoomEntry.toMap', () {
    test('writes exactly the keys of the stored layout, for every kind', () {
      const keys = {
        'v',
        'seq',
        'by',
        'seat',
        'at',
        'kind',
        'from',
        'to',
        'amount',
        'reason',
        'cid',
        'voided',
      };
      for (final e in [
        _entry(EntryKind.receive, from: 'bank', to: 'p2', reason: 'ค่าเช่า'),
        _entry(EntryKind.passGo, from: 'bank', to: 'p2', reason: goReason),
        _entry(EntryKind.payBank, from: 'p2', to: 'bank'),
      ]) {
        expect(e.toMap(_serverTime).keys.toSet(), keys, reason: '${e.kind}');
      }
    });

    test('holds the values of the entry and the given time', () {
      final map = _entry(
        EntryKind.receive,
        from: 'bank',
        to: 'p2',
        reason: 'ค่าเช่า',
      ).toMap(_serverTime);
      expect(map['v'], 1);
      expect(map['seq'], 3);
      expect(map['by'], 'uid-of-p2');
      expect(map['seat'], 'p2');
      expect(map['at'], same(_serverTime));
      expect(map['kind'], 'receive');
      expect(map['from'], 'bank');
      expect(map['to'], 'p2');
      expect(map['amount'], 200);
      expect(map['reason'], 'ค่าเช่า');
      expect(map['cid'], 'abcdefghij0123456789');
      expect(map['voided'], false);
    });

    test('a missing reason is stored as null, not left out', () {
      final map = _entry(
        EntryKind.payBank,
        from: 'p2',
        to: 'bank',
      ).toMap(_serverTime);
      expect(map.containsKey('reason'), isTrue);
      expect(map['reason'], isNull);
    });

    test('the reason of a GO is the words the rules expect', () {
      expect(goReason, 'ผ่านจุดเริ่ม');
    });

    test('refuses an entry that does not say who pressed it', () {
      expect(
        () => const RoomEntry(
          seq: 0,
          kind: EntryKind.payBank,
          seat: 'p1',
          from: 'p1',
          to: 'bank',
          amount: 1,
          cid: 'c',
        ).toMap(_serverTime),
        throwsStateError,
      );
    });

    test('refuses an entry that has no press code', () {
      expect(
        () => const RoomEntry(
          seq: 0,
          kind: EntryKind.payBank,
          seat: 'p1',
          by: 'u',
          from: 'p1',
          to: 'bank',
          amount: 1,
        ).toMap(_serverTime),
        throwsStateError,
      );
    });

    test('refuses what the first slice does not store', () {
      expect(
        () => const RoomEntry(
          seq: 0,
          kind: EntryKind.receive,
          seat: 'p1',
          by: 'u',
          from: 'bank',
          to: 'p1',
          amount: 1,
          cid: 'c',
          group: 'g',
        ).toMap(_serverTime),
        throwsStateError,
      );
      expect(
        () => const RoomEntry(
          seq: 0,
          kind: EntryKind.bankrupt,
          seat: 'p1',
          by: 'u',
          cid: 'c',
          bankrupt: BankruptInfo(seat: 'p1', cash: 0, owed: 10),
        ).toMap(_serverTime),
        throwsStateError,
      );
    });
  });

  group('RoomEntry.fromMap', () {
    test('reads back what toMap wrote, for the three kinds', () {
      for (final e in [
        _entry(EntryKind.receive, from: 'bank', to: 'p2', reason: 'ค่าเช่า'),
        _entry(EntryKind.passGo, from: 'bank', to: 'p2', reason: goReason),
        _entry(EntryKind.payBank, from: 'p2', to: 'bank'),
      ]) {
        final back = RoomEntry.fromMap(_stored(e));
        expect(back.seq, e.seq);
        expect(back.kind, e.kind);
        expect(back.seat, e.seat);
        expect(back.by, e.by);
        expect(back.from, e.from);
        expect(back.to, e.to);
        expect(back.amount, e.amount);
        expect(back.reason, e.reason);
        expect(back.cid, e.cid);
        expect(back.voided, isFalse);
        expect(back.at, DateTime.utc(2026, 10, 26, 12));
      }
    });

    test('keeps Thai and emoji in a reason as they are', () {
      const reason = 'ค่าเช่าที่ดิน 😀 สุขุมวิท';
      final back = RoomEntry.fromMap(
        _stored(
          _entry(EntryKind.receive, from: 'bank', to: 'p2', reason: reason),
        ),
      );
      expect(back.reason, reason);
    });

    test('accepts a time that is not known yet (a write still on its way)', () {
      final map = _stored(_entry(EntryKind.payBank, from: 'p2', to: 'bank'))
        ..['at'] = null;
      expect(RoomEntry.fromMap(map).at, isNull);
    });

    test('a voided entry reads as voided', () {
      final map = _stored(_entry(EntryKind.payBank, from: 'p2', to: 'bank'))
        ..['voided'] = true;
      expect(RoomEntry.fromMap(map).voided, isTrue);
    });

    void refuses(String what, void Function(Map<String, Object?> m) spoil) {
      test('refuses an entry with $what, with a readable message', () {
        final map = _stored(_entry(EntryKind.payBank, from: 'p2', to: 'bank'));
        spoil(map);
        expect(() => RoomEntry.fromMap(map), throwsA(isA<FormatException>()));
      });
    }

    refuses('a missing seq', (m) => m.remove('seq'));
    refuses('a seq that is not a whole number', (m) => m['seq'] = 3.5);
    refuses('a negative seq', (m) => m['seq'] = -1);
    refuses('an unknown kind', (m) => m['kind'] = 'gift');
    refuses('a kind that is not text', (m) => m['kind'] = 7);
    refuses('an amount with decimals', (m) => m['amount'] = 10.5);
    refuses('an amount that is text', (m) => m['amount'] = '10');
    refuses('no seat', (m) => m.remove('seat'));
    refuses('a seat that is not text', (m) => m['seat'] = 2);
    refuses('a reason that is not text', (m) => m['reason'] = 5);
    refuses('a time that is neither a time nor null', (m) => m['at'] = 'now');
    refuses('a voided flag that is not true or false', (m) => m['voided'] = 1);

    test('the message says which field is wrong', () {
      final map = _stored(_entry(EntryKind.payBank, from: 'p2', to: 'bank'))
        ..['amount'] = 10.5;
      expect(
        () => RoomEntry.fromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('amount'),
          ),
        ),
      );
    });
  });

  group('RoomState', () {
    const settings = RoomSettings(startingCash: 1500, goAmount: 200);
    const limited = RoomSettings(
      startingCash: 1500,
      goAmount: 200,
      bankLimit: 5000,
    );

    Map<String, Object?> stored({Map<String, Object?>? balances}) => {
      'v': 1,
      'seq': 4,
      'seats': ['p1', 'p2'],
      'balances': balances ?? {'p1': 1300, 'p2': 1700},
      'bankrupt': <Object?>[],
      'bankerSeat': null,
      'status': 'playing',
    };

    test('reads a stored state', () {
      final s = RoomState.fromMap(stored());
      expect(s.seq, 4);
      expect(s.seats, ['p1', 'p2']);
      expect(s.balances, {'p1': 1300, 'p2': 1700});
      expect(s.bankrupt, isEmpty);
      expect(s.bankerSeat, isNull);
      expect(s.status, RoomStatus.playing);
    });

    test('turns into the ledger with the starting cash of the room', () {
      final l = RoomState.fromMap(stored()).toLedger(settings);
      expect(l.balances, {'p1': 1300, 'p2': 1700});
      expect(l.startingCash, 1500);
      expect(l.bankHasLimit, isFalse);
      expect(l.isActive('p1'), isTrue);
    });

    test('a bank in the balances makes a ledger with a bank limit', () {
      final l = RoomState.fromMap(
        stored(balances: {'p1': 1300, 'p2': 1700, 'bank': 4000}),
      ).toLedger(limited);
      expect(l.bankHasLimit, isTrue);
      expect(l.balances['bank'], 4000);
    });

    test('the ledger of a state agrees with applying entries to it', () {
      final l = RoomState.fromMap(stored()).toLedger(settings);
      final result = Ledger.apply(
        l,
        const RoomEntry(
          seq: 4,
          kind: EntryKind.payBank,
          seat: 'p1',
          from: 'p1',
          to: 'bank',
          amount: 300,
        ),
      );
      expect((result as Applied).state.balances['p1'], 1000);
    });

    void refuses(String what, void Function(Map<String, Object?> m) spoil) {
      test('refuses a state with $what instead of crashing', () {
        final map = stored();
        spoil(map);
        expect(() => RoomState.fromMap(map), throwsA(isA<FormatException>()));
      });
    }

    refuses('a balance with decimals', (m) => m['balances'] = {'p1': 1500.5});
    refuses('a balance that is text', (m) => m['balances'] = {'p1': '1500'});
    refuses('balances that are not a map', (m) => m['balances'] = [1, 2]);
    refuses('seats that are not a list', (m) => m['seats'] = 'p1');
    refuses('a seat that is not text', (m) => m['seats'] = ['p1', 2]);
    refuses('a seq with decimals', (m) => m['seq'] = 1.5);
    refuses('an unknown status', (m) => m['status'] = 'paused');
    refuses('a missing field', (m) => m.remove('bankrupt'));
  });
}
