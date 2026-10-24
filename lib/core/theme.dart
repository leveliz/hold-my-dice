import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/palette.dart';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? Palette.night : Palette.paper;
  final onBackground = dark ? Palette.paper : Palette.ink;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.cobalt,
        brightness: brightness,
      ).copyWith(
        primary: Palette.cobalt,
        onPrimary: Colors.white,
        surface: background,
        onSurface: onBackground,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
  );
  final textTheme = GoogleFonts.itimTextTheme(
    base.textTheme,
  ).apply(bodyColor: onBackground, displayColor: onBackground);
  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onBackground,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.headlineMedium?.copyWith(
        color: onBackground,
        fontSize: 36,
      ),
    ),
  );
}
