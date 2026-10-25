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
        primary: dark ? Palette.auroraIndigo : Palette.cobalt,
        onPrimary: Colors.white,
        surface: background,
        onSurface: onBackground,
      );
  // Sheets and dialogs sit one step above the page, in the page's own hue.
  final raised = dark
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06), background)
      : Colors.white;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // The page gradient is painted behind every page (see PageBackground).
    scaffoldBackgroundColor: Colors.transparent,
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
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        // Cobalt is too dim for text on the dark navy page.
        foregroundColor: dark ? Palette.cobaltLight : Palette.cobalt,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: raised,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: raised,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// Fill for rows and fields that sit directly on the page background.
Color surfaceTileColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? Color.alphaBlend(
        Colors.white.withValues(alpha: 0.07),
        theme.colorScheme.surface,
      )
    : Colors.white;
