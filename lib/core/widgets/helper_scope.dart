import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/widgets/dashed_line.dart';

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

/// Tells a helper's pages which colour is theirs, for the line under a paper
/// header.
class HelperAccent extends InheritedWidget {
  const HelperAccent({super.key, required this.color, required super.child});

  final Color color;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HelperAccent>()?.color ??
      PaperStyle.ink;

  @override
  bool updateShouldNotify(HelperAccent old) => color != old.color;
}

/// Gives a helper's pages their header. Aurora (dark): a flat band in
/// [color]. Papery (light): the paper shows through and a dashed line in
/// [paperColor] runs underneath (see [HelperAppBar]).
class HelperScope extends StatelessWidget {
  const HelperScope({
    super.key,
    required this.color,
    required this.paperColor,
    required this.child,
  });

  final Color color;
  final Color paperColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = PaperStyle.maybeOf(context) != null;
    Widget page = HelperAccent(color: paper ? paperColor : color, child: child);
    if (paper) return page;
    final bar = headerColorFor(color, theme.brightness);
    final base = theme.appBarTheme;
    page = Theme(
      data: theme.copyWith(
        appBarTheme: base.copyWith(
          backgroundColor: bar,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          titleTextStyle: base.titleTextStyle?.copyWith(color: Colors.white),
        ),
      ),
      child: page,
    );
    return page;
  }
}

/// The header of a helper's page: the title and its buttons, and on paper a
/// dashed line in the helper's colour underneath.
class HelperAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HelperAppBar({
    super.key,
    required this.title,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight = 72,
  });

  final Widget title;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final paper = PaperStyle.maybeOf(context) != null;
    return AppBar(
      toolbarHeight: toolbarHeight,
      title: title,
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
      flexibleSpace: paper
          ? Align(
              key: const ValueKey('header-line'),
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DashedLine(color: HelperAccent.of(context)),
              ),
            )
          : null,
    );
  }
}
