import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
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
    required this.onTap,
    this.bankrupt = false,
    this.hideBalance = false,
    this.buttonsKey,
  });

  static double radiusFor({required bool compact}) => compact ? 20 : 28;

  final Player player;
  final int balance;
  final bool compact;
  final VoidCallback onReceive;
  final VoidCallback onPay;
  final VoidCallback onGo;

  /// Tapping the card itself starts a transfer.
  final VoidCallback onTap;

  /// A bankrupt player is out of the game: shown dimmed, no actions.
  final bool bankrupt;

  /// Shows dots instead of the balance, for a phone left in the middle of
  /// the table.
  final bool hideBalance;

  /// Marks the row of + − GO, for the first-run tour to point at.
  final GlobalKey? buttonsKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Color(player.color);

    Widget avatar(double size) =>
        PlayerAvatar(name: player.name, color: accent, size: size);

    Widget name() => Text(
      player.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: text.titleMedium,
    );

    Widget money(TextStyle? style) => Text(
      hideBalance ? '••••' : formatMoney(balance),
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

    if (bankrupt) {
      return Opacity(
        opacity: 0.55,
        child: GradientCard(
          key: ValueKey('player-card-${player.id}'),
          accent: Colors.grey,
          radius: radiusFor(compact: compact),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: name()),
                Text(
                  'ล้มละลาย',
                  key: ValueKey('bankrupt-${player.id}'),
                  style: text.titleMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GradientCard(
      key: ValueKey('player-card-${player.id}'),
      accent: accent,
      radius: radiusFor(compact: compact),
      onTap: onTap,
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : const EdgeInsets.all(14),
        child: compact
            ? Row(
                children: [
                  avatar(32),
                  const SizedBox(width: 8),
                  Expanded(child: name()),
                  const SizedBox(width: 8),
                  money(text.titleLarge),
                  const SizedBox(width: 10),
                  Row(
                    key: buttonsKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 44, height: 52, child: plus()),
                      const SizedBox(width: 6),
                      SizedBox(width: 44, height: 52, child: minus()),
                      const SizedBox(width: 6),
                      SizedBox(width: 52, height: 52, child: go()),
                    ],
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      avatar(36),
                      const SizedBox(width: 8),
                      Expanded(child: name()),
                      money(text.headlineMedium),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    key: buttonsKey,
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
