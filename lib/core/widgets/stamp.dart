import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';

/// A rubber-stamp mark: a dashed circle in [color] holding [child], a little
/// off the straight like a stamp pressed by hand.
class Stamp extends StatelessWidget {
  const Stamp({
    super.key,
    required this.color,
    required this.child,
    this.size = 40,
    this.tilt = -12,
  });

  final Color color;
  final Widget child;
  final double size;

  /// Degrees turned from upright.
  final double tilt;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt * math.pi / 180,
      child: SizedBox(
        width: size,
        height: size,
        child: DashedBorder(
          color: color,
          radius: size / 2,
          child: Center(
            child: IconTheme.merge(
              data: IconThemeData(color: color, size: size * 0.5),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
