import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/paper_style.dart';

/// A player's colour as a circle holding the first letter of their name, so
/// people can be told apart without reading. A numbered name such as the
/// default "ผู้เล่น 3" shows its number, since every first letter would match.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 32,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final paper = PaperStyle.maybeOf(context) != null;
    final trimmed = name.trim();
    final number = RegExp(r'\s(\d{1,2})$').firstMatch(trimmed)?.group(1);
    final initial = number ?? (trimmed.isEmpty ? '' : trimmed.characters.first);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          // On paper the circle is a stamp: an ivory gap, then a ring.
          border: paper ? Border.all(color: PaperStyle.card, width: 2) : null,
          boxShadow: paper
              ? [BoxShadow(color: color, spreadRadius: 1.5)]
              : null,
        ),
        child: Text(
          initial,
          maxLines: 1,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: onColor,
            fontSize: size * 0.5,
            height: 1,
          ),
        ),
      ),
    );
  }
}
