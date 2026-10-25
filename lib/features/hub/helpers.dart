import 'package:flutter/widgets.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class Helper {
  const Helper({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.paperColor,
    required this.route,
  });

  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// The earthier shade the helper wears on paper (Papery).
  final Color paperColor;
  final String route;
}

const helpers = [
  Helper(
    id: 'bank',
    name: 'Pocket Banker',
    subtitle: 'ธนาคารเกมเศรษฐี',
    icon: LucideIcons.landmark,
    color: Palette.green,
    paperColor: Color(0xFF3F7A52),
    route: '/bank',
  ),
  Helper(
    id: 'score',
    name: 'Score Snitch',
    subtitle: 'นับคะแนนรายรอบ',
    icon: LucideIcons.clipboardList,
    color: Palette.cobalt,
    paperColor: Color(0xFF3F51A3),
    route: '/score',
  ),
  Helper(
    id: 'point',
    name: 'Point Blank',
    subtitle: 'นับแต้มกีฬา 2 ฝั่ง',
    icon: LucideIcons.crosshair,
    color: Palette.rose,
    paperColor: Color(0xFFB5432B),
    route: '/point',
  ),
];

Helper helperById(String id) => helpers.firstWhere((h) => h.id == id);
