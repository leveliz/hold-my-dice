import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/format.dart';

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

/// An amount of money on a light tint of [accent], outlined in a deeper shade
/// of the same colour.
class BalanceChip extends StatelessWidget {
  const BalanceChip({
    super.key,
    required this.amount,
    required this.accent,
    this.style,
  });

  final int amount;
  final Color accent;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: dark ? 0.3 : 0.16),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? accent : _darken(accent, 0.22),
          width: 1.5,
        ),
      ),
      child: Text(
        formatMoney(amount),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (style ?? theme.textTheme.titleLarge)?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
