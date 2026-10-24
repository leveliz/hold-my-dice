/// Longest number a score may contain, so sums can never overflow.
const maxScoreDigits = 9;

/// Evaluates a score typed as a sum like "3+5+2", "-4+10" or "12-3-1".
///
/// Only whole numbers with `+` and `-` (also the real minus sign `−`) are
/// understood. A run of signs is allowed (`3+-2`, `3--2`) and counts as the
/// product of its signs. Returns null for anything incomplete or invalid, such
/// as an empty text, a trailing operator or a letter.
int? evaluateScore(String input) {
  var i = 0;
  var total = 0;
  final text = input.replaceAll(' ', '');
  if (text.isEmpty) return null;

  while (i < text.length) {
    var sign = 1;
    while (i < text.length && _isSign(text[i])) {
      if (_isMinus(text[i])) sign = -sign;
      i++;
    }
    final start = i;
    while (i < text.length && _isDigit(text[i])) {
      i++;
    }
    final digits = i - start;
    if (digits == 0 || digits > maxScoreDigits) return null;

    total += sign * int.parse(text.substring(start, i));
  }
  return total;
}

/// Like [evaluateScore], but forgives an unfinished ending such as "3+" or
/// "5-", so the result can be shown while the person is still typing.
int? previewScore(String input) {
  var text = input.replaceAll(' ', '');
  while (text.isNotEmpty && _isSign(text[text.length - 1])) {
    text = text.substring(0, text.length - 1);
  }
  return evaluateScore(text);
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
bool _isMinus(String c) => c == '-' || c == '−';
bool _isSign(String c) => c == '+' || _isMinus(c);
