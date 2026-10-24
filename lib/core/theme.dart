import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildTheme(Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: brightness,
    ),
  );
  return base.copyWith(textTheme: GoogleFonts.itimTextTheme(base.textTheme));
}
