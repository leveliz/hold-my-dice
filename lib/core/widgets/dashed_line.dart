import 'package:flutter/material.dart';

/// A thin dashed line across the available width, like the perforation of a
/// ticket.
class DashedLine extends StatelessWidget {
  const DashedLine({
    super.key,
    required this.color,
    this.thickness = 1.2,
    this.dash = 5,
    this.gap = 4,
  });

  final Color color;
  final double thickness;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(color, thickness, dash, gap),
      size: Size(double.infinity, thickness),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this.color, this.thickness, this.dash, this.gap);

  final Color color;
  final double thickness;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      final end = x + dash > size.width ? size.width : x + dash;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) =>
      old.color != color ||
      old.thickness != thickness ||
      old.dash != dash ||
      old.gap != gap;
}
