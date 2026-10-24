import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:hold_my_dice/features/bank/domain/transaction.dart';

export 'package:hold_my_dice/features/bank/domain/player.dart';
export 'package:hold_my_dice/features/bank/domain/transaction.dart';

sealed class PayResult {
  const PayResult();
}

class Paid extends PayResult {
  const Paid(this.state);

  final GameState state;
}

/// The payer cannot cover the amount; nothing was changed.
class Insufficient extends PayResult {
  const Insufficient(this.shortfall);

  final int shortfall;
}

/// Immutable game state. Balances are derived from the transaction history,
/// and every operation returns a new state.
class GameState {
  GameState._(this.players, this.startingCash, this.goAmount, this.history);

  factory GameState.start({
    required List<Player> players,
    required int startingCash,
    required int goAmount,
  }) {
    if (players.length < 2) {
      throw ArgumentError('A game needs at least 2 players');
    }
    if (players.map((p) => p.id).toSet().length != players.length) {
      throw ArgumentError('Player ids must be unique');
    }
    if (startingCash <= 0 || goAmount <= 0) {
      throw ArgumentError('Starting cash and go amount must be positive');
    }
    return GameState._(
      List.unmodifiable(players),
      startingCash,
      goAmount,
      const [],
    );
  }

  /// Restores a game saved with [toJson]. Throws if the data is not a game
  /// this version understands, so callers can discard a corrupt backup.
  factory GameState.fromJson(Map<String, dynamic> json) {
    if (json['v'] != _jsonVersion) {
      throw FormatException('Unsupported game version: ${json['v']}');
    }
    final base = GameState.start(
      players: [
        for (final p in json['players'] as List)
          Player.fromJson(p as Map<String, dynamic>),
      ],
      startingCash: json['startingCash'] as int,
      goAmount: json['goAmount'] as int,
    );
    return GameState._(base.players, base.startingCash, base.goAmount, [
      for (final e in json['history'] as List)
        Entry.fromJson(e as Map<String, dynamic>),
    ]);
  }

  static const _jsonVersion = 1;

  final List<Player> players;
  final int startingCash;
  final int goAmount;
  final List<Entry> history;

  bool get canUndo => history.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'v': _jsonVersion,
    'players': [for (final p in players) p.toJson()],
    'startingCash': startingCash,
    'goAmount': goAmount,
    'history': [for (final e in history) e.toJson()],
  };

  Iterable<Transaction> get _transactions =>
      history.expand((e) => e.transactions);

  int balanceOf(String playerId) {
    _player(playerId);
    var balance = startingCash;
    for (final t in _transactions) {
      if (t.to == playerId) balance += t.amount;
      if (t.from == playerId) balance -= t.amount;
    }
    return balance;
  }

  bool isBankrupt(String playerId) {
    _player(playerId);
    return history.any((e) => e.bankruptPlayerId == playerId);
  }

  List<Player> get activePlayers =>
      players.where((p) => !isBankrupt(p.id)).toList();

  bool get isOver => activePlayers.length <= 1;

  Player? get winner => isOver ? activePlayers.firstOrNull : null;

  /// Active players by money (ties keep seating order), then bankrupt players
  /// with the most recent bankruptcy first.
  List<Player> get ranking {
    final active = activePlayers;
    final indexOf = {for (final (i, p) in players.indexed) p.id: i};
    active.sort((a, b) {
      final byMoney = balanceOf(b.id).compareTo(balanceOf(a.id));
      return byMoney != 0 ? byMoney : indexOf[a.id]!.compareTo(indexOf[b.id]!);
    });
    final bankrupt = [
      for (final e in history.reversed)
        if (e.bankruptPlayerId != null) _player(e.bankruptPlayerId!),
    ];
    return [...active, ...bankrupt];
  }

  GameState passGo(String playerId) {
    _requireActive(playerId);
    return _add(
      Entry([
        Transaction(
          from: Transaction.bank,
          to: playerId,
          amount: goAmount,
          type: TransactionType.passGo,
        ),
      ]),
    );
  }

  GameState receiveFromBank(String playerId, int amount) {
    _requireActive(playerId);
    _requirePositive(amount);
    return _add(
      Entry([
        Transaction(
          from: Transaction.bank,
          to: playerId,
          amount: amount,
          type: TransactionType.receiveFromBank,
        ),
      ]),
    );
  }

  GameState mortgage(String playerId, int amount) {
    _requireActive(playerId);
    _requirePositive(amount);
    return _add(
      Entry([
        Transaction(
          from: Transaction.bank,
          to: playerId,
          amount: amount,
          type: TransactionType.mortgage,
        ),
      ]),
    );
  }

  PayResult payBank(String playerId, int amount) {
    return _pay(
      playerId,
      Transaction.bank,
      amount,
      TransactionType.payBank,
      const [],
    );
  }

  PayResult transfer(String fromId, String toId, int amount) {
    if (fromId == toId) {
      throw ArgumentError('Cannot transfer to the same player');
    }
    return _pay(fromId, toId, amount, TransactionType.transfer, const []);
  }

  /// Pays [amount] after first mortgaging properties worth [mortgages]; all of
  /// it is recorded as a single undoable entry.
  PayResult payWithMortgage({
    required String payerId,
    required String payeeId,
    required int amount,
    required List<int> mortgages,
  }) {
    mortgages.forEach(_requirePositive);
    return _pay(
      payerId,
      payeeId,
      amount,
      payeeId == Transaction.bank
          ? TransactionType.payBank
          : TransactionType.transfer,
      mortgages,
    );
  }

  /// Removes [playerId] from the game because they cannot pay [owed].
  /// A player creditor receives the full amount (the bank covers what the
  /// debtor cannot); with no creditor the debtor's cash returns to the bank.
  GameState declareBankrupt(
    String playerId, {
    required int owed,
    String? creditorId,
  }) {
    _requireActive(playerId);
    _requirePositive(owed);
    if (creditorId != null) {
      if (creditorId == playerId) {
        throw ArgumentError('A player cannot owe themselves');
      }
      _requireActive(creditorId);
    }
    final cash = balanceOf(playerId);
    if (cash >= owed) {
      throw ArgumentError('Player can still pay, bankruptcy is not allowed');
    }
    Transaction bankruptcy(String from, String to, int amount) => Transaction(
      from: from,
      to: to,
      amount: amount,
      type: TransactionType.bankruptcy,
    );
    final transactions = creditorId == null
        ? [if (cash > 0) bankruptcy(playerId, Transaction.bank, cash)]
        : [
            if (cash > 0) bankruptcy(playerId, creditorId, cash),
            bankruptcy(Transaction.bank, creditorId, owed - cash),
          ];
    return _add(Entry(transactions, bankruptPlayerId: playerId));
  }

  GameState undo() {
    if (!canUndo) throw StateError('Nothing to undo');
    return GameState._(
      players,
      startingCash,
      goAmount,
      history.sublist(0, history.length - 1),
    );
  }

  PayResult _pay(
    String payerId,
    String payeeId,
    int amount,
    TransactionType type,
    List<int> mortgages,
  ) {
    _requireActive(payerId);
    if (payeeId != Transaction.bank) _requireActive(payeeId);
    _requirePositive(amount);
    final available =
        balanceOf(payerId) + mortgages.fold<int>(0, (a, b) => a + b);
    if (available < amount) return Insufficient(amount - available);
    return Paid(
      _add(
        Entry([
          for (final m in mortgages)
            Transaction(
              from: Transaction.bank,
              to: payerId,
              amount: m,
              type: TransactionType.mortgage,
            ),
          Transaction(from: payerId, to: payeeId, amount: amount, type: type),
        ]),
      ),
    );
  }

  GameState _add(Entry entry) =>
      GameState._(players, startingCash, goAmount, [...history, entry]);

  Player _player(String id) {
    return players.firstWhere(
      (p) => p.id == id,
      orElse: () => throw ArgumentError('Unknown player: $id'),
    );
  }

  void _requireActive(String id) {
    _player(id);
    if (isBankrupt(id)) throw StateError('Player $id is bankrupt');
  }

  void _requirePositive(int amount) {
    if (amount <= 0) throw ArgumentError('Amount must be positive: $amount');
  }
}
