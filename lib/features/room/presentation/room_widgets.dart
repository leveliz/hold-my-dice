import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/players/player_colors.dart';
import 'package:hold_my_dice/core/theme.dart';
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
  const LiveMark({super.key});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: green, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          'สด',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: green),
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
