enum TransactionType {
  receiveFromBank,
  payBank,
  transfer,
  passGo,
  mortgage,
  bankruptcy,
}

class Transaction {
  const Transaction({
    required this.from,
    required this.to,
    required this.amount,
    required this.type,
  });

  /// Party id used for the bank on either side of a transaction.
  static const bank = 'bank';

  final String from;
  final String to;
  final int amount;
  final TransactionType type;
}

/// One undoable step. Usually a single transaction; a "mortgage + pay" or a
/// bankruptcy groups several so that undo reverts them together.
class Entry {
  const Entry(this.transactions, {this.bankruptPlayerId});

  final List<Transaction> transactions;
  final String? bankruptPlayerId;
}
