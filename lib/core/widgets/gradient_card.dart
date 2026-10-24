import 'package:flutter/material.dart';

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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [from, to],
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: dark ? 0.25 : 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
