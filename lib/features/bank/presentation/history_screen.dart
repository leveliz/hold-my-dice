import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/application/entry_labels.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';

/// Read-only list of every transaction in this game, newest first.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(bankProvider)?.game;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final entries = game == null ? <Entry>[] : game.history.reversed.toList();

    return Scaffold(
      appBar: HelperAppBar(toolbarHeight: 72, title: const Text('ประวัติ')),
      body: entries.isEmpty
          ? Center(
              key: const ValueKey('history-empty'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ยังไม่มีรายการ', style: text.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'ธุรกรรมที่ทำในเกมนี้จะมาอยู่ที่นี่',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final entry = entries[i];
                final label = describeEntry(game!, entry);
                final main = entry.transactions.last;
                final colorId =
                    entry.bankruptPlayerId ??
                    (main.from != Transaction.bank ? main.from : main.to);
                final dot = Color(
                  game.players.firstWhere((p) => p.id == colorId).color,
                );
                return Container(
                  key: ValueKey('history-row-$i'),
                  padding: const EdgeInsets.all(16),
                  decoration: tileDecoration(context),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label.title,
                              key: ValueKey('history-title-$i'),
                              style: text.titleMedium,
                            ),
                            if (label.subtitle case final sub?)
                              Text(
                                sub,
                                key: ValueKey('history-subtitle-$i'),
                                style: text.bodyMedium?.copyWith(color: muted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
