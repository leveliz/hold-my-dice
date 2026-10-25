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
}
