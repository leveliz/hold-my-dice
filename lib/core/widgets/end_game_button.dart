import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/widgets/end_game_icon.dart';

/// "End the game" for an app bar: the flag picture with its word under it.
/// The picture is too fine to read on its own at icon size, so the word says
/// what the button does. Takes its colour from the icon theme of the bar.
class EndGameButton extends StatelessWidget {
  const EndGameButton({super.key, required this.onPressed});

  static const label = 'จบเกม';

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onPressed,
        radius: 32,
        child: SizedBox(
          width: 60,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EndGameIcon(size: 30, color: color),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
