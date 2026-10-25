import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/widgets/dither.dart';

/// The card every helper screen uses. Light (Papery): an ivory paper card with
/// two sheets peeking out underneath. Dark (Aurora): a glowing card tinted with
/// [accent]. The caller lays out what is inside.
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

  /// The corner a card really gets: Papery cards are all squarer, whatever a
  /// screen asked for. Anything drawn around a card (like a drop-zone outline)
  /// should use this too, so the two match.
  static double radiusFor(BuildContext context, double requested) =>
      PaperStyle.maybeOf(context) != null ? PaperStyle.radius : requested;

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
    final paper = PaperStyle.maybeOf(context) != null;
    final radius = GradientCard.radiusFor(context, widget.radius);
    final from = Color.alphaBlend(
      widget.accent.withValues(alpha: 0.22),
      surface,
    );
    final to = Color.alphaBlend(widget.accent.withValues(alpha: 0.42), surface);
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
            // Papery: ivory sheets stacked under each other. Aurora: a glowing
            // card with a thin light edge.
            decoration: paper
                ? PaperStyle.cardDecoration(radius: radius)
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [from, to],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.32),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
            // Grain over the dark gradient keeps it from banding.
            child: paper
                ? widget.child
                : Stack(
                    fit: StackFit.passthrough,
                    children: [
                      widget.child,
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: const DitherOverlay(),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
