import 'dart:math';

import 'package:flutter/material.dart';

const playerPalette = [
  Color(0xFF3D5AFE),
  Color(0xFF2E9E57),
  Color(0xFFE8920C),
  Color(0xFFD6409F),
  Color(0xFF00A3B8),
  Color(0xFF7C4DFF),
  Color(0xFFC2410C),
  Color(0xFF65A30D),
  Color(0xFFE11D48),
  Color(0xFF0F766E),
];

/// A random palette colour not in [used]; once the palette is exhausted a
/// random hue is generated instead.
Color randomPlayerColor(Set<int> used, [Random? random]) {
  final rng = random ?? Random();
  final free = playerPalette
      .where((c) => !used.contains(c.toARGB32()))
      .toList();
  if (free.isNotEmpty) return free[rng.nextInt(free.length)];
  Color c;
  do {
    c = HSLColor.fromAHSL(1, rng.nextInt(360).toDouble(), 0.65, 0.5).toColor();
  } while (used.contains(c.toARGB32()));
  return c;
}
