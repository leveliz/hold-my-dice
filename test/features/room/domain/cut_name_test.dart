import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

void main() {
  group('cutName', () {
    test('keeps a name of 20 UTF-16 units as it is', () {
      expect(cutName('x' * 20), 'x' * 20);
      expect(cutName('ก' * 20), 'ก' * 20);
    });

    test('cuts a long name to 20 UTF-16 units', () {
      expect(cutName('x' * 25), 'x' * 20);
    });

    test('counts an emoji as two units, as the Firestore rules do', () {
      expect(cutName('😀' * 20), '😀' * 10);
    });

    test('never splits an emoji in half', () {
      expect(cutName('${'x' * 19}😀'), 'x' * 19);
    });

    test('leaves an empty name empty', () {
      expect(cutName(''), '');
    });
  });

  group('cutText and cutReason', () {
    test('cutText cuts to the given length in UTF-16 units', () {
      expect(cutText('abcdef', 4), 'abcd');
      expect(cutText('abc', 4), 'abc');
      expect(cutText('😀😀😀', 4), '😀😀');
      expect(cutText('😀😀😀', 5), '😀😀');
      expect(cutText('x😀', 2), 'x');
    });

    test('a reason holds up to 60 units and is never cut inside an emoji', () {
      expect(maxReasonLength, 60);
      expect(cutReason('ก' * 70), 'ก' * 60);
      expect(cutReason('${'x' * 59}😀'), 'x' * 59);
      expect(cutReason('${'x' * 58}😀'), '${'x' * 58}😀');
      expect(cutReason('😀' * 40), '😀' * 30);
    });

    test('cutName still cuts at 20', () {
      expect(cutName('x' * 25), 'x' * 20);
    });
  });
}
