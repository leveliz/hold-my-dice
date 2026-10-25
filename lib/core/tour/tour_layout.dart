import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Gap kept between the card and the screen edge, and around lit-up areas.
const tourMargin = 12.0;
const _clearance = 8.0;

/// Where [key]'s widget is on the screen, or null if it cannot be shown now:
/// not built, no size yet, or its middle is off the screen.
Rect? tourTargetRect(GlobalKey? key, Size screen) {
  final RenderObject? box;
  try {
    box = key?.currentContext?.findRenderObject();
  } on FlutterError {
    // The widget is on its way out (the screen under the tour is closing).
    return null;
  }
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  if (rect.isEmpty) return null;
  return (Offset.zero & screen).contains(rect.center) ? rect : null;
}

/// Where the card goes so it covers none of the [spots], or null if there is
/// no such place.
///
/// Upright: at the top or the bottom, trying first the end the spots are not
/// near, then the free band between them. Sideways: in one of the four
/// corners, trying first the corner on the other side from the spots.
Offset? placeTourCard({
  required Size screen,
  required EdgeInsets safe,
  required List<Rect> spots,
  required Size card,
}) {
  if (spots.isEmpty) return null;
  final area = Rect.fromLTRB(
    safe.left + tourMargin,
    safe.top + tourMargin,
    screen.width - safe.right - tourMargin,
    screen.height - safe.bottom - tourMargin,
  );
  final lit = [for (final s in spots) s.inflate(_clearance)];
  bool free(Rect r) => !lit.any((s) => s.overlaps(r));
  final center = spots.map((s) => s.center).reduce((a, b) => (a + b) / 2);

  Rect at(double left, double top) =>
      Rect.fromLTWH(left, top, card.width, card.height);

  final candidates = <Rect>[];
  if (screen.width > screen.height) {
    final left = area.left;
    final right = area.right - card.width;
    final top = area.top;
    final bottom = area.bottom - card.height;
    final lefts = center.dx > screen.width / 2 ? [left, right] : [right, left];
    for (final y in [bottom, top]) {
      for (final x in lefts) {
        candidates.add(at(x, y));
      }
    }
  } else {
    final x = (screen.width - card.width) / 2;
    final top = at(x, area.top);
    final bottom = at(x, area.bottom - card.height);
    candidates.addAll(
      center.dy > screen.height / 2 ? [top, bottom] : [bottom, top],
    );
    final band = _widestGap(area, lit, card.height);
    if (band != null) candidates.add(at(x, band));
  }
  for (final c in candidates) {
    if (free(c) &&
        area.inflate(0.5).contains(c.topLeft) &&
        area.inflate(0.5).contains(c.bottomRight)) {
      return c.topLeft;
    }
  }
  return null;
}

/// The top of the tallest free horizontal band in [area] that is at least
/// [height] tall, with the card centred in it.
double? _widestGap(Rect area, List<Rect> lit, double height) {
  final blocks = [...lit]..sort((a, b) => a.top.compareTo(b.top));
  var best = 0.0;
  double? top;
  var cursor = area.top;
  void gap(double from, double to) {
    final size = to - from;
    if (size >= height && size > best) {
      best = size;
      top = from + (size - height) / 2;
    }
  }

  for (final b in blocks) {
    gap(cursor, math.min(b.top, area.bottom));
    cursor = math.max(cursor, b.bottom);
  }
  gap(cursor, area.bottom);
  return top;
}
