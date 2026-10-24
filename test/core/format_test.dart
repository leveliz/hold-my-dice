import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/core/format.dart';

void main() {
  test('formatMoney adds thousands separators', () {
    expect(formatMoney(0), '0');
    expect(formatMoney(500), '500');
    expect(formatMoney(15000), '15,000');
    expect(formatMoney(1500000), '1,500,000');
  });

  test('formatMoney keeps the sign for negatives', () {
    expect(formatMoney(-2500), '-2,500');
  });
}
