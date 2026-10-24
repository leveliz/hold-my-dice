import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';

String typed(String text, {int maxDigits = 9}) {
  final f = ThousandsFormatter(maxDigits: maxDigits);
  return f
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text))
      .text;
}

void main() {
  test('adds separators as digits are typed', () {
    expect(typed('1'), '1');
    expect(typed('1500'), '1,500');
    expect(typed('1500000'), '1,500,000');
  });

  test('re-formats text that already has separators', () {
    expect(typed('1,5000'), '15,000');
  });

  test('drops anything that is not a digit', () {
    expect(typed('1a5,0 0'), '1,500');
    expect(typed('abc'), '');
  });

  test('zero and leading zeros show as empty or trimmed', () {
    expect(typed('0'), '');
    expect(typed('000'), '');
    expect(typed('0150'), '150');
  });

  test('limits the number of digits', () {
    expect(typed('1234567890', maxDigits: 9), '123,456,789');
  });

  test('cursor stays at the end', () {
    final v = const ThousandsFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '2500'),
    );
    expect(v.selection.baseOffset, v.text.length);
  });

  test('parseMoney reads formatted text back', () {
    expect(parseMoney('1,500'), 1500);
    expect(parseMoney(''), isNull);
  });
}
