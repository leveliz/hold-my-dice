import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Asked before a new game is started while the same helper has a game left in
/// its backup (one the person left on purpose, to come back to): starting the
/// new one would drop it. True to start the new game.
Future<bool> confirmReplaceSavedGame(
  BuildContext context,
  String helperName,
) async {
  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('replace-dialog'),
      title: const Text('มีเกมค้างอยู่'),
      content: Text(
        '$helperName: มีเกมที่เล่นค้างอยู่ ถ้าเริ่มเกมใหม่ เกมเดิมจะหายไป '
        'เล่นต่อจากเมนูเกมค้างได้',
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('replace-keep'),
          onPressed: () => Navigator.pop(context, false),
          icon: const Icon(LucideIcons.arrowLeft),
          label: const Text('กลับไปก่อน'),
        ),
        FilledButton.icon(
          key: const ValueKey('replace-confirm'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(LucideIcons.play),
          label: const Text('เริ่มเกมใหม่'),
        ),
      ],
    ),
  );
  return replace == true;
}
