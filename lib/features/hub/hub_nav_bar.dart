import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum HubTab { home, saved, about }

const hubNavBarHeight = 64.0;
const hubNavOverhang = 24.0;
const _notchDepth = 40.0;
const _notchHalfWidth = 44.0;
const _radius = 24.0;
const _fabSize = 58.0;

/// The selected tab in the dark theme: a pale violet that glows.
const _auroraOn = Color(0xFFC4B5FD);

/// A floating bar with a smooth notch in the middle and a raised round button
/// in it. Four tabs sit either side; the selected one shows a dot. On paper
/// (light) it is an ivory sheet with a kraft button; in Aurora (dark) a glassy
/// bar with a glowing one.
class HubNavBar extends StatelessWidget {
  const HubNavBar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onStart,
    required this.onRules,
  });

  final HubTab selected;
  final ValueChanged<HubTab> onSelect;

  /// The raised centre button: start a game.
  final VoidCallback onStart;

  /// The rules library is not built yet; tapping explains that.
  final VoidCallback onRules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = PaperStyle.maybeOf(context) != null;
    final barColor = paper ? PaperStyle.card : const Color(0xFF15162E);
    final on = paper ? PaperStyle.ink : _auroraOn;
    final dot = paper ? PaperStyle.stamp : _auroraOn;
    final off = paper
        ? PaperStyle.faint
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    Widget item({
      required Key key,
      required IconData icon,
      required String label,
      required Color color,
      required bool showDot,
      required VoidCallback onTap,
    }) => Expanded(
      child: Semantics(
        button: true,
        selected: showDot,
        label: label,
        child: Tooltip(
          message: label,
          child: InkResponse(
            key: key,
            onTap: onTap,
            radius: 32,
            child: SizedBox(
              height: hubNavBarHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 26,
                    color: color,
                    shadows: !paper && showDot
                        ? [
                            Shadow(
                              color: on.withValues(alpha: 0.9),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: showDot ? dot : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      height: hubNavBarHeight + hubNavOverhang,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: hubNavBarHeight,
            child: CustomPaint(
              painter: _BarPainter(
                barColor,
                paper: paper,
                edge: paper ? null : Colors.white.withValues(alpha: 0.16),
              ),
              child: Row(
                children: [
                  item(
                    key: const ValueKey('nav-home'),
                    icon: LucideIcons.house,
                    label: 'หน้าแรก',
                    color: selected == HubTab.home ? on : off,
                    showDot: selected == HubTab.home,
                    onTap: () => onSelect(HubTab.home),
                  ),
                  item(
                    key: const ValueKey('nav-saved'),
                    icon: LucideIcons.history,
                    label: 'เกมค้าง',
                    color: selected == HubTab.saved ? on : off,
                    showDot: selected == HubTab.saved,
                    onTap: () => onSelect(HubTab.saved),
                  ),
                  const SizedBox(width: _notchHalfWidth * 2 + 8),
                  item(
                    key: const ValueKey('nav-rules'),
                    icon: LucideIcons.bookOpen,
                    label: 'คลังกฎ (เร็ว ๆ นี้)',
                    color: off.withValues(alpha: paper ? 0.55 : 0.2),
                    showDot: false,
                    onTap: onRules,
                  ),
                  item(
                    key: const ValueKey('nav-about'),
                    icon: LucideIcons.info,
                    label: 'เกี่ยวกับ',
                    color: selected == HubTab.about ? on : off,
                    showDot: selected == HubTab.about,
                    onTap: () => onSelect(HubTab.about),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Semantics(
                button: true,
                label: 'เริ่มเกม',
                child: Tooltip(
                  message: 'เริ่มเกม',
                  child: GestureDetector(
                    key: const ValueKey('nav-start'),
                    onTap: onStart,
                    child: Container(
                      width: _fabSize,
                      height: _fabSize,
                      decoration: paper
                          ? const BoxDecoration(
                              shape: BoxShape.circle,
                              color: PaperStyle.kraft,
                              // An ivory ring, a kraft outline, a kraft edge.
                              border: Border.fromBorderSide(
                                BorderSide(color: PaperStyle.card, width: 3),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: PaperStyle.kraft,
                                  spreadRadius: 1.5,
                                ),
                                BoxShadow(
                                  color: PaperStyle.kraftDark,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            )
                          : BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Palette.auroraIndigo,
                                  Palette.auroraMagenta,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Palette.auroraMagenta.withValues(
                                    alpha: 0.55,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                      child: Icon(
                        LucideIcons.dices,
                        color: paper ? PaperStyle.paper : Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.color, {required this.paper, this.edge});

  final Color color;
  final bool paper;

  /// A thin light outline, only in the dark theme.
  final Color? edge;

  Path _path(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    return Path()
      ..moveTo(_radius, 0)
      ..lineTo(cx - _notchHalfWidth - 14, 0)
      ..cubicTo(
        cx - _notchHalfWidth + 10,
        0,
        cx - 34,
        _notchDepth,
        cx,
        _notchDepth,
      )
      ..cubicTo(
        cx + 34,
        _notchDepth,
        cx + _notchHalfWidth - 10,
        0,
        cx + _notchHalfWidth + 14,
        0,
      )
      ..lineTo(w - _radius, 0)
      ..arcToPoint(Offset(w, _radius), radius: const Radius.circular(_radius))
      ..lineTo(w, h - _radius)
      ..arcToPoint(
        Offset(w - _radius, h),
        radius: const Radius.circular(_radius),
      )
      ..lineTo(_radius, h)
      ..arcToPoint(
        Offset(0, h - _radius),
        radius: const Radius.circular(_radius),
      )
      ..lineTo(0, _radius)
      ..arcToPoint(Offset(_radius, 0), radius: const Radius.circular(_radius))
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    if (paper) {
      // A sheet of paper on a second sheet: a hard edge below, no soft shadow.
      canvas.drawPath(
        path.shift(const Offset(0, 3)),
        Paint()..color = PaperStyle.sheetFar,
      );
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..color = PaperStyle.edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      _dashedTopLine(canvas, size);
      return;
    }
    canvas.drawShadow(path, const Color(0x55141446), 6, false);
    canvas.drawPath(path, Paint()..color = color);
    final line = edge;
    if (line != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  /// The ticket perforation just inside the top edge, either side of the notch.
  void _dashedTopLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PaperStyle.dash
      ..strokeWidth = 1;
    final cx = size.width / 2;
    void run(double from, double to) {
      for (var x = from; x < to; x += 8) {
        canvas.drawLine(
          Offset(x, 5),
          Offset(x + 5 > to ? to : x + 5, 5),
          paint,
        );
      }
    }

    run(_radius / 2, cx - _notchHalfWidth - 14);
    run(cx + _notchHalfWidth + 14, size.width - _radius / 2);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.color != color || old.edge != edge || old.paper != paper;
}
