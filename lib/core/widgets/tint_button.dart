import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';

/// A small button for a player's card: tinted in Aurora, dashed-outlined on
/// paper, in [accent] either way.
class TintButton extends StatelessWidget {
  const TintButton({
    super.key,
    required this.accent,
    required this.onPressed,
    required this.child,
    this.semanticLabel,
  });

  final Color accent;
  final VoidCallback onPressed;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = PaperStyle.maybeOf(context) != null;
    final fill = paper
        ? Color.alphaBlend(accent.withValues(alpha: 0.08), PaperStyle.card)
        : Color.alphaBlend(
            accent.withValues(alpha: 0.5),
            theme.colorScheme.surface,
          );
    final radius = paper ? 5.0 : 14.0;
    final tap = InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onPressed,
      child: Center(
        child: DefaultTextStyle.merge(
          style: theme.textTheme.titleMedium,
          child: IconTheme.merge(
            data: IconThemeData(color: theme.colorScheme.onSurface, size: 22),
            child: child,
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        // Papery buttons are outlined with a dashed line in the player's colour.
        child: paper
            ? DashedBorder(
                color: accent,
                radius: radius,
                strokeWidth: 1.5,
                child: tap,
              )
            : tap,
      ),
    );
  }
}
