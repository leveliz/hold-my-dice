import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The darkest tint of [color] that still reads white text at 4.5:1, so every
/// helper can colour its header without losing legibility.
Color headerColorFor(Color color, Brightness brightness) {
  var hsl = HSLColor.fromColor(color);
  if (brightness == Brightness.dark) {
    hsl = hsl.withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0));
  }
  while (hsl.toColor().computeLuminance() > 0.183 && hsl.lightness > 0.05) {
    hsl = hsl.withLightness((hsl.lightness - 0.02).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

/// Gives a helper's pages a flat header in the helper's own colour.
class HelperScope extends StatelessWidget {
  const HelperScope({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bar = headerColorFor(color, theme.brightness);
    final base = theme.appBarTheme;
    return Theme(
      data: theme.copyWith(
        appBarTheme: base.copyWith(
          backgroundColor: bar,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          titleTextStyle: base.titleTextStyle?.copyWith(color: Colors.white),
        ),
      ),
      child: child,
    );
  }
}
