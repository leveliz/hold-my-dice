import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:hold_my_dice/features/bank/presentation/transfer_pair.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class BalanceLine {
  const BalanceLine(this.player, this.balance);

  final Player player;
  final int balance;
}

/// A transfer between two players, shown as "ผู้เล่น 1 ⇄ ผู้เล่น 2" with the
/// amount on the next line instead of a one-line title.
class TransferInfo {
  const TransferInfo({
    required this.from,
    required this.to,
    required this.amount,
  });

  final Player from;
  final Player to;
  final int amount;
}

/// Shown after a transaction is confirmed: the new balance of everyone
/// involved (one player, or both sides of a transfer) and a close button.
Future<void> showResultSheet(
  BuildContext context, {
  required String title,
  required List<BalanceLine> lines,
  TransferInfo? transfer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ResultSheet(title: title, lines: lines, transfer: transfer),
  );
}

class ResultSheet extends StatelessWidget {
  const ResultSheet({
    super.key,
    required this.title,
    required this.lines,
    this.transfer,
  });

  final String title;
  final List<BalanceLine> lines;
  final TransferInfo? transfer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const ValueKey('result-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (transfer case final t?) ...[
              TransferPair(
                key: const ValueKey('result-transfer'),
                from: t.from,
                to: t.to,
                center: true,
              ),
              const SizedBox(height: 8),
              Text(
                'ยอดโอน ${formatMoney(t.amount)}',
                key: const ValueKey('result-transfer-amount'),
                style: text.titleMedium,
              ),
            ] else
              Text(title, textAlign: TextAlign.center, style: text.titleMedium),
            const SizedBox(height: 4),
            Text('ยอดคงเหลือ', style: text.bodyMedium?.copyWith(color: muted)),
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
            FilledButton.icon(
              key: const ValueKey('result-close'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(LucideIcons.x),
              label: const Text('ปิด'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: text.titleLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
