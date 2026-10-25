import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/room_code.dart';

void main() {
  group('generateRoomCode', () {
    test('is 6 characters from the allowed alphabet, never O 0 I 1 L', () {
      final random = Random(7);
      for (var i = 0; i < 10000; i++) {
        final code = generateRoomCode(random);
        expect(code.length, 6);
        for (final ch in code.split('')) {
          expect(roomCodeAlphabet.contains(ch), isTrue, reason: code);
          expect('O0I1L'.contains(ch), isFalse, reason: code);
        }
      }
    });

    test('the alphabet is A to Z without I L O plus 2 to 9', () {
      expect(roomCodeAlphabet.length, 23 + 8);
      expect(
        roomCodeAlphabet.split('').toSet().length,
        roomCodeAlphabet.length,
      );
      for (final ch in 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'.split('')) {
        expect(roomCodeAlphabet.contains(ch), isTrue, reason: ch);
      }
    });

    test('different random numbers give different codes', () {
      final codes = {for (var i = 0; i < 200; i++) generateRoomCode(Random(i))};
      expect(codes.length, greaterThan(190));
    });
  });

  group('normalizeRoomCode', () {
    test('upper-cases, drops spaces and dashes', () {
      expect(normalizeRoomCode(' abc-d23 '), 'ABCD23');
      expect(normalizeRoomCode('abcd23'), 'ABCD23');
      expect(normalizeRoomCode('ABC D23'), 'ABCD23');
    });

    test('a code with a forbidden character is null', () {
      for (final bad in ['ABCD20', 'ABCD2O', 'ABCD2I', 'ABCD21', 'ABCD2L']) {
        expect(normalizeRoomCode(bad), isNull, reason: bad);
      }
    });

    test('the wrong length is null', () {
      for (final bad in ['', 'ABCD2', 'ABCD234', '    ', '-----']) {
        expect(normalizeRoomCode(bad), isNull, reason: bad);
      }
    });

    test('anything that is not a letter or digit is null', () {
      for (final bad in ['ABC_23', 'ABCเD2', 'ABCD2!']) {
        expect(normalizeRoomCode(bad), isNull, reason: bad);
      }
    });

    test('a code made by generateRoomCode survives normalising', () {
      final random = Random(3);
      for (var i = 0; i < 500; i++) {
        final code = generateRoomCode(random);
        expect(normalizeRoomCode(code.toLowerCase()), code);
      }
    });
  });

  group('hashRoomPassword', () {
    test('is the SHA-256 hex of the password followed by the code', () {
      expect(
        hashRoomPassword('secret', 'ABCD23'),
        '7eb33aa46840621431c5f3a2d44375aa860368f2de29cc12f0defec15c42277e',
      );
    });

    test('the same password gives another hash in another room', () {
      expect(
        hashRoomPassword('secret', 'ABCD24'),
        '07c39a99954504c5de8b5dc80160d8d63c4f26d0c5bd269e66c02e2694974b4a',
      );
    });

    test('handles Thai passwords and is always 64 characters', () {
      expect(
        hashRoomPassword('รหัสลับ', 'ABCD23'),
        '0a5d9b04dac00aa86d4c7ccb083457676511916ef0a8dc69b0b3ee631953c5a4',
      );
      expect(hashRoomPassword('', 'ABCD23').length, 64);
    });
  });
}
