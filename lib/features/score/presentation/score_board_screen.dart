import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/end_game_button.dart';
import 'package:hold_my_dice/core/widgets/end_game_icon.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/tour/tour_host.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
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

class _ScoreBoardScreenState extends ConsumerState<ScoreBoardScreen>
    with TourHost<ScoreBoardScreen> {
  late final ScreenAwake _awake;

  // What the first-run tour points at.
  final _infoKey = GlobalKey();
  final _tableKey = GlobalKey();
  final _cellKey = GlobalKey();
  final _finishKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider)..enable();
    offerTour(
      storage: ref.read(tourStorageProvider),
      id: TourIds.score,
      steps: _tourSteps,
    );
  }

  List<TourStep> _tourSteps() => [
    TourStep(
      title: 'รอบและคนนำ',
      body:
          'บอกว่าเล่นถึงรอบที่เท่าไร และเมื่อมีคะแนนแล้วจะบอกด้วยว่าใครนำอยู่',
      target: _infoKey,
    ),
    TourStep(
      title: 'ตารางคะแนน',
      body:
          'แถวคือรอบ คอลัมน์คือผู้เล่น ถ้าผู้เล่นเยอะ เลื่อนตารางไปทางซ้ายขวาได้',
      target: _tableKey,
    ),
    TourStep(
      title: 'กรอกคะแนน',
      body:
          'แตะช่องว่างของรอบนี้แล้วพิมพ์คะแนน พิมพ์สูตรได้ เช่น 3+5+2 กดตกลงแล้วจะไปช่องของคนถัดไปเอง',
      target: _cellKey,
      gesture: TourGesture.tap,
    ),
    TourStep(
      title: 'จบรอบ',
      body: 'กรอกครบทุกคนแล้วกดจบรอบ ปุ่มจะกดได้เมื่อกรอกครบ',
      target: _finishKey,
    ),
    TourStep(
      title: 'แก้คะแนนที่ผิด',
      body:
          'แตะช่องของรอบไหนก็ได้เพื่อแก้ ยอดรวมคำนวณใหม่ทันที จึงไม่มีปุ่มเลิกทำ',
      target: _tableKey,
    ),
  ];

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
        title: const Text('ออกจากหน้าเกม?'),
        content: const Text('เกมจะถูกเก็บไว้ในเมนูเกมค้าง กลับมาเล่นต่อได้'),
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
            label: const Text('ออกไปก่อน'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      ref.read(scoreProvider.notifier).leave();
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
            icon: const EndGameIcon(),
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
        appBar: HelperAppBar(title: const Text('Score Snitch')),
        body: const Center(child: Text('ยังไม่ได้เริ่มเกม')),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: HelperAppBar(
          toolbarHeight: 72,
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Score Snitch'),
          ),
          actions: [
            EndGameButton(
              key: const ValueKey('end-game-button'),
              onPressed: _confirmEnd,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              KeyedSubtree(
                key: _infoKey,
                child: _InfoRow(game: game),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ScoreTable(
                    key: _tableKey,
                    game: game,
                    firstEmptyCellKey: _cellKey,
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
                child: KeyedSubtree(
                  key: _finishKey,
                  child: FilledButton.icon(
                    key: const ValueKey('finish-round'),
                    onPressed: game.canFinishRound ? _finishRound : null,
                    icon: const Icon(LucideIcons.check),
                    label: Text(game.targetReached ? 'จบรอบและจบเกม' : 'จบรอบ'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      textStyle: Theme.of(context).textTheme.titleLarge,
                    ),
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
              color: PaperStyle.maybeOf(context) != null
                  ? null
                  : theme.colorScheme.onSurface.withValues(alpha: 0.09),
              border: PaperStyle.maybeOf(context) != null
                  ? Border.all(color: PaperStyle.ink, width: 1.5)
                  : null,
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
