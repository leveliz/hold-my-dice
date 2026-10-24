import 'package:flutter/services.dart';
import 'package:hold_my_dice/core/format.dart';

/// Keeps only digits and shows them with thousands separators while typing.
/// Zero is treated as empty so the field never shows a leading zero.
class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter({this.maxDigits = 9});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    final value = int.tryParse(digits) ?? 0;
    if (value == 0) return const TextEditingValue();
    final text = formatMoney(value);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
