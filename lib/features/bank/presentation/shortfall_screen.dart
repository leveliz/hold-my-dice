import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A payment the payer cannot cover. [payeeId] is the bank or a player.
class ShortfallArgs {
  const ShortfallArgs({
    required this.payerId,
    required this.payeeId,
    required this.amount,
  });

  final String payerId;
  final String payeeId;
  final int amount;
}

enum ShortfallOutcome { paid, bankrupt }

/// The "not enough money" page: nothing has been charged yet. The payer can
/// mortgage properties until the live total covers the shortfall and pay in
/// one step, or go bankrupt.
class ShortfallScreen extends ConsumerStatefulWidget {
  const ShortfallScreen({super.key, required this.args});

  final ShortfallArgs args;

  @override
  ConsumerState<ShortfallScreen> createState() => _ShortfallScreenState();
}

class _ShortfallScreenState extends ConsumerState<ShortfallScreen> {
  final _mortgages = <int>[];
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _toBank => widget.args.payeeId == Transaction.bank;

  void _addMortgage() {
    final value = parseMoney(_input.text) ?? 0;
    if (value <= 0) return;
    setState(() {
      _mortgages.add(value);
      _input.clear();
    });
  }

  void _payWithMortgage() {
    final a = widget.args;
    final result = ref
        .read(bankProvider.notifier)
        .payWithMortgage(
          payerId: a.payerId,
          payeeId: a.payeeId,
          amount: a.amount,
          mortgages: _mortgages,
        );
    if (result is Paid) context.pop(ShortfallOutcome.paid);
  }

  Future<void> _goBankrupt(String payerName, String payeeName, int cash) async {
    final a = widget.args;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('bankrupt-dialog'),
        title: Text('$payerName ล้มละลาย?'),
        content: Text(
          _toBank
              ? 'ออกจากเกม เงินที่เหลือ ${formatMoney(cash)} คืนธนาคาร'
              : 'ออกจากเกม $payeeName ได้รับ ${formatMoney(a.amount)} ครบ '
                    'ธนาคารจ่ายส่วนต่าง',
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('bankrupt-cancel'),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(LucideIcons.x),
            label: const Text('ยกเลิก'),
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
    ref
        .read(bankProvider.notifier)
        .declareBankrupt(
          a.payerId,
          owed: a.amount,
          creditorId: _toBank ? null : a.payeeId,
        );
    context.pop(ShortfallOutcome.bankrupt);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(bankProvider);
    if (session == null) return const Scaffold();
    final a = widget.args;
    final game = session.game;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);

    final payer = game.players.firstWhere((p) => p.id == a.payerId);
    final payeeName = _toBank
        ? 'ธนาคาร'
        : game.players.firstWhere((p) => p.id == a.payeeId).name;
    final cash = game.balanceOf(a.payerId);
    final shortfall = a.amount - cash;
    final mortgageTotal = _mortgages.fold(0, (sum, m) => sum + m);
    final remaining = shortfall - mortgageTotal;
    final enough = remaining <= 0;
    final accent = Color(payer.color);
    final dark = theme.brightness == Brightness.dark;
    final tile = dark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.07), scheme.surface)
        : Colors.white;

    Widget labelled(String label, Widget chip) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: chip),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const Text('เงินไม่พอ')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  GradientCard(
                    key: const ValueKey('shortfall-summary'),
                    accent: accent,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                  payer.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ต้องจ่าย ${formatMoney(a.amount)} ให้$payeeName',
                            key: const ValueKey('shortfall-owed'),
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              labelled(
                                'มีเงินอยู่',
                                BalanceChip(
                                  key: const ValueKey('shortfall-cash'),
                                  amount: cash,
                                  accent: accent,
                                ),
                              ),
                              labelled(
                                'ยอดที่ขาด',
                                BalanceChip(
                                  key: const ValueKey('shortfall-amount'),
                                  amount: shortfall,
                                  accent: scheme.error,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'จำนอง (ใส่ยอดทีละแปลง)',
                      style: text.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                  for (final (i, m) in _mortgages.indexed) ...[
                    Container(
                      key: ValueKey('mortgage-row-$i'),
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      decoration: BoxDecoration(
                        color: tile,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'แปลงที่ ${i + 1}',
                              style: text.titleMedium,
                            ),
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
                            onPressed: () =>
                                setState(() => _mortgages.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: tile,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: TextField(
                            key: const ValueKey('mortgage-input'),
                            controller: _input,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [ThousandsFormatter()],
                            style: text.titleLarge,
                            decoration: InputDecoration(
                              hintText: 'ยอดจำนองแปลงนี้',
                              hintStyle: text.bodyLarge?.copyWith(color: muted),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _addMortgage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.tonalIcon(
                        key: const ValueKey('mortgage-add'),
                        onPressed: (parseMoney(_input.text) ?? 0) > 0
                            ? _addMortgage
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(72, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(LucideIcons.plus),
                        label: const Text('เพิ่ม'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    key: const ValueKey('mortgage-status'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (enough ? Colors.green : scheme.error).withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          enough ? LucideIcons.check : LucideIcons.info,
                          color: enough ? Colors.green : scheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'จำนองรวม ${formatMoney(mortgageTotal)}',
                            key: const ValueKey('mortgage-total'),
                            style: text.titleMedium,
                          ),
                        ),
                        Text(
                          enough
                              ? 'พอจ่ายแล้ว'
                              : 'ยังขาดอีก ${formatMoney(remaining)}',
                          key: const ValueKey('mortgage-remaining'),
                          style: text.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  FilledButton.icon(
                    key: const ValueKey('mortgage-confirm'),
                    onPressed: enough ? _payWithMortgage : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      textStyle: text.titleLarge,
                    ),
                    icon: const Icon(LucideIcons.handCoins),
                    label: const Text('จำนองและจ่าย'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('bankrupt-button'),
                    onPressed: () => _goBankrupt(payer.name, payeeName, cash),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      textStyle: text.titleMedium,
                    ),
                    icon: const Icon(LucideIcons.logOut),
                    label: const Text('ล้มละลาย'),
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
