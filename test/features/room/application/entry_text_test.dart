import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/entry_text.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

String _name(String seat) => {'p1': 'ต้น', 'p2': 'แพร'}[seat] ?? seat;

RoomEntry _entry(
  EntryKind kind, {
  String seat = 'p1',
  int? amount = 300,
  String? reason,
  bool voided = false,
}) => RoomEntry(
  seq: 0,
  kind: kind,
  seat: seat,
  by: 'u',
  at: DateTime.utc(2026, 10, 26),
  cid: 'c',
  from: kind == EntryKind.payBank ? seat : 'bank',
  to: kind == EntryKind.payBank ? 'bank' : seat,
  amount: amount,
  reason: reason,
  voided: voided,
);

void main() {
  group('describeRoomEntry', () {
    test('a receive names the person, the amount and the reason', () {
      final label = describeRoomEntry(
        _entry(EntryKind.receive, reason: 'ค่าเช่า'),
        _name,
      );
      expect(label.title, 'รับจากธนาคาร ต้น +300');
      expect(label.subtitle, 'ค่าเช่า');
    });

    test('a pass over GO shows the amount and its own reason', () {
      final label = describeRoomEntry(
        _entry(EntryKind.passGo, seat: 'p2', amount: 200, reason: goReason),
        _name,
      );
      expect(label.title, 'ผ่านจุดเริ่ม แพร +200');
      expect(label.subtitle, isNull);
    });

    test('a payment shows a minus and the reason when there is one', () {
      final label = describeRoomEntry(
        _entry(EntryKind.payBank, seat: 'p2', amount: 1500, reason: 'ภาษี'),
        _name,
      );
      expect(label.title, 'จ่ายธนาคาร แพร -1,500');
      expect(label.subtitle, 'ภาษี');
      expect(
        describeRoomEntry(_entry(EntryKind.payBank), _name).subtitle,
        isNull,
      );
    });

    test('a payment with a mortgage says how much was mortgaged', () {
      final label = describeRoomEntry(
        RoomEntry(
          seq: 0,
          kind: EntryKind.payBank,
          seat: 'p2',
          from: 'p2',
          to: 'bank',
          amount: 700,
          mortgage: 1360,
          reason: 'ภาษี',
          voided: true,
        ),
        _name,
      );
      expect(label.title, 'จ่ายธนาคาร แพร -700');
      expect(label.subtitle, 'ภาษี · จำนอง 1,360 · ยกเลิกแล้ว');
    });

    test('a bankruptcy names who went out and who is owed', () {
      RoomEntry out(String? creditor) => RoomEntry(
        seq: 0,
        kind: EntryKind.bankrupt,
        seat: 'p2',
        bankrupt: BankruptInfo(
          seat: 'p2',
          creditorSeat: creditor,
          cash: 400,
          owed: 1700,
        ),
      );
      final toFriend = describeRoomEntry(out('p1'), _name);
      expect(toFriend.title, 'ล้มละลาย แพร');
      expect(toFriend.subtitle, 'หนี้ 1,700 ให้ ต้น');
      expect(
        describeRoomEntry(out(null), _name).subtitle,
        'หนี้ 1,700 ให้ธนาคาร',
      );
    });

    test('a transfer names both people and the amount', () {
      final label = describeRoomEntry(
        RoomEntry(
          seq: 0,
          kind: EntryKind.transfer,
          seat: 'p1',
          from: 'p1',
          to: 'p2',
          amount: 1200,
        ),
        _name,
      );
      expect(label.title, 'โอน ต้น → แพร 1,200');
      expect(label.subtitle, isNull);
    });

    test('a payment of a request says so, and an undone one says that too', () {
      final label = describeRoomEntry(
        RoomEntry(
          seq: 0,
          kind: EntryKind.transfer,
          seat: 'p2',
          from: 'p2',
          to: 'p1',
          amount: 300,
          reason: 'ตามคำขอเรียกเก็บ',
          voided: true,
        ),
        _name,
      );
      expect(label.title, 'โอน แพร → ต้น 300');
      expect(label.subtitle, 'ตามคำขอเรียกเก็บ · ยกเลิกแล้ว');
    });

    test('big amounts have thousands separators', () {
      expect(
        describeRoomEntry(
          _entry(EntryKind.receive, amount: 999999999, reason: 'x'),
          _name,
        ).title,
        'รับจากธนาคาร ต้น +999,999,999',
      );
    });

    test('an undone entry says so, next to its reason', () {
      final label = describeRoomEntry(
        _entry(EntryKind.receive, reason: 'ค่าเช่า', voided: true),
        _name,
      );
      expect(label.subtitle, 'ค่าเช่า · ยกเลิกแล้ว');
      expect(
        describeRoomEntry(
          _entry(EntryKind.passGo, reason: goReason, voided: true),
          _name,
        ).subtitle,
        'ยกเลิกแล้ว',
      );
    });

    test('a seat the list does not know is shown by its id', () {
      expect(
        describeRoomEntry(
          _entry(EntryKind.receive, seat: 'p7', reason: 'x'),
          _name,
        ).title,
        'รับจากธนาคาร p7 +300',
      );
    });

    test('a kind of entry this app does not know yet does not crash', () {
      final label = describeRoomEntry(_entry(EntryKind.mortgage), _name);
      expect(label.title, 'รายการที่แอพนี้ยังไม่รู้จัก');
    });
  });
}
