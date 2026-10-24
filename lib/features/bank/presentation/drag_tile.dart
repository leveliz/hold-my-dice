import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/palette.dart';

/// Makes [child] both draggable (after a long press) and a drop target for
/// every other tile. While any drag is in progress, tiles that can receive
/// it show an outline, which thickens when the drag hovers over them.
///
/// The payload is the tile's [id]; a disabled tile (for example a bankrupt
/// player) is neither draggable nor droppable.
class DragTile extends StatelessWidget {
  const DragTile({
    super.key,
    required this.id,
    required this.enabled,
    required this.accent,
    required this.radius,
    required this.feedbackLabel,
    required this.dragging,
    required this.onDrop,
    required this.child,
  });

  final String id;
  final bool enabled;
  final Color accent;
  final double radius;
  final String feedbackLabel;

  /// Id of the tile currently being dragged, shared by all tiles of a screen.
  final ValueNotifier<String?> dragging;

  /// Called with the id of the tile that was dropped on this one.
  final void Function(String sourceId) onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != id,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return ValueListenableBuilder<String?>(
          valueListenable: dragging,
          builder: (context, source, _) {
            final droppable = source != null && source != id;
            return LongPressDraggable<String>(
              data: id,
              feedback: _Feedback(label: feedbackLabel, accent: accent),
              childWhenDragging: Opacity(opacity: 0.35, child: child),
              onDragStarted: () => dragging.value = id,
              onDragEnd: (_) => dragging.value = null,
              child: DecoratedBox(
                key: ValueKey('drop-zone-$id'),
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: droppable
                      ? Border.all(color: accent, width: hovering ? 4 : 2.5)
                      : null,
                ),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(accent.withValues(alpha: 0.55), Colors.white),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Palette.ink),
        ),
      ),
    );
  }
}
