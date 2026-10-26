import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/players/player_colors.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/dashed_line.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The six colours offered when choosing yours (the palette keeps the rest for
/// the single-device mode).
final roomColorChoices = playerPalette.take(6).toList();

/// Colour circles to pick one from; the chosen one has a ring.
class ColorSwatches extends StatelessWidget {
  const ColorSwatches({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final c in roomColorChoices)
          Semantics(
            button: true,
            selected: c == selected,
            child: GestureDetector(
              key: ValueKey('color-${c.toARGB32()}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(c),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: c == selected
                      ? Border.all(color: ring, width: 2.5)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The room code as six big letters on tiles; tap to copy the code.
class RoomCodeTiles extends StatelessWidget {
  const RoomCodeTiles({super.key, required this.code, this.onCopied});

  final String code;
  final VoidCallback? onCopied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = PaperStyle.maybeOf(context) != null;
    final edge = paper
        ? PaperStyle.ink
        : theme.colorScheme.onSurface.withValues(alpha: 0.3);
    return Semantics(
      button: true,
      label: 'คัดลอกรหัสห้อง $code',
      child: GestureDetector(
        key: const ValueKey('code-tiles'),
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          onCopied?.call();
        },
        child: Row(
          children: [
            for (final (i, letter) in code.split('').indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: edge, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    letter,
                    style: serifStyle(theme.textTheme.headlineSmall),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small outlined label such as "เจ้าของห้อง" or "4 / 6".
class RoomChip extends StatelessWidget {
  const RoomChip(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c)),
    );
  }
}

/// The green "สด" mark: this list updates by itself.
class LiveMark extends StatelessWidget {
  const LiveMark({super.key, this.color = const Color(0xFF10B981)});

  /// The colour of the dot and the word; light on the coloured header of
  /// Aurora, where the usual green would vanish.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          'สด',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// A field that looks like the setup screens' rows: a label and a value.
class RoomField extends StatelessWidget {
  const RoomField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.obscure = false,
    this.onChanged,
    this.textAlign = TextAlign.end,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: tileDecoration(context),
      child: Row(
        children: [
          Text(label, style: text.titleMedium),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: textAlign,
              obscureText: obscure,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: text.titleLarge,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: text.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row with a label and an on/off switch.
class RoomSwitch extends StatelessWidget {
  const RoomSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(label, style: Theme.of(context).textTheme.titleMedium),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A QR code of [data] in dark ink on white, so a camera reads it in either
/// theme.
class RoomQr extends StatelessWidget {
  const RoomQr({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(6),
      child: QrImageView(
        data: data,
        size: 96,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF16163F),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF16163F),
        ),
      ),
    );
  }
}

/// A ticket: [top], a dashed perforation with a notch cut into each side, then
/// [bottom]. On paper the card has two sheets peeking out underneath.
class TicketCard extends StatefulWidget {
  const TicketCard({
    super.key,
    required this.top,
    required this.bottom,
    required this.line,
  });

  final Widget top;
  final Widget bottom;

  /// Colour of the perforation.
  final Color line;

  @override
  State<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> {
  static const _lineThickness = 1.5;
  final _topKey = GlobalKey();
  double? _notchY;

  void _measure() {
    final box = _topKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || box == null || !box.hasSize) return;
    final y = box.size.height + _lineThickness / 2;
    if (y != _notchY) setState(() => _notchY = y);
  }

  @override
  Widget build(BuildContext context) {
    // The perforation sits right under [top], whose height is only known once
    // it has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final theme = Theme.of(context);
    final paper = PaperStyle.maybeOf(context) != null;
    return CustomPaint(
      painter: TicketPainter(
        notchY: _notchY,
        radius: paper ? PaperStyle.radius : 22,
        fill: surfaceTileColor(theme),
        edge: paper ? PaperStyle.edge : Colors.white.withValues(alpha: 0.14),
        sheets: paper
            ? const [PaperStyle.sheetFar, PaperStyle.sheetNear]
            : const [],
      ),
      child: Column(
        children: [
          KeyedSubtree(key: _topKey, child: widget.top),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: DashedLine(color: widget.line, thickness: _lineThickness),
          ),
          widget.bottom,
        ],
      ),
    );
  }
}

/// Paints a ticket: a rounded card with a half circle cut out of each side at
/// [notchY], an edge line, and [sheets] (farthest first) under it.
class TicketPainter extends CustomPainter {
  const TicketPainter({
    required this.notchY,
    required this.radius,
    required this.fill,
    required this.edge,
    required this.sheets,
    this.notchRadius = 9,
  });

  final double? notchY;
  final double radius;
  final Color fill;
  final Color edge;
  final List<Color> sheets;
  final double notchRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final card = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    for (final (i, color) in sheets.indexed) {
      final shift = (sheets.length - i) * 3.0;
      canvas.drawRRect(
        card.shift(Offset(shift, shift)),
        Paint()..color = color,
      );
    }
    var path = Path()..addRRect(card);
    final y = notchY;
    if (y != null) {
      final notches = Path()
        ..addOval(Rect.fromCircle(center: Offset(0, y), radius: notchRadius))
        ..addOval(
          Rect.fromCircle(center: Offset(size.width, y), radius: notchRadius),
        );
      path = Path.combine(PathOperation.difference, path, notches);
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(TicketPainter old) =>
      notchY != old.notchY ||
      radius != old.radius ||
      fill != old.fill ||
      edge != old.edge ||
      notchRadius != old.notchRadius ||
      sheets.length != old.sheets.length;
}

/// Stops a name at the length the Firestore rules accept (see [cutName]), so
/// what a person sees typed is what is stored.
class NameLimitFormatter extends _CutFormatter {
  const NameLimitFormatter() : super(cutName);
}

/// The same for the reason of an entry (see [cutReason]).
class ReasonLimitFormatter extends _CutFormatter {
  const ReasonLimitFormatter() : super(cutReason);
}

class _CutFormatter extends TextInputFormatter {
  const _CutFormatter(this._cut);

  final String Function(String) _cut;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cut = _cut(newValue.text);
    if (cut == newValue.text) return newValue;
    final caret = newValue.selection.baseOffset.clamp(0, cut.length);
    return TextEditingValue(
      text: cut,
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}
