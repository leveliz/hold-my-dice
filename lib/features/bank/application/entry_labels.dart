import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';

class EntryLabel {
  const EntryLabel(this.title, [this.subtitle]);

  final String title;
  final String? subtitle;
}

/// Thai description of one undoable [Entry], used by the undo bar, the
/// confirmation sheet and the history page.
EntryLabel describeEntry(GameState game, Entry entry) {
  String name(String id) => id == Transaction.bank
      ? 'ธนาคาร'
      : game.players.firstWhere((p) => p.id == id).name;
  String money(int amount) => formatMoney(amount);

  final bankruptId = entry.bankruptPlayerId;
  if (bankruptId != null) {
    final txs = entry.transactions;
    final creditorId = txs
        .map((t) => t.to)
        .where((id) => id != Transaction.bank)
        .firstOrNull;
    final paidToCreditor = txs
        .where((t) => t.to == creditorId)
        .fold(0, (sum, t) => sum + t.amount);
    final bankCover = txs
        .where((t) => t.from == Transaction.bank)
        .fold(0, (sum, t) => sum + t.amount);
    final returnedToBank = txs
        .where((t) => t.to == Transaction.bank)
        .fold(0, (sum, t) => sum + t.amount);
    final parts = <String>[
      if (creditorId != null)
        '${name(creditorId)} ได้รับ ${money(paidToCreditor)}',
      if (bankCover > 0) 'ธนาคารจ่ายส่วนต่าง ${money(bankCover)}',
      if (returnedToBank > 0) 'เงินที่เหลือ ${money(returnedToBank)} คืนธนาคาร',
    ];
    return EntryLabel(
      '${name(bankruptId)} ล้มละลาย',
      parts.isEmpty ? null : parts.join(' · '),
    );
  }

  final main = entry.transactions.last;
  final mortgages = [
    for (final t in entry.transactions)
      if (!identical(t, main) && t.type == TransactionType.mortgage) t.amount,
  ];
  final mortgageNote = mortgages.isEmpty
      ? null
      : 'จำนอง ${mortgages.map((m) => '+${money(m)}').join(' ')}';

  final title = switch (main.type) {
    TransactionType.passGo =>
      'ผ่านจุดเริ่ม ${name(main.to)} +${money(main.amount)}',
    TransactionType.receiveFromBank =>
      'รับจากธนาคาร ${name(main.to)} +${money(main.amount)}',
    TransactionType.mortgage => 'จำนอง ${name(main.to)} +${money(main.amount)}',
    TransactionType.payBank =>
      'จ่ายธนาคาร ${name(main.from)} -${money(main.amount)}',
    TransactionType.transfer =>
      'โอน ${money(main.amount)} ${name(main.from)} → ${name(main.to)}',
    TransactionType.bankruptcy => 'ล้มละลาย',
  };
  return EntryLabel(title, mortgageNote);
}
