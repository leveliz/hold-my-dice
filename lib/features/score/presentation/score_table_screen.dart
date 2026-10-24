import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/presentation/score_table.dart';

/// The whole scoreboard to read (no editing), opened from the summary.
class ScoreTableScreen extends ConsumerWidget {
  const ScoreTableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(scoreProvider);
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const Text('ตารางคะแนน')),
      body: game == null
          ? const SizedBox.shrink()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                child: ScoreTable(game: game),
              ),
            ),
    );
  }
}
