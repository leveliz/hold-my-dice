import 'package:flutter/material.dart';

/// The Papery look of the light theme: warm ivory paper with a dotted grain,
/// ink and kraft brown, layered sheets, dashed ticket lines and stamps.
/// Present on the light theme only; the dark theme (Aurora Glow) has none, so
/// a widget asks `PaperStyle.maybeOf(context)` to pick its look.
@immutable
class PaperStyle extends ThemeExtension<PaperStyle> {
  const PaperStyle();

  static const paper = Color(0xFFFBF8F1);
  static const card = Color(0xFFFFFDF8);
  static const ink = Color(0xFF2C2419);
  static const onInk = Color(0xFFFFF8EA);
  static const kraft = Color(0xFF786C58);
  static const kraftDark = Color(0xFF5E5444);
  static const edge = Color(0xFFE5DCC8);
  static const dash = Color(0xFFCFC3AE);
  static const grain = Color(0xFFE6DCC4);
  static const stamp = Color(0xFFB8472B);
  static const sheetNear = Color(0xFFF0E8D6);
  static const sheetFar = Color(0xFFE6DCC4);
  static const faint = Color(0xFFB5A98F);

  /// Corner of a paper card, a button or a field.
  static const radius = 8.0;

  static PaperStyle? maybeOf(BuildContext context) =>
      Theme.of(context).extension<PaperStyle>();

  /// Two sheets peeking out from under a card, offset down and to the right.
  static const layeredShadow = [
    BoxShadow(color: sheetNear, offset: Offset(3, 3)),
    BoxShadow(color: sheetFar, offset: Offset(6, 6)),
  ];

  /// A paper card: ivory, a thin edge, two sheets underneath.
  static BoxDecoration cardDecoration({double radius = PaperStyle.radius}) =>
      BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge),
        boxShadow: layeredShadow,
      );

  @override
  PaperStyle copyWith() => this;

  @override
  PaperStyle lerp(PaperStyle? other, double t) => this;
}

/// [base] in the serif on paper, unchanged in Aurora.
TextStyle? headingStyle(BuildContext context, TextStyle? base) =>
    PaperStyle.maybeOf(context) != null ? serifStyle(base) : base;

/// Headings in the light theme use a Thai serif face; numbers and body text
/// keep Itim so amounts stay easy to read.
TextStyle? serifStyle(TextStyle? base) => base?.copyWith(
  fontFamily: 'NotoSerifThai',
  fontWeight: FontWeight.w700,
  fontVariations: const [FontVariation.weight(700)],
);
