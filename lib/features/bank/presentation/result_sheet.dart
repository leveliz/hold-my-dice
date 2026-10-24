import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';

class BalanceLine {
  const BalanceLine(this.player, this.balance);

  final Player player;
  final int balance;
}

/// Shown after a transaction is confirmed: the new balance of everyone
/// involved (one player, or both sides of a transfer) and a close button.
Future<void> showResultSheet(
  BuildContext context, {
  required String title,
  required List<BalanceLine> lines,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ResultSheet(title: title, lines: lines),
  );
}

class ResultSheet extends StatelessWidget {
  const ResultSheet({super.key, required this.title, required this.lines});

  final String title;
  final List<BalanceLine> lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const ValueKey('result-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'ยอดคงเหลือ',
              style: text.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 14),
            for (final line in lines) ...[
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Color(line.player.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line.player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  BalanceChip(
                    key: ValueKey('result-balance-${line.player.id}'),
                    amount: line.balance,
                    accent: Color(line.player.color),
                    style: text.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 4),
            FilledButton(
              key: const ValueKey('result-close'),
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: text.titleLarge,
              ),
              child: const Text('ปิด'),
            ),
          ],
        ),
      ),
    );
  }
}
