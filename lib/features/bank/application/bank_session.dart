import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/bank/application/entry_labels.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';

class BankSession {
  const BankSession({
    required this.game,
    this.undoAvailable = false,
    this.lastLabel,
    this.recentAmounts = const [],
  });

  final GameState game;

  /// Only the transaction just made can be undone, and only once.
  final bool undoAvailable;
  final String? lastLabel;

  /// Amounts used in this game, newest first, for quick re-entry.
  final List<int> recentAmounts;
}

class BankNotifier extends Notifier<BankSession?> {
  static const _recentLimit = 3;

  @override
  BankSession? build() => null;

  GameState get _game => state!.game;

  void start({
    required List<Player> players,
    required int startingCash,
    required int goAmount,
  }) {
    state = BankSession(
      game: GameState.start(
        players: players,
        startingCash: startingCash,
        goAmount: goAmount,
      ),
    );
  }

  void passGo(String id) => _commit(_game.passGo(id));

  void receive(String id, int amount) =>
      _commit(_game.receiveFromBank(id, amount), amount: amount);

  void mortgage(String id, int amount) =>
      _commit(_game.mortgage(id, amount), amount: amount);

  PayResult pay(String id, int amount) =>
      _commitPay(_game.payBank(id, amount), amount);

  PayResult transfer(String fromId, String toId, int amount) =>
      _commitPay(_game.transfer(fromId, toId, amount), amount);

  /// Mortgages [mortgages] and then pays [amount] to [payeeId] (the bank or a
  /// player) as one undoable entry.
  PayResult payWithMortgage({
    required String payerId,
    required String payeeId,
    required int amount,
    required List<int> mortgages,
  }) {
    final result = _game.payWithMortgage(
      payerId: payerId,
      payeeId: payeeId,
      amount: amount,
      mortgages: mortgages,
    );
    return _commitPay(result, amount);
  }

  void declareBankrupt(String id, {required int owed, String? creditorId}) {
    _commit(_game.declareBankrupt(id, owed: owed, creditorId: creditorId));
  }

  void end() => state = null;

  void undo() {
    final s = state;
    if (s == null || !s.undoAvailable) return;
    state = BankSession(game: s.game.undo(), recentAmounts: s.recentAmounts);
  }

  PayResult _commitPay(PayResult result, int amount) {
    if (result is Paid) _commit(result.state, amount: amount);
    return result;
  }

  void _commit(GameState game, {int? amount}) {
    final recent = amount == null
        ? state!.recentAmounts
        : [
            amount,
            ...state!.recentAmounts.where((a) => a != amount),
          ].take(_recentLimit).toList();
    state = BankSession(
      game: game,
      undoAvailable: true,
      lastLabel: describeEntry(game, game.history.last).title,
      recentAmounts: recent,
    );
  }
}

final bankProvider = NotifierProvider<BankNotifier, BankSession?>(
  BankNotifier.new,
);
