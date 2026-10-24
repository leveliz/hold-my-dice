import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0', 'en_US');

String formatMoney(int amount) => _money.format(amount);

int? parseMoney(String text) => int.tryParse(text.replaceAll(',', ''));
