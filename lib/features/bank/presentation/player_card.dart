import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/tint_button.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A player's card. [compact] is a single row for crowded tables; otherwise
/// the name and balance sit above a row of buttons.
class PlayerCard extends StatelessWidget {
  const PlayerCard({
    super.key,
    required this.player,
    required this.balance,
    required this.compact,
    required this.onReceive,
    required this.onPay,
    required this.onGo,
  });

  final Player player;
  final int balance;
  final bool compact;
  final VoidCallback onReceive;
  final VoidCallback onPay;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Color(player.color);

    Widget dot() => Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
    );

    Widget name() => Text(
      player.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text.titleMedium,
    );

    Widget money(TextStyle? style) => Text(
      formatMoney(balance),
      key: ValueKey('balance-${player.id}'),
      style: style?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    Widget plus() => TintButton(
      key: ValueKey('btn-plus-${player.id}'),
      accent: accent,
      semanticLabel: 'รับจากธนาคาร ${player.name}',
      onPressed: onReceive,
      child: const Icon(LucideIcons.plus),
    );
    Widget minus() => TintButton(
      key: ValueKey('btn-minus-${player.id}'),
      accent: accent,
      semanticLabel: 'จ่ายธนาคาร ${player.name}',
      onPressed: onPay,
      child: const Icon(LucideIcons.minus),
    );
    Widget go() => TintButton(
      key: ValueKey('btn-go-${player.id}'),
      accent: accent,
      semanticLabel: 'ผ่านจุดเริ่ม ${player.name}',
      onPressed: onGo,
      child: const Text('GO'),
    );

    return GradientCard(
      key: ValueKey('player-card-${player.id}'),
      accent: accent,
      radius: compact ? 20 : 28,
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : const EdgeInsets.all(14),
        child: compact
            ? Row(
                children: [
                  dot(),
                  const SizedBox(width: 8),
                  Expanded(child: name()),
                  const SizedBox(width: 8),
                  money(text.titleLarge),
                  const SizedBox(width: 10),
                  SizedBox(width: 44, height: 52, child: plus()),
                  const SizedBox(width: 6),
                  SizedBox(width: 44, height: 52, child: minus()),
                  const SizedBox(width: 6),
                  SizedBox(width: 52, height: 52, child: go()),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      dot(),
                      const SizedBox(width: 8),
                      Expanded(child: name()),
                      money(text.headlineMedium),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 46,
                    child: Row(
                      children: [
                        Expanded(child: plus()),
                        const SizedBox(width: 8),
                        Expanded(child: minus()),
                        const SizedBox(width: 8),
                        Expanded(child: go()),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
