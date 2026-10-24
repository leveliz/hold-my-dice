import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MoneyResult {
  const MoneyResult(this.amount, {this.mortgage = false});

  final int amount;
  final bool mortgage;
}

/// Opens the amount entry sheet. [isPay] is the "−" flow; the "+" flow lets
/// the player switch between receiving from the bank and mortgaging.
Future<MoneyResult?> showMoneySheet(
  BuildContext context, {
  required Player player,
  required int balance,
  required bool isPay,
  required List<int> recent,
}) {
  return showModalBottomSheet<MoneyResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => MoneySheet(
      player: player,
      balance: balance,
      isPay: isPay,
      recent: recent,
    ),
  );
}

class MoneySheet extends StatefulWidget {
  const MoneySheet({
    super.key,
    required this.player,
    required this.balance,
    required this.isPay,
    required this.recent,
  });

  final Player player;
  final int balance;
  final bool isPay;
  final List<int> recent;

  @override
  State<MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<MoneySheet> {
  static const _maxDigits = 9;

  var _digits = '';
  var _mortgage = false;

  int get _amount => _digits.isEmpty ? 0 : int.parse(_digits);

  void _type(String s) {
    final next = _digits + s;
    if (next.length > _maxDigits) return;
    setState(() => _digits = int.parse(next) == 0 ? '' : next);
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);
    final accent = Color(widget.player.color);

    Widget key(String label, {Key? k, VoidCallback? onTap, Widget? child}) {
      return Material(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: k,
          borderRadius: BorderRadius.circular(16),
          onTap: onTap ?? () => _type(label),
          child: Center(child: child ?? Text(label, style: text.headlineSmall)),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isPay ? 'จ่ายธนาคาร' : 'รับเงิน',
                  style: text.titleMedium,
                ),
              ],
            ),
            if (!widget.isPay) ...[
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                key: const ValueKey('sheet-kind'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('รับจากธนาคาร')),
                  ButtonSegment(value: true, label: Text('จำนอง')),
                ],
                selected: {_mortgage},
                onSelectionChanged: (s) => setState(() => _mortgage = s.first),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              key: const ValueKey('sheet-amount'),
              formatMoney(_amount),
              style: text.displayMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'ยอดเงินคงเหลือปัจจุบัน',
              key: const ValueKey('sheet-balance-label'),
              style: text.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            BalanceChip(
              key: const ValueKey('sheet-balance-chip'),
              amount: widget.balance,
              accent: accent,
            ),
            if (widget.recent.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in widget.recent)
                    ActionChip(
                      key: ValueKey('recent-$r'),
                      label: Text('ล่าสุด ${formatMoney(r)}'),
                      onPressed: () => setState(() => _digits = '$r'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
              children: [
                for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                  key(d, k: ValueKey('key-$d')),
                key('000', k: const ValueKey('key-000')),
                key('0', k: const ValueKey('key-0')),
                key(
                  '',
                  k: const ValueKey('key-back'),
                  onTap: _backspace,
                  child: const Icon(LucideIcons.delete),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('sheet-ok'),
              onPressed: _amount > 0
                  ? () => Navigator.pop(
                      context,
                      MoneyResult(_amount, mortgage: _mortgage),
                    )
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: text.titleLarge,
              ),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      ),
    );
  }
}
