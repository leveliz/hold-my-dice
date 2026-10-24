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
    required this.route,
  });

  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}

const helpers = [
  Helper(
    id: 'bank',
    name: 'Pocket Banker',
    subtitle: 'ธนาคารเกมเศรษฐี',
    icon: LucideIcons.landmark,
    color: Palette.green,
    route: '/bank',
  ),
  Helper(
    id: 'score',
    name: 'Score Snitch',
    subtitle: 'นับคะแนนรายรอบ',
    icon: LucideIcons.clipboardList,
    color: Palette.cobalt,
    route: '/score',
  ),
];
