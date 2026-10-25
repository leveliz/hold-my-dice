import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:hold_my_dice/features/bank/presentation/money_sheet.dart';
import 'package:hold_my_dice/features/bank/presentation/recipient_sheet.dart';
import 'package:hold_my_dice/features/bank/presentation/result_sheet.dart';
import 'package:hold_my_dice/features/bank/presentation/shortfall_screen.dart';

/// The flows a player triggers from the play screen: each one asks for an
/// amount, applies it to the session and then shows what happened. A payment
/// the payer cannot cover goes to the "not enough money" page instead.
class GameActions {
  GameActions(this.context, this.ref, {this.hideBalances = false});

  final BuildContext context;
  final WidgetRef ref;

  /// Balances stay out of the recipient list while the table is hidden.
  final bool hideBalances;

  BankNotifier get _notifier => ref.read(bankProvider.notifier);
  BankSession get _session => ref.read(bankProvider)!;

  Player _player(String id) =>
      _session.game.players.firstWhere((p) => p.id == id);

  int _balance(String id) => _session.game.balanceOf(id);

  /// "+" on a card, or the bank dropped on a player (no mortgage then).
  Future<void> receive(Player player, {bool allowMortgage = true}) async {
    final result = await showMoneySheet(
      context,
      player: player,
      balance: _balance(player.id),
      isPay: false,
      recent: _session.recentAmounts,
      allowMortgage: allowMortgage,
    );
    if (result == null || !context.mounted) return;
    result.mortgage
        ? _notifier.mortgage(player.id, result.amount)
        : _notifier.receive(player.id, result.amount);
    await _showResult([player.id]);
  }

  /// "−" on a card, or a player dropped on the bank.
  Future<void> payBank(Player player) async {
    final result = await showMoneySheet(
      context,
      player: player,
      balance: _balance(player.id),
      isPay: true,
      recent: _session.recentAmounts,
    );
    if (result == null || !context.mounted) return;
    await _settle(
      _notifier.pay(player.id, result.amount),
      player.id,
      Transaction.bank,
      result.amount,
    );
  }

  Future<void> transfer(Player from, Player to) async {
    final result = await showMoneySheet(
      context,
      player: from,
      balance: _balance(from.id),
      isPay: true,
      recent: _session.recentAmounts,
      recipient: to,
    );
    if (result == null || !context.mounted) return;
    await _settle(
      _notifier.transfer(from.id, to.id, result.amount),
      from.id,
      to.id,
      result.amount,
    );
  }

  /// Tapping a player's card: choose who to pay, then enter the amount.
  Future<void> pickRecipientAndTransfer(Player from) async {
    final game = _session.game;
    final options = [
      for (final p in game.activePlayers)
        if (p.id != from.id)
          RecipientOption(p, hideBalances ? null : game.balanceOf(p.id)),
    ];
    if (options.isEmpty) return;
    final to = await showRecipientSheet(context, from: from, options: options);
    if (to == null || !context.mounted) return;
    await transfer(from, to);
  }

  /// [sourceId] was dragged onto [targetId]; either may be the bank.
  Future<void> handleDrop(String sourceId, String targetId) {
    if (sourceId == Transaction.bank) {
      return receive(_player(targetId), allowMortgage: false);
    }
    if (targetId == Transaction.bank) return payBank(_player(sourceId));
    return transfer(_player(sourceId), _player(targetId));
  }

  Future<void> _settle(
    PayResult result,
    String payerId,
    String payeeId,
    int amount,
  ) async {
    final involved = [payerId, if (payeeId != Transaction.bank) payeeId];
    final transfer = payeeId == Transaction.bank
        ? null
        : TransferInfo(
            from: _player(payerId),
            to: _player(payeeId),
            amount: amount,
          );
    if (result is Paid) {
      await _showResult(involved, transfer: transfer);
      return;
    }
    final outcome = await context.push<ShortfallOutcome>(
      '/bank/play/shortfall',
      extra: ShortfallArgs(payerId: payerId, payeeId: payeeId, amount: amount),
    );
    if (!context.mounted || outcome == null) return;
    switch (outcome) {
      case ShortfallOutcome.paid:
        await _showResult(involved, transfer: transfer);
      case ShortfallOutcome.bankrupt:
        if (_session.game.isOver) {
          context.pushReplacement('/bank/summary');
        } else if (payeeId != Transaction.bank) {
          await _showResult([payeeId]);
        }
    }
  }

  /// New balance of everyone involved in the transaction just confirmed.
  Future<void> _showResult(List<String> playerIds, {TransferInfo? transfer}) {
    final session = _session;
    return showResultSheet(
      context,
      title: session.lastLabel ?? '',
      transfer: transfer,
      lines: [
        for (final id in playerIds)
          BalanceLine(_player(id), session.game.balanceOf(id)),
      ],
    );
  }
}
