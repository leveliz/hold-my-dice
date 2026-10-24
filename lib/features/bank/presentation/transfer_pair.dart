import 'package:flutter/material.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// "● ผู้เล่น 1  ⇄  ● ผู้เล่น 2": who pays and who receives in one row, with
/// a transfer icon and a small grey "โอนให้" caption between the two names.
class TransferPair extends StatelessWidget {
  const TransferPair({
    super.key,
    required this.from,
    required this.to,
    this.center = false,
  });

  final Player from;
  final Player to;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    Widget who(Player p) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Color(p.color),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge,
          ),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Flexible(child: who(from)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'โอนให้',
                style: text.bodySmall?.copyWith(color: muted, fontSize: 12),
              ),
              Icon(LucideIcons.arrowRightLeft, size: 20, color: muted),
            ],
          ),
        ),
        Flexible(child: who(to)),
      ],
    );
  }
}
