import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';
import 'package:hold_my_dice/features/bank/domain/transaction.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// What the person chose on the "not enough money" sheet: pay, raising
/// [mortgage] first (null when the cash covers it by now), or go bankrupt.
class ShortfallResult {
  const ShortfallResult.pay(this.mortgage) : bankrupt = false;
  const ShortfallResult.bankrupt() : mortgage = null, bankrupt = true;

  final int? mortgage;
  final bool bankrupt;
}

/// Opens the sheet for a payment of [amount] to the bank ([toSeat] null) or to
/// that seat, which this person cannot cover. Nothing has been charged yet.
Future<ShortfallResult?> showShortfallSheet(
  BuildContext context, {
  required String code,
  required int amount,
  String? toSeat,
}) => showModalBottomSheet<ShortfallResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ShortfallSheet(code: code, amount: amount, toSeat: toSeat),
);

/// The "not enough money" sheet of a room: mortgage properties until the live
/// total covers what is missing (and leaves no more over than a fifth of the
/// starting cash) and pay in one step, or go bankrupt. The cash is read live:
/// money that arrives while the sheet is open counts.
class ShortfallSheet extends ConsumerStatefulWidget {
  const ShortfallSheet({
    super.key,
    required this.code,
    required this.amount,
    this.toSeat,
  });

  final String code;
  final int amount;
  final String? toSeat;

  @override
  ConsumerState<ShortfallSheet> createState() => _ShortfallSheetState();
}

class _ShortfallSheetState extends ConsumerState<ShortfallSheet> {
  final _mortgages = <int>[];
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final value = parseMoney(_input.text) ?? 0;
    if (value <= 0) return;
    setState(() {
      _mortgages.add(value);
      _input.clear();
    });
  }

  Future<void> _goBankrupt(String payee, int cash) async {
    final toBank = widget.toSeat == null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('bankrupt-dialog'),
        title: Text(
          'ล้มละลาย?',
          style: serifStyle(Theme.of(context).textTheme.headlineSmall),
        ),
        content: Text(
          'ต้องจ่าย ${formatMoney(widget.amount)} · มี ${formatMoney(cash)}\n'
          '${toBank ? 'ออกจากเกม เงินที่เหลือ ${formatMoney(cash)} คืนธนาคาร' : 'ออกจากเกม $payee ได้รับ ${formatMoney(widget.amount)} ครบ ธนาคารจ่ายส่วนต่าง'}\n'
          'ดูเกมต่อได้ แต่กดเงินไม่ได้ และย้อนกลับไม่ได้',
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('bankrupt-cancel'),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(LucideIcons.x),
            label: const Text('กลับไปก่อน'),
          ),
          FilledButton.icon(
            key: const ValueKey('bankrupt-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(LucideIcons.logOut),
            label: const Text('ล้มละลาย'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context, const ShortfallResult.bankrupt());
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(roomGameProvider(widget.code)).value;
    if (view == null) return const SizedBox(height: 120);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);
    final amount = widget.amount;
    final payee = widget.toSeat == null
        ? 'ธนาคาร'
        : view.nameOf(widget.toSeat!);
    final cash = view.myBalance ?? 0;
    final covered = cash >= amount;
    final shortfall = amount - cash;
    final total = covered ? 0 : _mortgages.fold(0, (a, b) => a + b);
    final left = cash + total - amount;
    final cap = view.settings.startingCash ~/ 5;
    final bank = view.balances[Transaction.bank];
    final bankShort = !covered && bank != null && bank < total;
    final tooMuch = !covered && total >= shortfall && left > cap;
    final enough = covered || (total >= shortfall && left <= cap && !bankShort);
    final canGoBankrupt =
        amount <= maxOwedTimesStartingCash * view.settings.startingCash;

    String status;
    Color statusColor;
    if (covered) {
      status = 'ตอนนี้เงินพอจ่ายแล้ว ไม่ต้องจำนอง';
      statusColor = const Color(0xFF10A15F);
    } else if (bankShort) {
      status = 'ธนาคารมีเงินไม่พอให้จำนองยอดนี้';
      statusColor = scheme.error;
    } else if (tooMuch) {
      status =
          'จำนองเกินไป เหลือ ${formatMoney(left)} เกินเพดาน ${formatMoney(cap)}';
      statusColor = scheme.error;
    } else if (total < shortfall) {
      status = 'ยังขาดอีก ${formatMoney(shortfall - total)}';
      statusColor = scheme.error;
    } else {
      status = 'พอจ่ายแล้ว เหลือ ${formatMoney(left)}';
      statusColor = const Color(0xFF10A15F);
    }

    return Padding(
      key: const ValueKey('shortfall-sheet'),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('เงินไม่พอ', style: serifStyle(text.titleLarge)),
                ),
                if (!covered)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'ขาด ${formatMoney(shortfall)}',
                      key: const ValueKey('shortfall-missing'),
                      style: text.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'จ่าย$payee ${formatMoney(amount)} · มีอยู่ ${formatMoney(cash)}',
              key: const ValueKey('shortfall-owed'),
              style: text.bodyMedium?.copyWith(color: muted),
            ),
            if (!covered) ...[
              const SizedBox(height: 12),
              for (final (i, m) in _mortgages.indexed)
                Row(
                  key: ValueKey('mortgage-row-$i'),
                  children: [
                    Expanded(
                      child: Text('แปลงที่ ${i + 1}', style: text.titleMedium),
                    ),
                    Text(
                      '+${formatMoney(m)}',
                      key: ValueKey('mortgage-amount-$i'),
                      style: text.titleMedium,
                    ),
                    IconButton(
                      key: ValueKey('mortgage-remove-$i'),
                      tooltip: 'ลบแปลงที่ ${i + 1}',
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => setState(() => _mortgages.removeAt(i)),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'เหลือหลังจ่ายได้ไม่เกิน ${formatMoney(cap)}',
                  key: const ValueKey('mortgage-cap'),
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('mortgage-input'),
                      controller: _input,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [ThousandsFormatter()],
                      style: text.titleMedium,
                      decoration: const InputDecoration(
                        hintText: 'ยอดจำนองแปลงนี้',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    key: const ValueKey('mortgage-add'),
                    onPressed: (parseMoney(_input.text) ?? 0) > 0 ? _add : null,
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('เพิ่ม'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('mortgage-status'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    enough ? LucideIcons.check : LucideIcons.info,
                    color: statusColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      covered
                          ? status
                          : 'รวมจำนอง ${formatMoney(total)} · $status',
                      key: const ValueKey('mortgage-total'),
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('mortgage-confirm'),
              onPressed: enough
                  ? () => Navigator.pop(
                      context,
                      ShortfallResult.pay(covered ? null : total),
                    )
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(LucideIcons.handCoins),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('จ่าย ${formatMoney(amount)}', maxLines: 1),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('bankrupt-button'),
              onPressed: canGoBankrupt && !covered
                  ? () => _goBankrupt(payee, cash)
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: scheme.error,
                side: BorderSide(
                  color: scheme.error.withValues(
                    alpha: canGoBankrupt && !covered ? 1 : 0.3,
                  ),
                ),
              ),
              icon: const Icon(LucideIcons.logOut),
              label: const Text('ล้มละลาย'),
            ),
            if (!canGoBankrupt && !covered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'หนี้เกิน 10 เท่าของเงินเริ่มต้น ล้มละลายไม่ได้',
                  key: const ValueKey('bankrupt-too-big'),
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
