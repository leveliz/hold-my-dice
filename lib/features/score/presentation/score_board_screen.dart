import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:hold_my_dice/features/score/presentation/score_entry_sheet.dart';
import 'package:hold_my_dice/features/score/presentation/score_table.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The scoreboard while playing: tap a cell to enter or correct a score, then
/// finish the round once everyone has one.
class ScoreBoardScreen extends ConsumerStatefulWidget {
  const ScoreBoardScreen({super.key});

  @override
  ConsumerState<ScoreBoardScreen> createState() => _ScoreBoardScreenState();
}

class _ScoreBoardScreenState extends ConsumerState<ScoreBoardScreen> {
  late final ScreenAwake _awake;

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider)..enable();
  }

  @override
  void dispose() {
    _awake.disable();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('leave-dialog'),
        title: const Text('ออกจากเกมนี้?'),
        content: const Text('เกมที่กำลังเล่นอยู่จะหายไป'),
        actions: [
          TextButton.icon(
            key: const ValueKey('leave-stay'),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(LucideIcons.play),
            label: const Text('เล่นต่อ'),
          ),
          FilledButton.icon(
            key: const ValueKey('leave-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(LucideIcons.logOut),
            label: const Text('ออกจากเกม'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      ref.read(scoreProvider.notifier).end();
      context.go('/');
    }
  }

  Future<void> _confirmEnd() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('end-dialog'),
        title: const Text('จบเกมตอนนี้?'),
        content: const Text('จะดูอันดับตามคะแนนที่กรอกไว้แล้ว'),
        actions: [
          TextButton.icon(
            key: const ValueKey('end-stay'),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(LucideIcons.play),
            label: const Text('เล่นต่อ'),
          ),
          FilledButton.icon(
            key: const ValueKey('end-confirm'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(LucideIcons.flag),
            label: const Text('จบเกม'),
          ),
        ],
      ),
    );
    if (end == true && mounted) {
      ref.read(scoreProvider.notifier).endNow();
      context.pushReplacement('/score/summary');
    }
  }

  void _finishRound() {
    ref.read(scoreProvider.notifier).finishRound();
    if (ref.read(scoreProvider)!.isOver) {
      context.pushReplacement('/score/summary');
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(scoreProvider);
    if (game == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Score Snitch')),
        body: const Center(child: Text('ยังไม่ได้เริ่มเกม')),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Score Snitch'),
          ),
          actions: [
            IconButton(
              key: const ValueKey('end-game-button'),
              tooltip: 'จบเกม',
              icon: const Icon(LucideIcons.flag),
              onPressed: _confirmEnd,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _InfoRow(game: game),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ScoreTable(
                    game: game,
                    onCellTap: (round, playerIndex) => showScoreEntrySheet(
                      context,
                      round: round,
                      playerIndex: playerIndex,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FilledButton.icon(
                  key: const ValueKey('finish-round'),
                  onPressed: game.canFinishRound ? _finishRound : null,
                  icon: const Icon(LucideIcons.check),
                  label: Text(game.targetReached ? 'จบรอบและจบเกม' : 'จบรอบ'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    textStyle: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "รอบ 4/10", who leads, and how far the leader is from the target.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.game});

  final ScoreGame game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final distance = game.distanceToTarget;

    String? targetInfo;
    if (distance != null) {
      targetInfo = game.targetReached
          ? 'ถึงเป้า ${formatMoney(game.targetScore!)} แล้ว จบรอบนี้เพื่อจบเกม'
          : 'ห่างเป้า ${formatMoney(distance)}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            key: const ValueKey('score-round-pill'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'รอบ ${game.roundNumber}/${game.roundCount}',
              style: text.titleSmall,
            ),
          ),
          if (game.leaders.isNotEmpty) ...[
            Text('นำอยู่', style: text.bodyMedium?.copyWith(color: muted)),
            for (final p in game.leaders)
              Container(
                key: ValueKey('score-leader-${p.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: Color(p.color).withValues(alpha: 0.2),
                  border: Border.all(color: Color(p.color), width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(p.name, style: text.titleSmall),
              ),
          ],
          if (targetInfo != null)
            Text(
              targetInfo,
              key: const ValueKey('score-target-info'),
              style: text.bodyMedium?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}
