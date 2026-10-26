import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

Map<String, Object?> _doc([Map<String, Object?> over = const {}]) => {
  'fromSeat': 'p1',
  'toSeat': 'p2',
  'amount': 300,
  'status': 'open',
  'createdAt': DateTime.utc(2026, 10, 26, 12),
  'paidSeq': null,
  ...over,
};

void main() {
  test('the id of a request is the asker and the payer', () {
    expect(RoomRequest.idFor(toSeat: 'p2', fromSeat: 'p1'), 'p2_p1');
  });

  test('a stored request is read with every field', () {
    final r = RoomRequest.fromMap('p2_p1', _doc());
    expect(r.id, 'p2_p1');
    expect(r.fromSeat, 'p1');
    expect(r.toSeat, 'p2');
    expect(r.amount, 300);
    expect(r.status, RequestStatus.open);
    expect(r.isOpen, isTrue);
    expect(r.createdAt, DateTime.utc(2026, 10, 26, 12));
    expect(r.paidSeq, isNull);
  });

  test('a paid request keeps the number of the entry that paid it', () {
    final r = RoomRequest.fromMap(
      'p2_p1',
      _doc({'status': 'paid', 'paidSeq': 7}),
    );
    expect(r.status, RequestStatus.paid);
    expect(r.isOpen, isFalse);
    expect(r.paidSeq, 7);
  });

  test('the time of a write that is still on its way is not there yet', () {
    final r = RoomRequest.fromMap('p2_p1', _doc({'createdAt': null}));
    expect(r.createdAt, isNull);
  });

  test('a document that is wrong is a format error, not a crash later', () {
    for (final bad in [
      {'status': 'gone'},
      {'status': 3},
      {'amount': 0},
      {'amount': '300'},
      {'fromSeat': null},
      {'toSeat': 4},
    ]) {
      expect(
        () => RoomRequest.fromMap('p2_p1', _doc(bad)),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('a request is written with the same fields it is read from', () {
    final r = RoomRequest.fromMap('p2_p1', _doc());
    final map = r.toMap('server-time');
    expect(map.keys.toSet(), {
      'fromSeat',
      'toSeat',
      'amount',
      'status',
      'createdAt',
      'paidSeq',
    });
    expect(map['createdAt'], 'server-time');
    expect(map['status'], 'open');
    expect(map['paidSeq'], isNull);
  });

  test('a request lives for two minutes', () {
    expect(requestLifetime, const Duration(minutes: 2));
  });
}
