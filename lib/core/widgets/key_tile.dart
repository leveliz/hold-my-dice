import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/paper_style.dart';

/// One key of a number pad. On paper an ivory tile with a thin edge and a
/// sheet under it; in Aurora a faint rounded panel. Touches land on the
/// [InkWell], which carries [inkKey].
class KeyTile extends StatelessWidget {
  const KeyTile({
    super.key,
    this.inkKey,
    required this.onTap,
    required this.child,
  });

  final Key? inkKey;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final paper = PaperStyle.maybeOf(context) != null;
    final radius = BorderRadius.circular(paper ? 6 : 16);
    final tap = InkWell(
      key: inkKey,
      borderRadius: radius,
      onTap: onTap,
      child: Center(child: child),
    );
    if (paper) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: PaperStyle.card,
          borderRadius: radius,
          border: Border.all(color: PaperStyle.edge),
          boxShadow: const [
            BoxShadow(color: PaperStyle.sheetFar, offset: Offset(0, 2)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          child: tap,
        ),
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
      borderRadius: radius,
      child: tap,
    );
  }
}
