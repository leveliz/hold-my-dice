import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';

void main() {
  group('entryIsMine', () {
    test('the entry with the same code from the same person is the press', () {
      expect(entryIsMine({'cid': 'abc', 'by': 'u1'}, 'abc', 'u1'), isTrue);
    });

    test('another code is another press', () {
      expect(entryIsMine({'cid': 'xyz', 'by': 'u1'}, 'abc', 'u1'), isFalse);
    });

    test('the same code from another person is not this press', () {
      expect(entryIsMine({'cid': 'abc', 'by': 'u2'}, 'abc', 'u1'), isFalse);
    });

    test('the seat does not matter: a banker presses for other seats', () {
      expect(
        entryIsMine({'cid': 'abc', 'by': 'u1', 'seat': 'p3'}, 'abc', 'u1'),
        isTrue,
      );
    });

    test('an empty place or an entry without a code is nobody\'s', () {
      expect(entryIsMine(null, 'abc', 'u1'), isFalse);
      expect(entryIsMine({'by': 'u1'}, 'abc', 'u1'), isFalse);
    });
  });
}
