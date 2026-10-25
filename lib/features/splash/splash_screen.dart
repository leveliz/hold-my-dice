import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _totalDuration = Duration(milliseconds: 3000);
const _fallEnd = 0.30;
const _rollMid = 0.46;
const _rollEnd = 0.72;

/// Faces flicker past while the die is in the air, then it lands on a six.
const _airFaces = [3, 1, 4, 2, 5];
const _faceStep = _fallEnd / 5;

/// A die is thrown in from the top-left corner, lands once and rolls to rest
/// in the middle of the screen, then the title fades in and we move on to the
/// hub.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _totalDuration,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final die = math.min(box.maxWidth * 0.26, 120.0);
            final landDx = -box.maxWidth * 0.30;
            final midDx = landDx * 0.37;
            final startDx = -box.maxWidth * 0.65;
            final startDy = -(box.maxHeight / 2 + die);
            // A square die turns a quarter turn per side-length rolled.
            double rollAngle(double dx) => dx / die * math.pi / 2;

            double span(double a, double b) =>
                ((_controller.value - a) / (b - a)).clamp(0.0, 1.0);
            final fallT = const Cubic(
              .4,
              0,
              .8,
              .55,
            ).transform(span(0, _fallEnd));
            final roll1T = span(_fallEnd, _rollMid);
            final roll2T = const Cubic(
              .2,
              .6,
              .4,
              1,
            ).transform(span(_rollMid, _rollEnd));

            final double dx, dy, angle;
            if (_controller.value < _fallEnd) {
              dx = _lerp(startDx, landDx, fallT);
              dy = _lerp(startDy, 0, fallT);
              angle = _lerp(-7.3, rollAngle(landDx), fallT);
            } else if (_controller.value < _rollMid) {
              dx = _lerp(landDx, midDx, roll1T);
              dy = 0;
              angle = rollAngle(dx);
            } else {
              dx = _lerp(midDx, 0, roll2T);
              dy = 0;
              angle = rollAngle(dx);
            }

            final titleT = Curves.easeOut.transform(span(0.68, 0.85));
            // Width of the die's silhouette: a corner-down die is wider and
            // sits higher, so it rolls along its corners instead of sinking.
            final footprint = math.cos(angle).abs() + math.sin(angle).abs();
            final lift = die / 2 * (footprint - 1) * fallT;
            final shadowScale = _lerp(0.3, 1, fallT);
            final shadowOpacity = _lerp(0.15, 1, fallT);
            final faceIndex = (_controller.value / _faceStep).floor();
            final face = faceIndex < _airFaces.length
                ? _airFaces[faceIndex]
                : 6;

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: die,
                    height: die * 1.2,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Soft contact shadow: only the blur of an unpainted pill.
                        Positioned(
                          left: dx + die / 2 - die * footprint * 0.4,
                          top: die * 1.02,
                          child: Opacity(
                            opacity: shadowOpacity,
                            child: Container(
                              width: die * footprint * 0.8 * shadowScale,
                              height: die * 0.06,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(die),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.onSurface.withValues(
                                      alpha: dark ? 0.55 : 0.32,
                                    ),
                                    blurRadius: die * 0.12,
                                    spreadRadius: die * 0.02,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: dx,
                          top: dy - lift,
                          child: Transform.rotate(
                            angle: angle,
                            child: _Die(size: die, face: face),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: die * 0.3),
                  Opacity(
                    opacity: titleT,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - titleT)),
                      child: Text(
                        'Hold My Dice',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Pips on a 3x3 grid, row by row, for each face.
const _pips = {
  1: {4},
  2: {2, 6},
  3: {2, 4, 6},
  4: {0, 2, 6, 8},
  5: {0, 2, 4, 6, 8},
  6: {0, 2, 3, 5, 6, 8},
};

class _Die extends StatelessWidget {
  const _Die({required this.size, required this.face});

  final double size;
  final int face;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pip = size * 0.155;
    return Container(
      key: const ValueKey('splash-die'),
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2A66) : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: scheme.onSurface, width: 3),
      ),
      child: Column(
        key: ValueKey('splash-face-$face'),
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var r = 0; r < 3; r++)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var c = 0; c < 3; c++)
                  SizedBox(
                    width: pip,
                    height: pip,
                    child: _pips[face]!.contains(r * 3 + c)
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.onSurface,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
