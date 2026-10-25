import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/widgets/dither.dart';

/// A soft card that fades from a light tint to a deeper tint of [accent],
/// with an icon-sized tile slot handled by the caller.
class GradientCard extends StatefulWidget {
  const GradientCard({
    super.key,
    required this.accent,
    this.onTap,
    required this.child,
    this.radius = 28,
  });

  final Color accent;
  final VoidCallback? onTap;
  final Widget child;
  final double radius;

  @override
  State<GradientCard> createState() => _GradientCardState();
}

class _GradientCardState extends State<GradientCard> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final dark = theme.brightness == Brightness.dark;
    final from = Color.alphaBlend(
      widget.accent.withValues(alpha: dark ? 0.22 : 0.08),
      surface,
    );
    final to = Color.alphaBlend(
      widget.accent.withValues(alpha: dark ? 0.42 : 0.32),
      surface,
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 100),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              // A thin light edge catches the aurora in the dark theme.
              border: dark
                  ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                  : null,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [from, to],
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: dark ? 0.32 : 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            // Grain over the dark gradient keeps it from banding.
            child: dark
                ? Stack(
                    fit: StackFit.passthrough,
                    children: [
                      widget.child,
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(widget.radius),
                          child: const DitherOverlay(),
                        ),
                      ),
                    ],
                  )
                : widget.child,
          ),
        ),
      ),
    );
  }
}
