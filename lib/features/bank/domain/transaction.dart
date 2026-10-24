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

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    from: json['from'] as String,
    to: json['to'] as String,
    amount: json['amount'] as int,
    type: TransactionType.values.byName(json['type'] as String),
  );

  /// Party id used for the bank on either side of a transaction.
  static const bank = 'bank';

  final String from;
  final String to;
  final int amount;
  final TransactionType type;

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'amount': amount,
    'type': type.name,
  };
}

/// One undoable step. Usually a single transaction; a "mortgage + pay" or a
/// bankruptcy groups several so that undo reverts them together.
class Entry {
  const Entry(this.transactions, {this.bankruptPlayerId});

  factory Entry.fromJson(Map<String, dynamic> json) => Entry([
    for (final t in json['transactions'] as List)
      Transaction.fromJson(t as Map<String, dynamic>),
  ], bankruptPlayerId: json['bankruptPlayerId'] as String?);

  final List<Transaction> transactions;
  final String? bankruptPlayerId;

  Map<String, dynamic> toJson() => {
    'transactions': [for (final t in transactions) t.toJson()],
    if (bankruptPlayerId != null) 'bankruptPlayerId': bankruptPlayerId,
  };
}
