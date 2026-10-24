import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// End of the game: players ranked by the winning mode; equal scores share a
/// rank.
class ScoreSummaryScreen extends ConsumerWidget {
  const ScoreSummaryScreen({super.key});

  void _leave(BuildContext context, WidgetRef ref, String location) {
    ref.read(scoreProvider.notifier).end();
    context.go(location);
  }

  static String _headline(ScoreGame game) {
    final reason = switch (game.endReason) {
      EndReason.allRoundsPlayed => 'ครบ ${game.roundCount} รอบแล้ว',
      EndReason.targetReached =>
        'มีคนถึงเป้า ${formatMoney(game.targetScore ?? 0)}',
      _ => 'จบเกมก่อนกำหนด',
    };
    final winners = game.ranking.where((r) => r.rank == 1).toList();
    final names = winners.map((r) => r.player.name).join(', ');
    return '$reason · ${winners.length > 1 ? 'ผู้ชนะร่วม' : 'ผู้ชนะ'} $names';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(scoreProvider);
    if (game == null) return const Scaffold();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final ranking = game.ranking;

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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _headline(game),
                    key: const ValueKey('summary-headline'),
                    style: text.titleMedium?.copyWith(color: muted),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  itemCount: ranking.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final r = ranking[i];
                    final first = r.rank == 1;
                    final accent = Color(r.player.color);
                    return SizedBox(
                      height: first ? 88 : 72,
                      child: GradientCard(
                        key: ValueKey('rank-${r.player.id}'),
                        accent: accent,
                        radius: 24,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: first
                                    ? const Icon(LucideIcons.trophy)
                                    : Text(
                                        '${r.rank}',
                                        key: ValueKey(
                                          'rank-number-${r.player.id}',
                                        ),
                                        style: text.titleLarge,
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.player.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: first
                                      ? text.titleLarge
                                      : text.titleMedium,
                                ),
                              ),
                              BalanceChip(
                                key: ValueKey('rank-score-${r.player.id}'),
                                amount: r.total,
                                accent: accent,
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
                    FilledButton.tonalIcon(
                      key: const ValueKey('view-table'),
                      onPressed: () => context.push('/score/table'),
                      icon: const Icon(LucideIcons.table),
                      label: const Text('ดูตารางทุกรอบ'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        textStyle: text.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey('play-again'),
                      onPressed: () => _leave(context, ref, '/score'),
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
