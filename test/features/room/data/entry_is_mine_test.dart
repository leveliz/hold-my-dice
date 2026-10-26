import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';

void main() {
  group('entryIsMine', () {
    test('the entry with the same code from the same seat is the press', () {
      expect(entryIsMine({'cid': 'abc', 'seat': 'p1'}, 'abc', 'p1'), isTrue);
    });

    test('another code is another press', () {
      expect(entryIsMine({'cid': 'xyz', 'seat': 'p1'}, 'abc', 'p1'), isFalse);
    });

    test('the same code from another seat is not this press', () {
      expect(entryIsMine({'cid': 'abc', 'seat': 'p2'}, 'abc', 'p1'), isFalse);
    });

    test('an empty place or an entry without a code is nobody\'s', () {
      expect(entryIsMine(null, 'abc', 'p1'), isFalse);
      expect(entryIsMine({'seat': 'p1'}, 'abc', 'p1'), isFalse);
    });
  });
}
