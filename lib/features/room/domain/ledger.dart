import 'package:hold_my_dice/features/bank/domain/transaction.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

/// The largest amount one entry may move.
const maxEntryAmount = 999999999;

/// A debt in a bankruptcy may not exceed this many times the starting cash.
const maxOwedTimesStartingCash = 10;

/// Why an entry was refused.
enum LedgerRejection {
  insufficient,
  notActive,
  invalidAmount,
  bankLimit,
  invalidBankrupt,

  /// Who pays and who receives do not fit the kind of entry.
  invalidParties,

  /// The entry is not one that can be undone (already undone, or a kind
  /// that has no undo here).
  notUndoable,
}

/// The money side of a game: who holds what, who is out, who is the banker.
/// Balances hold one number per seat, plus `bank` when the bank has a limit.
class LedgerState {
  LedgerState({
    required Map<String, int> balances,
    required List<String> bankrupt,
    required this.bankerSeat,
    required this.startingCash,
  }) : balances = Map.unmodifiable(balances),
       bankrupt = List.unmodifiable(bankrupt);

  final Map<String, int> balances;

  /// In the order they went out.
  final List<String> bankrupt;

  /// The first seat to go bankrupt.
  final String? bankerSeat;
  final int startingCash;

  bool isActive(String seat) =>
      seat != Transaction.bank &&
      balances.containsKey(seat) &&
      !bankrupt.contains(seat);

  bool get bankHasLimit => balances.containsKey(Transaction.bank);

  LedgerState _with({
    Map<String, int>? balances,
    List<String>? bankrupt,
    String? bankerSeat,
  }) => LedgerState(
    balances: balances ?? this.balances,
    bankrupt: bankrupt ?? this.bankrupt,
    bankerSeat: bankerSeat ?? this.bankerSeat,
    startingCash: startingCash,
  );
}

sealed class LedgerResult {
  const LedgerResult();
}

class Applied extends LedgerResult {
  const Applied(this.state);

  final LedgerState state;
}

class Rejected extends LedgerResult {
  const Rejected(this.reason);

  final LedgerRejection reason;
}

/// The rules of the money, as pure functions on [LedgerState]. They give the
/// same answers as `GameState` in the single-device mode (a test plays
/// thousands of random games on both).
class Ledger {
  const Ledger._();

  static LedgerState initial(
    List<String> seats,
    int startingCash, {
    int? bankLimit,
  }) => LedgerState(
    balances: {
      for (final s in seats) s: startingCash,
      Transaction.bank: ?bankLimit,
    },
    bankrupt: const [],
    bankerSeat: null,
    startingCash: startingCash,
  );

  static LedgerResult apply(LedgerState state, RoomEntry entry) {
    if (entry.voided) return Applied(state);
    return switch (entry.kind) {
      EntryKind.receive ||
      EntryKind.mortgage ||
      EntryKind.passGo => _fromBank(state, entry),
      EntryKind.payBank => _payBank(state, entry),
      EntryKind.transfer => _transfer(state, entry),
      EntryKind.bankrupt => _bankrupt(state, entry),
    };
  }

  /// Gives back what [entry] did to the balances, as when a person takes
  /// back their latest press. Refused when it would leave a seat (or a bank
  /// with a limit) below zero, and for entries that are already undone or of
  /// a kind that is not undone (mortgage, bankruptcy).
  static LedgerResult undo(LedgerState state, RoomEntry entry) {
    if (entry.voided) return const Rejected(LedgerRejection.notUndoable);
    final amount = entry.amount;
    final balances = {...state.balances};
    switch (entry.kind) {
      case EntryKind.receive || EntryKind.passGo:
        final to = entry.to;
        if (to == null || amount == null || !balances.containsKey(to)) {
          return const Rejected(LedgerRejection.invalidParties);
        }
        if (balances[to]! < amount) {
          return const Rejected(LedgerRejection.insufficient);
        }
        balances[to] = balances[to]! - amount;
        if (state.bankHasLimit) {
          balances[Transaction.bank] = balances[Transaction.bank]! + amount;
        }
      case EntryKind.payBank:
        final from = entry.from;
        if (from == null || amount == null || !balances.containsKey(from)) {
          return const Rejected(LedgerRejection.invalidParties);
        }
        if (state.bankHasLimit) {
          if (balances[Transaction.bank]! < amount) {
            return const Rejected(LedgerRejection.bankLimit);
          }
          balances[Transaction.bank] = balances[Transaction.bank]! - amount;
        }
        balances[from] = balances[from]! + amount;
      case EntryKind.transfer:
        final from = entry.from;
        final to = entry.to;
        if (from == null ||
            to == null ||
            amount == null ||
            !balances.containsKey(from) ||
            !balances.containsKey(to)) {
          return const Rejected(LedgerRejection.invalidParties);
        }
        if (balances[to]! < amount) {
          return const Rejected(LedgerRejection.insufficient);
        }
        balances[from] = balances[from]! + amount;
        balances[to] = balances[to]! - amount;
      case EntryKind.mortgage || EntryKind.bankrupt:
        return const Rejected(LedgerRejection.notUndoable);
    }
    return Applied(state._with(balances: balances));
  }

  /// Applies [entries] one after another, all or nothing: the first refusal
  /// refuses the whole group and the original state stays as it was.
  static LedgerResult applyGroup(LedgerState state, List<RoomEntry> entries) {
    var current = state;
    for (final entry in entries) {
      final result = apply(current, entry);
      if (result is Rejected) return result;
      current = (result as Applied).state;
    }
    return Applied(current);
  }

  static Rejected? _badAmount(int? amount) =>
      amount == null || amount < 1 || amount > maxEntryAmount
      ? const Rejected(LedgerRejection.invalidAmount)
      : null;

  static LedgerResult _fromBank(LedgerState s, RoomEntry e) {
    final to = e.to;
    if (e.from != Transaction.bank || to == null || to == Transaction.bank) {
      return const Rejected(LedgerRejection.invalidParties);
    }
    if (_badAmount(e.amount) case final bad?) return bad;
    final amount = e.amount!;
    if (!s.isActive(to)) return const Rejected(LedgerRejection.notActive);
    final balances = {...s.balances};
    if (s.bankHasLimit) {
      if (balances[Transaction.bank]! < amount) {
        return const Rejected(LedgerRejection.bankLimit);
      }
      balances[Transaction.bank] = balances[Transaction.bank]! - amount;
    }
    balances[to] = balances[to]! + amount;
    return Applied(s._with(balances: balances));
  }

  static LedgerResult _payBank(LedgerState s, RoomEntry e) {
    final from = e.from;
    if (e.to != Transaction.bank || from == null || from == Transaction.bank) {
      return const Rejected(LedgerRejection.invalidParties);
    }
    if (_badAmount(e.amount) case final bad?) return bad;
    final amount = e.amount!;
    if (!s.isActive(from)) return const Rejected(LedgerRejection.notActive);
    if (s.balances[from]! < amount) {
      return const Rejected(LedgerRejection.insufficient);
    }
    final balances = {...s.balances};
    balances[from] = balances[from]! - amount;
    if (s.bankHasLimit) {
      balances[Transaction.bank] = balances[Transaction.bank]! + amount;
    }
    return Applied(s._with(balances: balances));
  }

  static LedgerResult _transfer(LedgerState s, RoomEntry e) {
    final from = e.from;
    final to = e.to;
    if (from == null ||
        to == null ||
        from == to ||
        from == Transaction.bank ||
        to == Transaction.bank) {
      return const Rejected(LedgerRejection.invalidParties);
    }
    if (_badAmount(e.amount) case final bad?) return bad;
    final amount = e.amount!;
    if (!s.isActive(from) || !s.isActive(to)) {
      return const Rejected(LedgerRejection.notActive);
    }
    if (s.balances[from]! < amount) {
      return const Rejected(LedgerRejection.insufficient);
    }
    final balances = {...s.balances};
    balances[from] = balances[from]! - amount;
    balances[to] = balances[to]! + amount;
    return Applied(s._with(balances: balances));
  }

  /// The debtor ends at 0. With a creditor, the creditor receives the whole
  /// debt and the bank pays what the debtor's cash does not cover; without
  /// one, the debtor's cash goes to the bank. The bank may go below zero here.
  static LedgerResult _bankrupt(LedgerState s, RoomEntry e) {
    final info = e.bankrupt;
    if (info == null) return const Rejected(LedgerRejection.invalidBankrupt);
    final seat = info.seat;
    final creditor = info.creditorSeat;
    if (!s.isActive(seat)) return const Rejected(LedgerRejection.notActive);
    if (creditor != null) {
      if (creditor == seat) {
        return const Rejected(LedgerRejection.invalidBankrupt);
      }
      if (!s.isActive(creditor)) {
        return const Rejected(LedgerRejection.notActive);
      }
    }
    final cash = s.balances[seat]!;
    if (info.cash != cash ||
        cash >= info.owed ||
        info.owed > maxOwedTimesStartingCash * s.startingCash) {
      return const Rejected(LedgerRejection.invalidBankrupt);
    }
    final balances = {...s.balances};
    balances[seat] = 0;
    if (creditor != null) {
      balances[creditor] = balances[creditor]! + info.owed;
      if (s.bankHasLimit) {
        balances[Transaction.bank] =
            balances[Transaction.bank]! - (info.owed - cash);
      }
    } else if (s.bankHasLimit) {
      balances[Transaction.bank] = balances[Transaction.bank]! + cash;
    }
    return Applied(
      s._with(
        balances: balances,
        bankrupt: [...s.bankrupt, seat],
        bankerSeat: s.bankerSeat ?? seat,
      ),
    );
  }
}
