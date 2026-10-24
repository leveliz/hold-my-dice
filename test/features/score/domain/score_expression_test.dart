import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/score/domain/score_expression.dart';

void main() {
  group('evaluateScore', () {
    test('a plain number', () {
      expect(evaluateScore('7'), 7);
      expect(evaluateScore('0'), 0);
      expect(evaluateScore('120'), 120);
    });

    test('negative numbers', () {
      expect(evaluateScore('-4'), -4);
      expect(evaluateScore('-0'), 0);
      expect(evaluateScore('−4'), -4);
    });

    test('sums and differences', () {
      expect(evaluateScore('3+5+2'), 10);
      expect(evaluateScore('12-3-1'), 8);
      expect(evaluateScore('-4+10'), 6);
      expect(evaluateScore('2-9'), -7);
      expect(evaluateScore('1+2-3+4-5'), -1);
    });

    test('a leading plus is allowed', () {
      expect(evaluateScore('+5'), 5);
      expect(evaluateScore('+5+5'), 10);
    });

    test('runs of signs multiply', () {
      expect(evaluateScore('3+-2'), 1);
      expect(evaluateScore('3--2'), 5);
      expect(evaluateScore('3-+2'), 1);
      expect(evaluateScore('--4'), 4);
      expect(evaluateScore('---4'), -4);
    });

    test('spaces are ignored', () {
      expect(evaluateScore(' 3 + 5 '), 8);
      expect(evaluateScore('- 4'), -4);
    });

    test('leading zeros are fine', () {
      expect(evaluateScore('007+03'), 10);
    });

    test('empty and unfinished input has no value', () {
      expect(evaluateScore(''), isNull);
      expect(evaluateScore('   '), isNull);
      expect(evaluateScore('3+'), isNull);
      expect(evaluateScore('-'), isNull);
      expect(evaluateScore('+'), isNull);
      expect(evaluateScore('5-'), isNull);
      expect(evaluateScore('3+5+'), isNull);
    });

    test('anything else is refused', () {
      expect(evaluateScore('3*2'), isNull);
      expect(evaluateScore('3/2'), isNull);
      expect(evaluateScore('a'), isNull);
      expect(evaluateScore('3 5'), 35, reason: 'spaces vanish before parsing');
      expect(evaluateScore('1.5'), isNull);
      expect(evaluateScore('1,000'), isNull);
      expect(evaluateScore('(3)'), isNull);
    });

    test('numbers longer than the limit are refused', () {
      expect(evaluateScore('123456789'), 123456789);
      expect(evaluateScore('1234567890'), isNull);
      expect(evaluateScore('1+1234567890'), isNull);
    });

    test('many terms still add up exactly', () {
      final many = List.filled(1000, '999999999').join('+');
      expect(evaluateScore(many), 999999999 * 1000);
    });
  });

  group('previewScore', () {
    test('equals the result when the sum is complete', () {
      expect(previewScore('3+5+2'), 10);
      expect(previewScore('-4'), -4);
    });

    test('ignores an unfinished ending', () {
      expect(previewScore('3+'), 3);
      expect(previewScore('3+5-'), 8);
      expect(previewScore('3+-'), 3);
      expect(previewScore('12-'), 12);
    });

    test('has nothing to show before a number is typed', () {
      expect(previewScore(''), isNull);
      expect(previewScore('-'), isNull);
      expect(previewScore('+-'), isNull);
    });

    test('still refuses invalid text', () {
      expect(previewScore('3*'), isNull);
      expect(previewScore('abc'), isNull);
    });
  });
}
