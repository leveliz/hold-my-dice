/// What an entry in a room's ledger does. One entry is one transaction, so the
/// rules that check an entry can be a fixed formula per kind.
enum EntryKind { receive, mortgage, passGo, payBank, transfer, bankrupt }

/// A seat going out of the game because it cannot pay [owed].
class BankruptInfo {
  const BankruptInfo({
    required this.seat,
    this.creditorSeat,
    required this.cash,
    required this.owed,
  });

  final String seat;

  /// Who is owed the money; null when the debt is to the bank.
  final String? creditorSeat;

  /// What the seat holds at that moment.
  final int cash;
  final int owed;
}

/// One line of a room's history, as the ledger sees it.
class RoomEntry {
  const RoomEntry({
    required this.seq,
    required this.kind,
    required this.seat,
    this.from,
    this.to,
    this.amount,
    this.bankrupt,
    this.group,
    this.reason,
    this.voided = false,
  });

  final int seq;
  final EntryKind kind;

  /// The seat of the person who pressed the button.
  final String seat;

  /// Who pays and who receives (a seat id or `bank`); empty for [bankrupt].
  final String? from;
  final String? to;
  final int? amount;
  final BankruptInfo? bankrupt;

  /// Entries made by one press (mortgage and then pay) share a group.
  final String? group;
  final String? reason;

  /// Undone: still shown in the history but it moves no money.
  final bool voided;
}
