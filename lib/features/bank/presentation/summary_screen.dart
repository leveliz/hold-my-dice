import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// End of the game: players ranked by the money they have left.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  void _leave(BuildContext context, WidgetRef ref, String location) {
    ref.read(bankProvider.notifier).end();
    context.go(location);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(bankProvider)?.game;
    if (game == null) return const Scaffold();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final ranking = game.ranking;
    final winner = game.winner;

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
                    winner != null
                        ? 'ผู้ชนะคือ ${winner.name}'
                        : 'จบเกมแล้ว เรียงตามเงินที่เหลือ',
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
                    final p = ranking[i];
                    final out = game.isBankrupt(p.id);
                    final accent = out ? Colors.grey : Color(p.color);
                    final first = i == 0 && !out;
                    return SizedBox(
                      height: first ? 96 : 72,
                      child: GradientCard(
                        key: ValueKey('rank-${p.id}'),
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
                                        '${i + 1}',
                                        key: ValueKey('rank-number-${p.id}'),
                                        style: text.titleLarge,
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: first
                                      ? text.titleLarge
                                      : text.titleMedium,
                                ),
                              ),
                              if (out)
                                Text(
                                  'ล้มละลาย',
                                  key: ValueKey('rank-out-${p.id}'),
                                  style: text.titleMedium,
                                )
                              else
                                BalanceChip(
                                  key: ValueKey('rank-balance-${p.id}'),
                                  amount: game.balanceOf(p.id),
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
                    FilledButton.icon(
                      key: const ValueKey('play-again'),
                      onPressed: () => _leave(context, ref, '/bank'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        textStyle: text.titleLarge,
                      ),
                      icon: const Icon(LucideIcons.rotateCcw),
                      label: const Text('เล่นอีกครั้ง'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const ValueKey('back-to-hub'),
                      onPressed: () => _leave(context, ref, '/'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        textStyle: text.titleMedium,
                      ),
                      icon: const Icon(LucideIcons.house),
                      label: const Text('กลับหน้าหลัก'),
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
