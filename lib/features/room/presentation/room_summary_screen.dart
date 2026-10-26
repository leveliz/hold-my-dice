import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/domain/standings.dart';
import 'package:hold_my_dice/features/room/presentation/room_error_text.dart';
import 'package:hold_my_dice/features/room/presentation/room_game_screen.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _gold = Color(0xFFC8962A);

/// Gold text that can be read on the light and on the dark ground.
Color _goldText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF0C060)
    : const Color(0xFF8A5E00);

/// The colour of a rank number: gold, silver, bronze, then plain.
Color? _rankColor(int rank) => switch (rank) {
  1 => _gold,
  2 => const Color(0xFF8E959C),
  3 => const Color(0xFFB87333),
  _ => null,
};

/// What everybody in the room sees once the game has ended: the ranking, as a
/// podium for the first three and a list for the rest. Every balance is
/// shown, whatever the room hid while it was played.
class RoomSummaryScreen extends ConsumerStatefulWidget {
  const RoomSummaryScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<RoomSummaryScreen> createState() => _RoomSummaryScreenState();
}

class _RoomSummaryScreenState extends ConsumerState<RoomSummaryScreen> {
  String get code => widget.code;

  @override
  void initState() {
    super.initState();
    // A message from the game (somebody went out, a refusal) would sit over
    // the buttons of the summary.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(roomGameProvider(code));
    return Scaffold(
      key: const ValueKey('room-summary'),
      appBar: HelperAppBar(title: Text('โต๊ะ $code')),
      body: game.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(roomErrorText(e))),
        data: (view) => _Summary(code: code, view: view),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.code, required this.view});

  final String code;
  final RoomGameView view;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ranking = standings(
      seats: view.seats,
      balances: view.balances,
      bankrupt: view.state.bankrupt,
    );
    final podium = ranking.take(3).toList();
    final rest = ranking.skip(3).toList();
    Widget step(int index, double height) => Expanded(
      flex: index == 0 ? 6 : 5,
      child: _Step(
        standing: podium[index],
        name: view.nameOf(podium[index].seat),
        color: Color(view.colorOf(podium[index].seat) ?? 0xFF8A8A8A),
        height: height,
      ),
    );
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              children: [
                Text(
                  'จบเกมแล้ว',
                  style: headingStyle(context, text.headlineSmall),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (podium.length > 1) ...[
                      step(1, 200),
                      const SizedBox(width: 8),
                    ],
                    step(0, 262),
                    if (podium.length > 2) ...[
                      const SizedBox(width: 8),
                      step(2, 176),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                for (final s in rest) ...[
                  _Row(
                    standing: s,
                    name: view.nameOf(s.seat),
                    color: Color(view.colorOf(s.seat) ?? 0xFF8A8A8A),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  key: const ValueKey('summary-home'),
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('กลับหน้าแรก'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('summary-history'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => RoomHistorySheet(code: code),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('ดูประวัติทั้งหมด'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One step of the podium.
class _Step extends StatelessWidget {
  const _Step({
    required this.standing,
    required this.name,
    required this.color,
    required this.height,
  });

  final Standing standing;
  final String name;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final winner = standing.rank == 1;
    return Container(
      key: ValueKey('podium-${standing.seat}'),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border.all(
          color: winner ? _gold : Theme.of(context).dividerColor,
          width: winner ? 2.5 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              if (winner)
                const Icon(LucideIcons.trophy, size: 22, color: _gold),
              PlayerAvatar(name: name, color: color, size: winner ? 36 : 30),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.titleSmall,
              ),
              if (winner)
                Text(
                  'ผู้ชนะ',
                  style: text.bodyMedium?.copyWith(
                    color: _goldText(context),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else if (standing.out)
                Text(
                  'ล้มละลาย',
                  style: text.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
          Column(
            children: [
              if (!standing.out)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(standing.balance),
                    style: serifStyle(
                      (winner ? text.titleLarge : text.titleMedium)?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Text(
                '${standing.rank}',
                style: text.titleLarge?.copyWith(
                  color: _rankColor(standing.rank),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A line of the ranking below the podium.
class _Row extends StatelessWidget {
  const _Row({required this.standing, required this.name, required this.color});

  final Standing standing;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: ValueKey('standing-${standing.seat}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: tileDecoration(context),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${standing.rank}', style: text.titleMedium),
          ),
          PlayerAvatar(name: name, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium,
            ),
          ),
          if (standing.out)
            const RoomChip('ล้มละลาย')
          else
            Text(
              formatMoney(standing.balance),
              style: serifStyle(
                text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
