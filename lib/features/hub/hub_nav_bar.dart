import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum HubTab { home, saved, settings }

const hubNavBarHeight = 64.0;
const hubNavOverhang = 24.0;
const _notchDepth = 40.0;
const _notchHalfWidth = 44.0;
const _radius = 24.0;
const _fabSize = 58.0;

/// The selected tab in the dark theme: a pale violet that glows.
const _auroraOn = Color(0xFFC4B5FD);

/// A floating bar with a smooth notch in the middle and a raised round button
/// in it. Four tabs sit either side; the selected one shows a dot.
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
    final dark = theme.brightness == Brightness.dark;
    final barColor = dark ? const Color(0xFF15162E) : Colors.white;
    final on = dark ? _auroraOn : Palette.cobalt;
    final off = theme.colorScheme.onSurface.withValues(alpha: 0.38);

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
                    shadows: dark && showDot
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
                      color: showDot ? on : Colors.transparent,
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
                edge: dark ? Colors.white.withValues(alpha: 0.16) : null,
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
                    color: off.withValues(alpha: 0.2),
                    showDot: false,
                    onTap: onRules,
                  ),
                  item(
                    key: const ValueKey('nav-settings'),
                    icon: LucideIcons.settings,
                    label: 'ตั้งค่า',
                    color: selected == HubTab.settings ? on : off,
                    showDot: selected == HubTab.settings,
                    onTap: () => onSelect(HubTab.settings),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark
                              ? const [
                                  Palette.auroraIndigo,
                                  Palette.auroraMagenta,
                                ]
                              : const [Color(0xFF6B86FF), Palette.cobalt],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (dark ? Palette.auroraMagenta : Palette.cobalt)
                                    .withValues(alpha: dark ? 0.55 : 0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.dices,
                        color: Colors.white,
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
  _BarPainter(this.color, {this.edge});

  final Color color;

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

  @override
  bool shouldRepaint(_BarPainter old) => old.color != color || old.edge != edge;
}
