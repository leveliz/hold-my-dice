import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/incoming_events.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

final _t0 = DateTime.utc(2026, 10, 26, 12);

String _name(String seat) => switch (seat) {
  'p1' => 'ต้น',
  'p2' => 'แพร',
  _ => seat,
};

RoomEntry _transfer(
  int seq, {
  String from = 'p2',
  String to = 'p1',
  int amount = 200,
  String? reason,
  bool voided = false,
  Duration age = Duration.zero,
}) => RoomEntry(
  seq: seq,
  kind: EntryKind.transfer,
  seat: from,
  by: 'u-$from',
  at: _t0.add(Duration(seconds: seq * 5)).subtract(age),
  cid: 'cid$seq',
  from: from,
  to: to,
  amount: amount,
  reason: reason,
  voided: voided,
);

RoomEntry _goOf(int seq, String seat) => RoomEntry(
  seq: seq,
  kind: EntryKind.passGo,
  seat: seat,
  by: 'u-$seat',
  at: _t0.add(Duration(seconds: seq * 5)),
  cid: 'cid$seq',
  from: 'bank',
  to: seat,
  amount: 200,
  reason: goReason,
);

RoomEntry _bankrupt(int seq, String seat, {String? creditor, int owed = 700}) =>
    RoomEntry(
      seq: seq,
      kind: EntryKind.bankrupt,
      seat: seat,
      by: 'u-$seat',
      at: _t0.add(Duration(seconds: seq * 5)),
      cid: 'cid$seq',
      bankrupt: BankruptInfo(
        seat: seat,
        creditorSeat: creditor,
        cash: 100,
        owed: owed,
      ),
    );

void main() {
  IncomingTracker tracker() => IncomingTracker(mySeat: 'p1');

  test(
    'a press of the banker that was taken back before it was seen is not announced',
    () {
      final t = tracker();
      t.update(const [], _name);
      final e = RoomEntry(
        seq: 0,
        kind: EntryKind.receive,
        seat: 'p1',
        by: 'u-p3',
        at: _t0,
        cid: 'cid0',
        from: 'bank',
        to: 'p1',
        amount: 300,
        voided: true,
      );
      expect(t.update([e], _name, pressedByOther: (_) => 'มด'), isEmpty);
    },
  );

  group('a player going out', () {
    test('is announced once, to everybody', () {
      final t = tracker();
      t.update(const [], _name);
      final entries = [_bankrupt(0, 'p2', creditor: 'p3')];
      expect(t.update(entries, _name), ['แพร ล้มละลาย']);
      expect(t.update(entries, _name), isEmpty);
    });

    test('says so to the one who is paid', () {
      final t = tracker();
      t.update(const [], _name);
      expect(t.update([_bankrupt(0, 'p2', creditor: 'p1', owed: 700)], _name), [
        'แพร ล้มละลาย คุณได้รับ +700',
      ]);
    });

    test('is not announced when it was already in the history', () {
      final t = tracker();
      expect(t.update([_bankrupt(0, 'p2')], _name), isEmpty);
    });

    test('is not told to the one who went out', () {
      final t = tracker();
      t.update(const [], _name);
      expect(t.update([_bankrupt(0, 'p1')], _name), isEmpty);
    });
  });

  test(
    'what is already in the history when the screen opens is not announced',
    () {
      final t = tracker();
      expect(t.update([_transfer(0), _transfer(1)], _name), isEmpty);
    },
  );

  test('a transfer to me that comes after that is announced once', () {
    final t = tracker();
    t.update([_transfer(0)], _name);
    final entries = [_transfer(0), _transfer(1, amount: 500)];
    expect(t.update(entries, _name), ['แพร โอนให้คุณ +500']);
    expect(t.update(entries, _name), isEmpty, reason: 'the same list again');
    expect(t.update([...entries, _goOf(2, 'p2')], _name), isEmpty);
  });

  test('a transfer to somebody else, or from me, is not for me', () {
    final t = tracker();
    t.update(const [], _name);
    expect(
      t.update([
        _transfer(0, from: 'p2', to: 'p3'),
        _transfer(1, from: 'p1', to: 'p2'),
      ], _name),
      isEmpty,
    );
  });

  test('a payment of a request has its own words', () {
    final t = tracker();
    t.update(const [], _name);
    expect(
      t.update([_transfer(0, amount: 300, reason: 'ตามคำขอเรียกเก็บ')], _name),
      ['แพร จ่ายตามที่เรียกเก็บ +300'],
    );
  });

  test('a transfer that is taken back after it was announced says so', () {
    final t = tracker();
    t.update(const [], _name);
    t.update([_transfer(0, amount: 700)], _name);
    expect(t.update([_transfer(0, amount: 700, voided: true)], _name), [
      'แพร ยกเลิกการโอน 700',
    ]);
    expect(
      t.update([_transfer(0, amount: 700, voided: true)], _name),
      isEmpty,
      reason: 'only once',
    );
  });

  test(
    'a transfer taken back before this device ever saw it is not announced',
    () {
      final t = tracker();
      t.update(const [], _name);
      expect(t.update([_transfer(0, voided: true)], _name), isEmpty);
    },
  );

  test('old transfers that arrive late with the first fresh snapshot are not '
      'announced, new ones are', () {
    // The first snapshot came from a cache with nothing in it; the next from
    // the server holds a game's worth of history and one fresh transfer.
    final t = tracker();
    t.update(const [], _name);
    final history = [
      for (var i = 0; i < 5; i++) _transfer(i, age: const Duration(hours: 1)),
      _transfer(5, amount: 50),
    ];
    expect(t.update(history, _name), ['แพร โอนให้คุณ +50']);
  });

  test('several transfers at once give several lines', () {
    final t = tracker();
    t.update(const [], _name);
    expect(
      t.update([_transfer(0, amount: 10), _transfer(1, amount: 20)], _name),
      ['แพร โอนให้คุณ +10', 'แพร โอนให้คุณ +20'],
    );
  });

  test(
    'an entry that is still on its way has no time and is not held back',
    () {
      final t = tracker();
      t.update(const [], _name);
      final pending = RoomEntry(
        seq: 0,
        kind: EntryKind.transfer,
        seat: 'p2',
        by: 'u-p2',
        cid: 'cid0',
        from: 'p2',
        to: 'p1',
        amount: 5,
      );
      expect(t.update([pending], _name), ['แพร โอนให้คุณ +5']);
    },
  );
}
