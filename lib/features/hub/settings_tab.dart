import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/settings/app_settings.dart';
import 'package:hold_my_dice/core/theme.dart';

/// App-wide settings. For now just the look: follow the phone, Papery, or
/// Aurora.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key, required this.bottomSpace});

  final double bottomSpace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final paper = PaperStyle.maybeOf(context) != null;
    final mode = ref.watch(themeModeProvider);
    void pick(ThemeMode m) => ref.read(themeModeProvider.notifier).set(m);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 22, paper ? 26 : 20, bottomSpace),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: paper
              ? PaperStyle.cardDecoration()
              : BoxDecoration(
                  color: surfaceTileColor(theme),
                  borderRadius: BorderRadius.circular(22),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ธีม',
                style: paper ? serifStyle(text.titleMedium) : text.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                key: const ValueKey('theme-mode'),
                children: [
                  Expanded(
                    child: ThemeOption(
                      key: const ValueKey('theme-system'),
                      label: 'ตามเครื่อง',
                      selected: mode == ThemeMode.system,
                      onTap: () => pick(ThemeMode.system),
                      preview: const _SystemPreview(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ThemeOption(
                      key: const ValueKey('theme-light'),
                      label: 'Papery',
                      selected: mode == ThemeMode.light,
                      onTap: () => pick(ThemeMode.light),
                      preview: const _PaperPreview(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ThemeOption(
                      key: const ValueKey('theme-dark'),
                      label: 'Aurora',
                      selected: mode == ThemeMode.dark,
                      onTap: () => pick(ThemeMode.dark),
                      preview: const _AuroraPreview(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One choice of look: a small picture of it above its name. The chosen one is
/// outlined, and on paper carries a red tick like a stamp.
class ThemeOption extends StatelessWidget {
  const ThemeOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = PaperStyle.maybeOf(context) != null;
    final edge = selected
        ? (paper ? PaperStyle.ink : Palette.auroraIndigo)
        : (paper ? PaperStyle.edge : Colors.white.withValues(alpha: 0.18));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: paper
                    ? PaperStyle.card
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(paper ? 6 : 14),
                border: Border.all(color: edge, width: selected ? 2 : 1),
                boxShadow: paper && selected
                    ? const [
                        BoxShadow(
                          color: PaperStyle.kraft,
                          offset: Offset(2, 2),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1.15,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(paper ? 4 : 8),
                      child: preview,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: -8,
                right: -6,
                child: Container(
                  key: const ValueKey('theme-tick'),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: paper ? PaperStyle.stamp : Palette.auroraIndigo,
                  ),
                  child: const Icon(Icons.check, size: 15, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Half paper, half night: follows whichever the phone uses.
class _SystemPreview extends StatelessWidget {
  const _SystemPreview();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SplitPainter());
  }
}

class _SplitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PaperStyle.paper);
    final night = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(night, Paint()..color = const Color(0xFF17182E));
  }

  @override
  bool shouldRepaint(_SplitPainter old) => false;
}

class _PaperPreview extends StatelessWidget {
  const _PaperPreview();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: PaperStyle.paper);
  }
}

class _AuroraPreview extends StatelessWidget {
  const _AuroraPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.6, -0.7),
          radius: 1.1,
          // Opaque stops, so the picture looks the same on paper and at night.
          colors: [
            Color.alphaBlend(
              Palette.auroraIndigo.withValues(alpha: 0.8),
              Palette.night,
            ),
            Color.alphaBlend(
              Palette.auroraMagenta.withValues(alpha: 0.45),
              Palette.night,
            ),
            Palette.night,
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
    );
  }
}
