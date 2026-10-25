import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';

/// Light is Papery (warm paper and ink), dark is Aurora Glow (midnight and
/// light blooms).
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? Palette.night : PaperStyle.paper;
  final onBackground = dark ? Palette.paper : PaperStyle.ink;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.cobalt,
        brightness: brightness,
      ).copyWith(
        primary: dark ? Palette.auroraIndigo : PaperStyle.ink,
        onPrimary: dark ? Colors.white : PaperStyle.onInk,
        surface: background,
        onSurface: onBackground,
        secondaryContainer: dark ? null : const Color(0xFFEFE6D2),
        onSecondaryContainer: dark ? null : PaperStyle.ink,
        outline: dark ? null : PaperStyle.kraft,
        outlineVariant: dark ? null : PaperStyle.dash,
      );
  // Sheets and dialogs sit one step above the page, in the page's own hue.
  final raised = dark
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06), background)
      : PaperStyle.card;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // The page ground is painted behind every page (see PageBackground).
    scaffoldBackgroundColor: Colors.transparent,
    extensions: [if (!dark) const PaperStyle()],
  );
  final textTheme = GoogleFonts.itimTextTheme(
    base.textTheme,
  ).apply(bodyColor: onBackground, displayColor: onBackground);
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(dark ? 20 : PaperStyle.radius),
  );
  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: onBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: dark
          ? textTheme.headlineMedium?.copyWith(
              color: onBackground,
              fontSize: 36,
            )
          : serifStyle(
              textTheme.headlineMedium?.copyWith(
                color: onBackground,
                fontSize: 26,
              ),
            ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        surfaceTintColor: Colors.transparent,
        // Papery buttons rest on a kraft edge; Aurora buttons stay flat.
        elevation: dark ? 0 : 2,
        shadowColor: dark ? null : PaperStyle.kraft,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        // Cobalt is too dim for text on the dark page.
        foregroundColor: dark ? Palette.cobaltLight : PaperStyle.ink,
      ),
    ),
    segmentedButtonTheme: dark
        ? null
        : SegmentedButtonThemeData(
            style: SegmentedButton.styleFrom(
              foregroundColor: PaperStyle.ink,
              backgroundColor: PaperStyle.card,
              selectedForegroundColor: PaperStyle.ink,
              selectedBackgroundColor: const Color(0xFFEFE6D2),
              side: const BorderSide(color: PaperStyle.kraft),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PaperStyle.radius),
              ),
            ),
          ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? raised : PaperStyle.paper,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: dark ? null : PaperStyle.dash,
      shape: dark
          ? null
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              side: BorderSide(color: PaperStyle.edge),
            ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: raised,
      surfaceTintColor: Colors.transparent,
      shape: dark
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PaperStyle.radius),
              side: const BorderSide(color: PaperStyle.edge),
            ),
      titleTextStyle: dark
          ? null
          : serifStyle(textTheme.titleLarge?.copyWith(color: PaperStyle.ink)),
    ),
    snackBarTheme: dark
        ? null
        : SnackBarThemeData(
            backgroundColor: PaperStyle.ink,
            contentTextStyle: textTheme.bodyMedium?.copyWith(
              color: PaperStyle.onInk,
            ),
          ),
    chipTheme: dark
        ? null
        : ChipThemeData(
            backgroundColor: PaperStyle.card,
            side: const BorderSide(color: PaperStyle.kraft),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            labelStyle: textTheme.bodyMedium?.copyWith(color: PaperStyle.ink),
          ),
    dividerColor: dark ? null : PaperStyle.dash,
  );
}

/// Fill for rows and fields that sit directly on the page background.
Color surfaceTileColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? Color.alphaBlend(
        Colors.white.withValues(alpha: 0.07),
        theme.colorScheme.surface,
      )
    : PaperStyle.card;

/// A row or field that sits directly on the page: on paper a ticket-like box
/// with a thin edge and one sheet under it, in Aurora a faint lighter panel.
BoxDecoration tileDecoration(BuildContext context, {double radius = 18}) {
  if (PaperStyle.maybeOf(context) != null) {
    return BoxDecoration(
      color: PaperStyle.card,
      borderRadius: BorderRadius.circular(PaperStyle.radius),
      border: Border.all(color: PaperStyle.edge),
      boxShadow: const [
        BoxShadow(color: PaperStyle.sheetFar, offset: Offset(2, 3)),
      ],
    );
  }
  return BoxDecoration(
    color: surfaceTileColor(Theme.of(context)),
    borderRadius: BorderRadius.circular(radius),
  );
}

/// A bigger block that holds a few related things (a settings group, an about
/// card): on paper a card with two sheets under it, in Aurora a faint panel.
BoxDecoration panelDecoration(BuildContext context) {
  if (PaperStyle.maybeOf(context) != null) return PaperStyle.cardDecoration();
  return BoxDecoration(
    color: surfaceTileColor(Theme.of(context)),
    borderRadius: BorderRadius.circular(22),
  );
}
