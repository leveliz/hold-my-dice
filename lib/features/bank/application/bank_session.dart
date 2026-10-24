import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/format.dart';
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

  String _name(String id) => _game.players.firstWhere((p) => p.id == id).name;

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

  void passGo(String id) {
    final amount = _game.goAmount;
    _commit(
      _game.passGo(id),
      'ผ่านจุดเริ่ม ${_name(id)} +${formatMoney(amount)}',
    );
  }

  void receive(String id, int amount) {
    _commit(
      _game.receiveFromBank(id, amount),
      'รับจากธนาคาร ${_name(id)} +${formatMoney(amount)}',
      amount: amount,
    );
  }

  void mortgage(String id, int amount) {
    _commit(
      _game.mortgage(id, amount),
      'จำนอง ${_name(id)} +${formatMoney(amount)}',
      amount: amount,
    );
  }

  PayResult pay(String id, int amount) {
    final result = _game.payBank(id, amount);
    if (result is Paid) {
      _commit(
        result.state,
        'จ่ายธนาคาร ${_name(id)} -${formatMoney(amount)}',
        amount: amount,
      );
    }
    return result;
  }

  void end() => state = null;

  void undo() {
    final s = state;
    if (s == null || !s.undoAvailable) return;
    state = BankSession(game: s.game.undo(), recentAmounts: s.recentAmounts);
  }

  void _commit(GameState game, String label, {int? amount}) {
    final recent = amount == null
        ? state!.recentAmounts
        : [
            amount,
            ...state!.recentAmounts.where((a) => a != amount),
          ].take(_recentLimit).toList();
    state = BankSession(
      game: game,
      undoAvailable: true,
      lastLabel: label,
      recentAmounts: recent,
    );
  }
}

final bankProvider = NotifierProvider<BankNotifier, BankSession?>(
  BankNotifier.new,
);
