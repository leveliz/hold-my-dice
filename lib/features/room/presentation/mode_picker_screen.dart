import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/stamp.dart';
import 'package:hold_my_dice/features/bank/presentation/setup_screen.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Where Pocket Banker starts: straight into the single-device setup, or, when
/// rooms are available, the choice between the two modes.
class BankEntryScreen extends ConsumerWidget {
  const BankEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(multiDeviceEnabledProvider)
      ? const ModePickerScreen()
      : const SetupScreen();
}

class ModePickerScreen extends StatelessWidget {
  const ModePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = helperById('bank').color;
    return Scaffold(
      appBar: const HelperAppBar(title: Text('Pocket Banker')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'เล่นกันแบบไหนดี',
                style: headingStyle(context, text.titleLarge),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                key: const ValueKey('mode-solo'),
                accent: accent,
                icon: LucideIcons.smartphone,
                title: 'เครื่องเดียว',
                subtitle: 'เครื่องนี้เป็นนายธนาคาร',
                onTap: () => context.push('/bank/solo'),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                key: const ValueKey('mode-multi'),
                accent: accent,
                icon: LucideIcons.users,
                title: 'หลายเครื่อง',
                subtitle:
                    'ทุกคนถือเครื่องตัวเอง ไม่มีนายธนาคารกลาง เห็นประวัติเดียวกัน',
                isNew: true,
                onTap: () => context.push('/room/create'),
              ),
              const Spacer(),
              OutlinedButton.icon(
                key: const ValueKey('mode-join'),
                onPressed: () => context.push('/room/join'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(LucideIcons.doorOpen),
                label: const Text('มีรหัสห้อง เข้าห้อง'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isNew = false,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GradientCard(
      accent: accent,
      radius: 22,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(title, style: text.titleMedium)),
                      if (isNew) ...[
                        const SizedBox(width: 8),
                        Stamp(
                          color: PaperStyle.stamp,
                          size: 34,
                          tilt: -8,
                          child: Text('ใหม่', style: text.labelSmall),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: text.bodyMedium?.copyWith(
                      color: text.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
