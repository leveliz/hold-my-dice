import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/stamp.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/hub/saved_games.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The two buttons on a ticket are short, so title and buttons fit its height.
final _ticketButton = ButtonStyle(
  minimumSize: WidgetStateProperty.all(const Size(0, 36)),
  padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Games that were left unfinished, each with a way to carry on or drop it.
/// On paper each game is a ticket: a stamp on the stub, then the details.
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
    final paper = PaperStyle.maybeOf(context) != null;
    final muted = paper
        ? PaperStyle.kraft
        : theme.colorScheme.onSurface.withValues(alpha: 0.65);

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
              Text(
                'ไม่มีเกมที่เล่นค้างอยู่',
                style: paper ? serifStyle(text.titleLarge) : text.titleLarge,
              ),
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
      padding: EdgeInsets.fromLTRB(20, 22, paper ? 26 : 20, bottomSpace),
      itemCount: games.length,
      separatorBuilder: (_, _) => SizedBox(height: paper ? 22 : 14),
      itemBuilder: (context, i) {
        final game = games[i];
        final helper = helperById(game.helperId);
        final accent = paper ? helper.paperColor : helper.color;

        final buttons = Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (paper)
              DashedBorder(
                color: PaperStyle.kraft,
                radius: 6,
                strokeWidth: 1.5,
                child: TextButton(
                  key: ValueKey('saved-discard-${game.helperId}'),
                  onPressed: () => _discard(context, ref, game),
                  style: _ticketButton,
                  child: const Text('ทิ้ง'),
                ),
              )
            else
              TextButton.icon(
                key: ValueKey('saved-discard-${game.helperId}'),
                onPressed: () => _discard(context, ref, game),
                icon: const Icon(LucideIcons.trash2),
                label: const Text('ทิ้ง'),
              ),
            const SizedBox(width: 8),
            if (paper)
              FilledButton(
                key: ValueKey('saved-continue-${game.helperId}'),
                onPressed: () => _continue(context, ref, game),
                style: _ticketButton,
                child: const Text('เล่นต่อ'),
              )
            else
              FilledButton.icon(
                key: ValueKey('saved-continue-${game.helperId}'),
                onPressed: () => _continue(context, ref, game),
                icon: const Icon(LucideIcons.play),
                label: const Text('เล่นต่อ'),
              ),
          ],
        );

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              game.helperName,
              style: paper ? serifStyle(text.titleMedium) : text.titleMedium,
            ),
            Text(
              game.detail,
              key: ValueKey('saved-detail-${game.helperId}'),
              style: text.bodyMedium?.copyWith(color: muted),
            ),
          ],
        );

        return SizedBox(
          height: paper ? 124 : 132,
          child: GradientCard(
            key: ValueKey('saved-${game.helperId}'),
            accent: helper.color,
            radius: 24,
            child: paper
                ? Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Center(
                          child: Stamp(
                            key: ValueKey('saved-stamp-${game.helperId}'),
                            color: accent,
                            size: 44,
                            tilt: -8,
                            child: Icon(helper.icon),
                          ),
                        ),
                      ),
                      // The perforation between stub and ticket.
                      Container(
                        key: const ValueKey('ticket-perforation'),
                        width: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        child: CustomPaint(
                          painter: _PerforationPainter(PaperStyle.dash),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [details, const Spacer(), buttons],
                          ),
                        ),
                      ),
                    ],
                  )
                : Padding(
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
                            Expanded(child: details),
                          ],
                        ),
                        const Spacer(),
                        buttons,
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _PerforationPainter extends CustomPainter {
  const _PerforationPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var y = 0.0; y < size.height; y += 8) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + 5 > size.height ? size.height : y + 5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => old.color != color;
}
