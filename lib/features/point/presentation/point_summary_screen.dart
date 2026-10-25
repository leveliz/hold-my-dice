import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:hold_my_dice/features/point/presentation/point_setup_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Color _colorOf(Side side) => side == Side.red ? pointRed : pointBlue;

/// End of the game: rounds won by each side and every round's score.
class PointSummaryScreen extends ConsumerWidget {
  const PointSummaryScreen({super.key});

  void _leave(BuildContext context, WidgetRef ref, String location) {
    ref.read(pointProvider.notifier).end();
    context.go(location);
  }

  /// The side that won more rounds, or null when level.
  static Side? _overallWinner(PointGame game) {
    final red = game.roundsWon(Side.red);
    final blue = game.roundsWon(Side.blue);
    if (red == blue) return null;
    return red > blue ? Side.red : Side.blue;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(pointProvider);
    if (game == null) return const Scaffold();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final winner = _overallWinner(game);
    final left = game.leftSide;

    Widget teamName(Side side) => Expanded(
      child: Text(
        game.nameOf(side),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: side == left ? TextAlign.start : TextAlign.end,
        style: text.titleLarge?.copyWith(color: _colorOf(side)),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(context, ref, '/');
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          automaticallyImplyLeading: false,
          title: const Text('สรุปผลเกม'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    teamName(left),
                    Text(
                      '${game.roundsWon(left)} – ${game.roundsWon(left.other)}',
                      key: const ValueKey('summary-score'),
                      style: text.displaySmall,
                    ),
                    teamName(left.other),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  winner == null
                      ? (game.rounds.isEmpty ? 'ยังไม่มีรอบที่จบ' : 'ผลเสมอกัน')
                      : '${game.nameOf(winner)} ชนะ',
                  key: const ValueKey('summary-headline'),
                  style: text.titleMedium?.copyWith(color: muted),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  itemCount: game.rounds.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = game.rounds[i];
                    final side = r.winner;
                    final accent = side == null ? Colors.grey : _colorOf(side);
                    return SizedBox(
                      height: 64,
                      child: GradientCard(
                        key: ValueKey('round-${i + 1}'),
                        accent: accent,
                        radius: 20,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text('รอบ ${i + 1}', style: text.titleMedium),
                              const Spacer(),
                              Text(
                                '${r.pointsOf(left)} – ${r.pointsOf(left.other)}',
                                key: ValueKey('round-score-${i + 1}'),
                                style: text.titleLarge,
                              ),
                              const Spacer(),
                              Text(
                                side == null ? 'เสมอ' : game.nameOf(side),
                                key: ValueKey('round-winner-${i + 1}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium?.copyWith(color: muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('play-again'),
                      onPressed: () => _leave(context, ref, '/point'),
                      icon: const Icon(LucideIcons.rotateCcw),
                      label: const Text('เล่นอีกครั้ง'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        textStyle: text.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const ValueKey('back-to-hub'),
                      onPressed: () => _leave(context, ref, '/'),
                      icon: const Icon(LucideIcons.house),
                      label: const Text('กลับหน้าหลัก'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        textStyle: text.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
