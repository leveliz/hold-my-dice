import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/widgets/dither.dart';

/// The page ground. Light: white fading into pale blue. Dark: midnight lit by
/// three soft blooms (Aurora Glow), drawn as radial gradients so nothing needs
/// a blur. Every page paints its own so pages stay opaque while they slide.
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Palette.skyTop, Palette.skyBottom],
          ),
        ),
        child: child,
      );
    }
    return ColoredBox(
      color: Palette.night,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: _AuroraBlooms()),
          child,
        ],
      ),
    );
  }
}

class _AuroraBlooms extends StatelessWidget {
  const _AuroraBlooms();

  static Widget _bloom(Alignment at, double radius, Color color, double alpha) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: at,
            radius: radius,
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('aurora-blooms'),
      fit: StackFit.expand,
      children: [
        _bloom(const Alignment(-0.8, -0.84), 1.0, Palette.auroraIndigo, 0.5),
        _bloom(const Alignment(1.0, -0.2), 0.72, Palette.auroraMagenta, 0.34),
        _bloom(const Alignment(-0.1, 1.1), 1.1, Palette.auroraEmerald, 0.36),
        const Positioned.fill(child: DitherOverlay()),
      ],
    );
  }
}
