import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/widgets/dither.dart';

/// The page ground. Light (Papery): warm paper with a faint dotted grain.
/// Dark (Aurora Glow): midnight lit by three soft blooms, drawn as radial
/// gradients so nothing needs a blur. Every page paints its own so pages stay
/// opaque while they slide.
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return ColoredBox(
        color: PaperStyle.paper,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(child: _PaperGrain()),
            child,
          ],
        ),
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

/// Faint dots on a 14-pixel grid, like the grain of craft paper.
class _PaperGrain extends StatelessWidget {
  const _PaperGrain();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      key: ValueKey('paper-grain'),
      painter: _GrainPainter(),
      size: Size.infinite,
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  static const spacing = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      for (var y = spacing / 2; y < size.height; y += spacing)
        for (var x = spacing / 2; x < size.width; x += spacing) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = PaperStyle.grain
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}
