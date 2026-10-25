import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/hub/saved_games.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Games that were left unfinished, each with a way to carry on or drop it.
class SavedGamesTab extends ConsumerWidget {
  const SavedGamesTab({super.key, required this.bottomSpace});

  final double bottomSpace;

  Future<void> _continue(
    BuildContext context,
    WidgetRef ref,
    SavedGame game,
  ) async {
    game.restore();
    await context.push(game.route);
    ref.invalidate(savedGamesProvider);
  }

  Future<void> _discard(
    BuildContext context,
    WidgetRef ref,
    SavedGame game,
  ) async {
    final drop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('discard-dialog'),
        title: Text('ทิ้งเกม ${game.helperName}?'),
        content: const Text('เกมที่เล่นค้างอยู่จะหายไป เอากลับมาไม่ได้'),
        actions: [
          TextButton.icon(
            key: const ValueKey('discard-keep'),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(LucideIcons.play),
            label: const Text('เก็บไว้'),
          ),
          FilledButton.icon(
            key: const ValueKey('discard-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(LucideIcons.trash2),
            label: const Text('ทิ้งเกม'),
          ),
        ],
      ),
    );
    if (drop != true) return;
    await game.clear();
    ref.invalidate(savedGamesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(savedGamesProvider).value;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    if (games == null) return const SizedBox.shrink();
    if (games.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(32, 0, 32, bottomSpace),
        child: Center(
          child: Column(
            key: const ValueKey('saved-empty'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.history, size: 44, color: muted),
              const SizedBox(height: 12),
              Text('ไม่มีเกมที่เล่นค้างอยู่', style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                'เกมที่ยังไม่จบจะมารออยู่ตรงนี้ ปิดแอพแล้วกลับมาเล่นต่อได้',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(20, 22, 20, bottomSpace),
      itemCount: games.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        final game = games[i];
        final helper = helperById(game.helperId);
        return SizedBox(
          height: 132,
          child: GradientCard(
            key: ValueKey('saved-${game.helperId}'),
            accent: helper.color,
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: helper.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(helper.icon, color: helper.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(game.helperName, style: text.titleMedium),
                            Text(
                              game.detail,
                              key: ValueKey('saved-detail-${game.helperId}'),
                              style: text.bodyMedium?.copyWith(color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        key: ValueKey('saved-discard-${game.helperId}'),
                        onPressed: () => _discard(context, ref, game),
                        icon: const Icon(LucideIcons.trash2),
                        label: const Text('ทิ้ง'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: ValueKey('saved-continue-${game.helperId}'),
                        onPressed: () => _continue(context, ref, game),
                        icon: const Icon(LucideIcons.play),
                        label: const Text('เล่นต่อ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
