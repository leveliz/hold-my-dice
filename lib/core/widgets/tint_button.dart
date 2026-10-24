import 'package:flutter/material.dart';

/// A small rounded button tinted with [accent], meant to sit on a
/// [GradientCard] of the same accent.
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
    final dark = theme.brightness == Brightness.dark;
    final fill = dark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.5),
            theme.colorScheme.surface,
          )
        : Color.alphaBlend(accent.withValues(alpha: 0.26), Colors.white);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Center(
            child: DefaultTextStyle.merge(
              style: theme.textTheme.titleMedium,
              child: IconTheme.merge(
                data: IconThemeData(
                  color: theme.colorScheme.onSurface,
                  size: 22,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
