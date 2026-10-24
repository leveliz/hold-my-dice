import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:hold_my_dice/features/bank/presentation/money_sheet.dart';
import 'package:hold_my_dice/features/bank/presentation/player_card.dart';
import 'package:hold_my_dice/features/bank/presentation/result_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// Card heights (dp). Tall cards show at most [maxTallPlayers]; with more
// players, or on a short screen, rows switch to the compact single-line card.
const maxTallPlayers = 4;
const _tallMin = 112.0;
const _tallMax = 150.0;
const _compactMin = 60.0;
const _compactMax = 92.0;
const _gap = 12.0;
const _undoSlotHeight = 54.0;
const _listPadding = EdgeInsets.fromLTRB(16, 4, 16, 12);

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  Future<void> _receive(
    BuildContext context,
    WidgetRef ref,
    BankSession session,
    Player player,
  ) async {
    final result = await showMoneySheet(
      context,
      player: player,
      balance: session.game.balanceOf(player.id),
      isPay: false,
      recent: session.recentAmounts,
    );
    if (result == null) return;
    final notifier = ref.read(bankProvider.notifier);
    result.mortgage
        ? notifier.mortgage(player.id, result.amount)
        : notifier.receive(player.id, result.amount);
    if (context.mounted) await _showResult(context, ref, [player.id]);
  }

  /// Summary of the new balance of everyone involved in the transaction
  /// that was just confirmed.
  Future<void> _showResult(
    BuildContext context,
    WidgetRef ref,
    List<String> playerIds,
  ) {
    final session = ref.read(bankProvider)!;
    return showResultSheet(
      context,
      title: session.lastLabel ?? '',
      lines: [
        for (final id in playerIds)
          BalanceLine(
            session.game.players.firstWhere((p) => p.id == id),
            session.game.balanceOf(id),
          ),
      ],
    );
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('leave-dialog'),
        title: const Text('ออกจากเกมนี้?'),
        content: const Text('เกมที่กำลังเล่นอยู่จะหายไป'),
        actions: [
          TextButton(
            key: const ValueKey('leave-stay'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('เล่นต่อ'),
          ),
          FilledButton(
            key: const ValueKey('leave-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกจากเกม'),
          ),
        ],
      ),
    );
    if (leave == true && context.mounted) {
      ref.read(bankProvider.notifier).end();
      context.go('/');
    }
  }

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    BankSession session,
    Player player,
  ) async {
    final result = await showMoneySheet(
      context,
      player: player,
      balance: session.game.balanceOf(player.id),
      isPay: true,
      recent: session.recentAmounts,
    );
    if (result == null) return;
    final outcome = ref
        .read(bankProvider.notifier)
        .pay(player.id, result.amount);
    if (outcome is Insufficient && context.mounted) {
      // Placeholder until the "not enough money" screen (phase 4).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เงินไม่พอ ขาด ${formatMoney(outcome.shortfall)}'),
        ),
      );
    }
    if (outcome is Paid && context.mounted) {
      await _showResult(context, ref, [player.id]);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(bankProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pocket Banker')),
        body: const Center(child: Text('ยังไม่ได้เริ่มเกม')),
      );
    }
    final players = session.game.players;
    final notifier = ref.read(bankProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(toolbarHeight: 72, title: const Text('Pocket Banker')),
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final n = players.length;
                  final available =
                      constraints.maxHeight -
                      _listPadding.vertical -
                      _gap * (n - 1);
                  final perCard = available / n;
                  final tall = n <= maxTallPlayers && perCard >= _tallMin;
                  final height = tall
                      ? perCard.clamp(_tallMin, _tallMax).toDouble()
                      : perCard.clamp(_compactMin, _compactMax).toDouble();
                  return ListView.separated(
                    padding: _listPadding,
                    itemCount: n,
                    separatorBuilder: (_, _) => const SizedBox(height: _gap),
                    itemBuilder: (context, i) {
                      final p = players[i];
                      return SizedBox(
                        height: height,
                        child: PlayerCard(
                          player: p,
                          balance: session.game.balanceOf(p.id),
                          compact: !tall,
                          onReceive: () => _receive(context, ref, session, p),
                          onPay: () => _pay(context, ref, session, p),
                          onGo: () => notifier.passGo(p.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _Dock(session: session, onUndo: notifier.undo),
          ],
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.session, required this.onUndo});

  final BankSession session;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Space for the undo bar is always reserved so the cards above
            // never shift while people are tapping.
            SizedBox(
              height: _undoSlotHeight,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: session.undoAvailable
                    ? Align(
                        key: const ValueKey('undo-bar'),
                        alignment: Alignment.center,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  session.lastLabel ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(
                                    color: theme.colorScheme.surface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                key: const ValueKey('undo-button'),
                                onPressed: onUndo,
                                icon: const Icon(LucideIcons.undo2, size: 18),
                                label: const Text('เลิกทำ'),
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.surface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            Container(
              key: const ValueKey('bank-card'),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: theme.brightness == Brightness.dark
                      ? const [Color(0xFF4A5BE0), Color(0xFF2B3181)]
                      : const [Color(0xFF3A4CC0), Color(0xFF16163F)],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D16163F),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.landmark,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'ธนาคาร',
                    style: text.titleLarge?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
