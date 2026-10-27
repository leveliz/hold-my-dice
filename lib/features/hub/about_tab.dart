import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/app_info.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/stamp.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Who made the app, and where to find them.
const developerName = 'leveliz';
final developerGithub = Uri.parse('https://github.com/leveliz');

/// The "เกี่ยวกับ" tab: what the app is, which version, who made it. Room for
/// ways to support the developer later.
class AboutTab extends ConsumerWidget {
  const AboutTab({super.key, required this.bottomSpace});

  final double bottomSpace;

  Future<void> _openGithub(BuildContext context, WidgetRef ref) async {
    final opened = await ref.read(linkOpenerProvider).open(developerGithub);
    if (opened || !context.mounted) return;
    // No browser to take it: hand the link over by copy instead.
    await _copyGithub(context, 'เปิดลิงก์ไม่ได้ คัดลอกลิงก์ให้แล้ว');
  }

  Future<void> _copyGithub(BuildContext context, String message) async {
    await Clipboard.setData(ClipboardData(text: developerGithub.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('about-copied'),
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final paper = PaperStyle.maybeOf(context) != null;
    final muted = paper
        ? PaperStyle.kraft
        : theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final accent = paper ? PaperStyle.stamp : Palette.auroraIndigo;
    final info = ref.watch(appInfoProvider);
    final version = info.maybeWhen(data: (i) => i.label, orElse: () => '–');

    Widget card({required Key key, required List<Widget> children}) =>
        Container(
          key: key,
          padding: const EdgeInsets.all(16),
          decoration: panelDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 22, paper ? 26 : 20, bottomSpace),
      children: [
        card(
          key: const ValueKey('about-app'),
          children: [
            Row(
              children: [
                Stamp(
                  color: accent,
                  size: 52,
                  child: const Icon(LucideIcons.dices),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hold My Dice',
                        style: headingStyle(context, text.titleLarge),
                      ),
                      Text(
                        'ตัวช่วยสำหรับเล่นบอร์ดเกม',
                        style: text.bodyMedium?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'เวอร์ชัน $version',
              key: const ValueKey('about-version'),
              style: text.bodyLarge,
            ),
          ],
        ),
        const SizedBox(height: 22),
        card(
          key: const ValueKey('about-why'),
          children: [
            Text(
              'ทำไมถึงทำแอพนี้',
              style: headingStyle(context, text.titleMedium),
            ),
            const SizedBox(height: 8),
            Text(
              'แอพนี้เกิดจากปัญหาส่วนตัวของผู้พัฒนาเอง เวลาเล่นบอร์ดเกมกับเพื่อน '
              'มักเจอเรื่องเดิม ๆ ซ้ำ ๆ แบงก์กระดาษหายหรือนับผิด จำไม่ได้ว่าใคร'
              'จ่ายใครไปเท่าไร นับคะแนนรายรอบแล้วเถียงกัน เลยลงมือทำแอพนี้ขึ้นมา'
              'แก้ปัญหาพวกนั้น ให้เกมเดินต่อได้โดยกดน้อยที่สุด',
              key: const ValueKey('about-why-text'),
              style: text.bodyLarge,
            ),
          ],
        ),
        const SizedBox(height: 22),
        card(
          key: const ValueKey('about-developer'),
          children: [
            Text('ผู้พัฒนา', style: headingStyle(context, text.titleMedium)),
            const SizedBox(height: 8),
            Text(
              developerName,
              key: const ValueKey('about-developer-name'),
              style: text.titleLarge,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const ValueKey('about-github'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openGithub(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(LucideIcons.gitBranch, color: accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'github.com/$developerName',
                              style: text.bodyLarge?.copyWith(
                                decoration: TextDecoration.underline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            LucideIcons.externalLink,
                            size: 18,
                            color: muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('about-copy-github'),
                  tooltip: 'คัดลอกลิงก์',
                  icon: const Icon(LucideIcons.copy),
                  onPressed: () => _copyGithub(context, 'คัดลอกลิงก์แล้ว'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
