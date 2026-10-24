import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';
import 'package:hold_my_dice/features/bank/presentation/drag_tile.dart';
import 'package:hold_my_dice/features/bank/presentation/game_actions.dart';
import 'package:hold_my_dice/features/bank/presentation/player_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// Card heights (dp). Tall cards show at most [maxTallPlayers]; with more
// players, or on a short screen, rows switch to the compact single-line card.
const maxTallPlayers = 4;
const _tallMin = 112.0;
const _tallMax = 150.0;
const _compactMin = 60.0;
const _compactMax = 92.0;
const _gap = 12.0;
const _undoSlotHeight = 54.0;
const _listPadding = EdgeInsets.fromLTRB(16, 4, 16, 12);
const _bankRadius = 24.0;
const _bankColor = Color(0xFF3A4CC0);

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  /// Id of the tile being dragged right now ('bank' or a player id).
  final _dragging = ValueNotifier<String?>(null);
  late final ScreenAwake _awake;

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider)..enable();
  }

  @override
  void dispose() {
    _awake.disable();
    _dragging.dispose();
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
      ref.read(bankProvider.notifier).end();
      context.go('/');
    }
  }

  Future<void> _confirmEnd() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('end-dialog'),
        title: const Text('จบเกมตอนนี้?'),
        content: const Text('จะดูอันดับตามเงินที่เหลือของทุกคน'),
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
    if (end == true && mounted) context.pushReplacement('/bank/summary');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(bankProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pocket Banker')),
        body: const Center(child: Text('ยังไม่ได้เริ่มเกม')),
      );
    }
    final game = session.game;
    final players = game.players;
    final notifier = ref.read(bankProvider.notifier);
    final actions = GameActions(context, ref);

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
            child: Text('Pocket Banker'),
          ),
          actions: [
            IconButton(
              key: const ValueKey('history-button'),
              tooltip: 'ประวัติ',
              icon: const Icon(LucideIcons.history),
              onPressed: () => context.push('/bank/history'),
            ),
            IconButton(
              key: const ValueKey('end-game-button'),
              tooltip: 'จบเกม',
              icon: const Icon(LucideIcons.flag),
              onPressed: _confirmEnd,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final n = players.length;
                  final available =
                      constraints.maxHeight -
                      _listPadding.vertical -
                      _gap * (n - 1);
                  final perCard = available / n;
                  final tall = n <= maxTallPlayers && perCard >= _tallMin;
                  final height = tall
                      ? perCard.clamp(_tallMin, _tallMax).toDouble()
                      : perCard.clamp(_compactMin, _compactMax).toDouble();
                  return ListView.separated(
                    padding: _listPadding,
                    itemCount: n,
                    separatorBuilder: (_, _) => const SizedBox(height: _gap),
                    itemBuilder: (context, i) {
                      final p = players[i];
                      final out = game.isBankrupt(p.id);
                      return SizedBox(
                        height: height,
                        child: DragTile(
                          id: p.id,
                          enabled: !out,
                          accent: Color(p.color),
                          radius: PlayerCard.radiusFor(compact: !tall),
                          feedbackLabel: p.name,
                          dragging: _dragging,
                          onDrop: (source) => actions.handleDrop(source, p.id),
                          child: PlayerCard(
                            player: p,
                            balance: game.balanceOf(p.id),
                            compact: !tall,
                            bankrupt: out,
                            onReceive: () => actions.receive(p),
                            onPay: () => actions.payBank(p),
                            onGo: () => notifier.passGo(p.id),
                            onTap: () => actions.pickRecipientAndTransfer(p),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _Dock(
              session: session,
              onUndo: notifier.undo,
              dragging: _dragging,
              onDrop: (source) => actions.handleDrop(source, Transaction.bank),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.session,
    required this.onUndo,
    required this.dragging,
    required this.onDrop,
  });

  final BankSession session;
  final VoidCallback onUndo;
  final ValueNotifier<String?> dragging;
  final void Function(String sourceId) onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Space for the undo bar is always reserved so the cards above
            // never shift while people are tapping.
            SizedBox(
              height: _undoSlotHeight,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: session.undoAvailable
                    ? Align(
                        key: const ValueKey('undo-bar'),
                        alignment: Alignment.center,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  session.lastLabel ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(
                                    color: theme.colorScheme.surface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                key: const ValueKey('undo-button'),
                                onPressed: onUndo,
                                icon: const Icon(LucideIcons.undo2, size: 18),
                                label: const Text('เลิกทำ'),
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.surface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            DragTile(
              id: Transaction.bank,
              enabled: true,
              accent: _bankColor,
              radius: _bankRadius,
              feedbackLabel: 'ธนาคาร',
              dragging: dragging,
              onDrop: onDrop,
              child: Container(
                key: const ValueKey('bank-card'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_bankRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: theme.brightness == Brightness.dark
                        ? const [Color(0xFF4A5BE0), Color(0xFF2B3181)]
                        : const [Color(0xFF3A4CC0), Color(0xFF16163F)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D16163F),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.landmark,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'ธนาคาร',
                      style: text.titleLarge?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
