import 'package:flutter/widgets.dart';

/// The "end the game" icon: a flag with END on it. A picture rather than a
/// glyph from the icon font, so it takes its colour and size from the nearest
/// [IconTheme] like any other icon.
class EndGameIcon extends StatelessWidget {
  const EndGameIcon({super.key, this.size, this.color});

  static const asset = 'assets/icons/end_game.png';

  final double? size;
  final Color? color;

  /// The picture fills its whole square, while the icon font keeps a margin
  /// inside each glyph, so it is drawn a little smaller to look the same size.
  static const _scale = 0.88;

  @override
  Widget build(BuildContext context) {
    final full = size ?? IconTheme.of(context).size ?? 24;
    // A picture fills any box that is forced on it (a font icon would only be
    // drawn at its own size inside the box), so it is centred to keep its size.
    return Center(
      child: ImageIcon(
        const AssetImage(asset),
        size: full * _scale,
        color: color,
      ),
    );
  }
}
