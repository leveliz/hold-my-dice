import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/settings/app_settings.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// App-wide settings. For now just the colour mode.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key, required this.bottomSpace});

  final double bottomSpace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final mode = ref.watch(themeModeProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 22, 20, bottomSpace),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceTileColor(theme),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('โหมดสี', style: text.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                key: const ValueKey('theme-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(LucideIcons.smartphone),
                    label: Text('ตามเครื่อง'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(LucideIcons.sun),
                    label: Text('สว่าง'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(LucideIcons.moon),
                    label: Text('มืด'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
