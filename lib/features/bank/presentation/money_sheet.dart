import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/tour/tour_host.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/core/widgets/key_tile.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:hold_my_dice/features/bank/presentation/transfer_pair.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MoneyResult {
  const MoneyResult(this.amount, {this.mortgage = false, this.reason});

  final int amount;
  final bool mortgage;

  /// Why the money moves; null when the sheet did not ask.
  final String? reason;
}

/// Asks for a required reason on the sheet: a text field with quick [chips]
/// that fill it, and an optional [formatter] that bounds what is typed.
class ReasonOptions {
  const ReasonOptions({required this.chips, this.formatter});

  final List<String> chips;
  final TextInputFormatter? formatter;
}

/// Opens the amount entry sheet. [isPay] is the "−" flow; the "+" flow lets
/// the player switch between receiving from the bank and mortgaging (unless
/// [allowMortgage] is off). With a [recipient] it is a transfer from [player].
Future<MoneyResult?> showMoneySheet(
  BuildContext context, {
  required Player player,
  required int balance,
  required bool isPay,
  required List<int> recent,
  Player? recipient,
  bool allowMortgage = true,
  ReasonOptions? reason,
  TourStorage? tourStorage,
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
      recipient: recipient,
      allowMortgage: allowMortgage,
      reason: reason,
      tourStorage: tourStorage,
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
    this.recipient,
    this.allowMortgage = true,
    this.reason,
    this.tourStorage,
  });

  final Player player;
  final int balance;
  final bool isPay;
  final List<int> recent;
  final Player? recipient;
  final bool allowMortgage;

  /// When given, the sheet will not close with an amount until a reason is typed.
  final ReasonOptions? reason;

  /// Where the first-run tip is remembered; null means no tip.
  final TourStorage? tourStorage;

  @override
  State<MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<MoneySheet> with TourHost<MoneySheet> {
  static const _maxDigits = 9;

  var _digits = '';
  var _mortgage = false;
  final _reason = TextEditingController();

  final _zeroKey = GlobalKey();
  final _recentKey = GlobalKey();
  final _kindKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.tourStorage case final tours?) {
      offerTour(
        storage: tours,
        id: TourIds.bankMoneyTip,
        steps: () => [
          TourStep(
            title: 'ใส่เงินให้เร็วขึ้น',
            body: widget.recent.isEmpty
                ? 'ปุ่ม 000 ใส่ศูนย์สามตัวในปุ่มเดียว เช่น 15 แล้วกด 000 ได้ 15,000'
                : 'ปุ่ม 000 ใส่ศูนย์สามตัวในปุ่มเดียว เช่น 15 แล้วกด 000 ได้ 15,000 ส่วนแถวด้านบนคือยอดที่เพิ่งใช้ แตะเพื่อใช้ซ้ำ',
            target: _zeroKey,
            destination: widget.recent.isEmpty ? null : _recentKey,
          ),
          // On screen only when receiving with mortgage allowed; a step whose
          // spot is missing is left out of the tour.
          TourStep(
            title: 'จำนอง',
            body:
                'เลือก "จำนอง" เมื่อรับเงินจากการจำนอง ไม่ต้องบอกว่าที่ดินแปลงไหน',
            target: _kindKey,
          ),
        ],
      );
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _reasonOk => widget.reason == null || _reason.text.trim().isNotEmpty;

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
      return KeyTile(
        inkKey: k,
        onTap: onTap ?? () => _type(label),
        child: child ?? Text(label, style: text.headlineSmall),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        // Room for the keyboard, so the keypad stays in reach while typing.
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.recipient case final to?)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'โอนเงิน',
                    key: const ValueKey('sheet-transfer-title'),
                    style: headingStyle(context, text.titleMedium),
                  ),
                  const SizedBox(height: 8),
                  TransferPair(
                    key: const ValueKey('transfer-pair'),
                    from: widget.player,
                    to: to,
                    center: true,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Text(
                    widget.isPay ? 'จ่ายธนาคาร' : 'รับเงิน',
                    key: const ValueKey('sheet-kind-label'),
                    style: headingStyle(context, text.titleMedium),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        key: const ValueKey('sheet-player'),
                        mainAxisSize: MainAxisSize.min,
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
                          Flexible(
                            child: Text(
                              widget.player.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            if (!widget.isPay && widget.allowMortgage) ...[
              const SizedBox(height: 10),
              KeyedSubtree(
                key: _kindKey,
                child: SegmentedButton<bool>(
                  key: const ValueKey('sheet-kind'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(LucideIcons.landmark),
                      label: Text('รับจากธนาคาร'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(LucideIcons.handCoins),
                      label: Text('จำนอง'),
                    ),
                  ],
                  selected: {_mortgage},
                  onSelectionChanged: (s) =>
                      setState(() => _mortgage = s.first),
                ),
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
              KeyedSubtree(
                key: _recentKey,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final r in widget.recent)
                      ActionChip(
                        key: ValueKey('recent-$r'),
                        avatar: const Icon(LucideIcons.history, size: 18),
                        label: Text('ล่าสุด ${formatMoney(r)}'),
                        onPressed: () => setState(() => _digits = '$r'),
                      ),
                  ],
                ),
              ),
            ],
            if (widget.reason case final options?) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('sheet-reason'),
                controller: _reason,
                inputFormatters: [?options.formatter],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'เหตุผล',
                  hintText: 'ต้องมีเหตุผลก่อนรับเงินจากธนาคาร',
                  isDense: true,
                ),
              ),
              if (options.chips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in options.chips)
                      ActionChip(
                        key: ValueKey('reason-chip-$c'),
                        label: Text(c),
                        onPressed: () => setState(() => _reason.text = c),
                      ),
                  ],
                ),
              ],
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
                KeyedSubtree(
                  key: _zeroKey,
                  child: key('000', k: const ValueKey('key-000')),
                ),
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
            FilledButton.icon(
              key: const ValueKey('sheet-ok'),
              onPressed: _amount > 0 && _reasonOk
                  ? () => Navigator.pop(
                      context,
                      MoneyResult(
                        _amount,
                        mortgage: _mortgage,
                        reason: widget.reason == null
                            ? null
                            : _reason.text.trim(),
                      ),
                    )
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: text.titleLarge,
              ),
              icon: const Icon(LucideIcons.check),
              label: const Text('ตกลง'),
            ),
          ],
        ),
      ),
    );
  }
}
