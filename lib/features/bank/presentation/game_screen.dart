import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/widgets/end_game_button.dart';
import 'package:hold_my_dice/core/widgets/end_game_icon.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/dashed_line.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/tour/tour_host.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
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

/// From this width the players go in two columns.
const _twoColumnsWidth = 720.0;
const _undoSlotHeight = 54.0;
const _listPadding = EdgeInsets.fromLTRB(16, 4, 16, 12);
const _bankRadius = 24.0;
const _bankColor = Color(0xFF3A4CC0);

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with TourHost<GameScreen> {
  /// Id of the tile being dragged right now ('bank' or a player id).
  final _dragging = ValueNotifier<String?>(null);
  late final ScreenAwake _awake;
  bool _hideBalances = false;

  // What the first-run tour points at.
  final _firstCardKey = GlobalKey();
  final _secondCardKey = GlobalKey();
  final _buttonsKey = GlobalKey();
  final _barKey = GlobalKey();
  final _bankKey = GlobalKey();
  final _undoKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider)..enable();
    final tours = ref.read(tourStorageProvider);
    offerTour(
      storage: tours,
      id: TourIds.bank,
      alsoSeenOnSkip: TourIds.bankTips,
      steps: _tourSteps,
    );
    ref.listenManual(bankProvider.select((s) => s?.undoAvailable ?? false), (
      _,
      now,
    ) {
      if (now) {
        offerTour(
          storage: tours,
          id: TourIds.bankUndoTip,
          steps: () => [
            TourStep(
              title: 'เลิกทำ',
              body: 'กดผิดแตะตรงนี้เพื่อย้อนรายการล่าสุด ย้อนได้ 1 รายการ',
              target: _undoKey,
            ),
          ],
        );
      }
    });
  }

  List<TourStep> _tourSteps() => [
    TourStep(
      title: 'เงินของแต่ละคน',
      body: 'ตัวเลขใหญ่บนการ์ดคือเงินที่ผู้เล่นคนนั้นมีอยู่',
      target: _firstCardKey,
    ),
    TourStep(
      title: 'ปุ่มรับ จ่าย และ GO',
      body:
          '+ รับเงินจากธนาคาร (เลือก "จำนอง" ได้ในหน้าใส่เงิน) · − จ่ายเงินให้ธนาคาร · GO ผ่านจุดเริ่ม',
      target: _buttonsKey,
      gesture: TourGesture.tap,
    ),
    TourStep(
      title: 'โอนให้ผู้เล่น',
      body: 'แตะที่การ์ด แล้วเลือกคนที่จะรับเงิน',
      target: _firstCardKey,
      gesture: TourGesture.tap,
    ),
    TourStep(
      title: 'ลากไปวางเพื่อโอน',
      body: 'กดการ์ดค้างไว้ แล้วลากไปวางบนผู้เล่นที่จะรับเงิน',
      target: _firstCardKey,
      destination: _secondCardKey,
      gesture: TourGesture.drag,
    ),
    TourStep(
      title: 'ลากไปวางที่ธนาคาร',
      body:
          'ลากการ์ดไปวางบนธนาคารเพื่อจ่ายเงิน หรือลากธนาคารมาวางบนผู้เล่นเพื่อรับเงิน',
      target: _firstCardKey,
      destination: _bankKey,
      gesture: TourGesture.drag,
    ),
    TourStep(
      title: 'ปุ่มบนแถบหัว',
      body: 'เรียงจากซ้ายไปขวา: ซ่อนยอดเงิน ดูประวัติ จบเกม',
      target: _barKey,
    ),
  ];

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
            icon: const EndGameIcon(),
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
        appBar: HelperAppBar(title: const Text('Pocket Banker')),
        body: const Center(child: Text('ยังไม่ได้เริ่มเกม')),
      );
    }
    final game = session.game;
    final players = game.players;
    final notifier = ref.read(bankProvider.notifier);
    final actions = GameActions(context, ref, hideBalances: _hideBalances);

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
            child: Text('Pocket Banker'),
          ),
          actions: [
            Row(
              key: _barKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('hide-balances-button'),
                  tooltip: _hideBalances ? 'แสดงยอดเงิน' : 'ซ่อนยอดเงิน',
                  icon: Icon(
                    _hideBalances ? LucideIcons.eyeOff : LucideIcons.eye,
                  ),
                  onPressed: () =>
                      setState(() => _hideBalances = !_hideBalances),
                ),
                IconButton(
                  key: const ValueKey('history-button'),
                  tooltip: 'ประวัติ',
                  icon: const Icon(LucideIcons.history),
                  onPressed: () => context.push('/bank/history'),
                ),
                EndGameButton(
                  key: const ValueKey('end-game-button'),
                  onPressed: _confirmEnd,
                ),
              ],
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
                  final columns = constraints.maxWidth >= _twoColumnsWidth
                      ? 2
                      : 1;
                  final rows = (n / columns).ceil();
                  // The first two players still in the game are what the
                  // tour points at.
                  final active = [
                    for (var i = 0; i < n; i++)
                      if (!game.isBankrupt(players[i].id)) i,
                  ];
                  final available =
                      constraints.maxHeight -
                      _listPadding.vertical -
                      _gap * (rows - 1);
                  final perCard = available / rows;
                  final tall = rows <= maxTallPlayers && perCard >= _tallMin;
                  final height = tall
                      ? perCard.clamp(_tallMin, _tallMax).toDouble()
                      : perCard.clamp(_compactMin, _compactMax).toDouble();
                  Widget tile(int i) {
                    final p = players[i];
                    final out = game.isBankrupt(p.id);
                    final tourKey = active.isNotEmpty && i == active[0]
                        ? _firstCardKey
                        : active.length > 1 && i == active[1]
                        ? _secondCardKey
                        : null;
                    return KeyedSubtree(
                      key: tourKey,
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
                          hideBalance: _hideBalances,
                          onReceive: () => actions.receive(p),
                          onPay: () => actions.payBank(p),
                          onGo: () => notifier.passGo(p.id),
                          onTap: () => actions.pickRecipientAndTransfer(p),
                          buttonsKey: i == active.firstOrNull
                              ? _buttonsKey
                              : null,
                        ),
                      ),
                    );
                  }

                  if (columns == 1) {
                    return ListView.separated(
                      padding: _listPadding,
                      itemCount: n,
                      separatorBuilder: (_, _) => const SizedBox(height: _gap),
                      itemBuilder: (context, i) =>
                          SizedBox(height: height, child: tile(i)),
                    );
                  }
                  return GridView.builder(
                    padding: _listPadding,
                    itemCount: n,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: height,
                      mainAxisSpacing: _gap,
                      crossAxisSpacing: _gap,
                    ),
                    itemBuilder: (context, i) => tile(i),
                  );
                },
              ),
            ),
            _Dock(
              session: session,
              bankKey: _bankKey,
              undoKey: _undoKey,
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
    required this.bankKey,
    required this.undoKey,
    required this.onUndo,
    required this.dragging,
    required this.onDrop,
  });

  final BankSession session;

  /// Mark the bank card and the undo slot for the first-run tour.
  final GlobalKey bankKey;
  final GlobalKey undoKey;
  final VoidCallback onUndo;
  final ValueNotifier<String?> dragging;
  final void Function(String sourceId) onDrop;

  /// The bank at the foot of the screen. Papery: an ink ticket with a dashed
  /// line inside and a kraft edge. Aurora: the blue gradient bar.
  Widget _bankCard(BuildContext context, TextTheme text, ThemeData theme) {
    final paper = PaperStyle.maybeOf(context) != null;
    final radius = GradientCard.radiusFor(context, _bankRadius);
    final row = Row(
      children: [
        Icon(
          LucideIcons.landmark,
          color: paper ? PaperStyle.onInk : Colors.white,
          size: 30,
        ),
        const SizedBox(width: 14),
        Text(
          'ธนาคาร',
          style: text.titleLarge?.copyWith(
            color: paper ? PaperStyle.onInk : Colors.white,
          ),
        ),
      ],
    );
    if (paper) {
      return Container(
        key: const ValueKey('bank-card'),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: PaperStyle.ink,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(color: PaperStyle.kraft, offset: Offset(3, 3)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -7,
              child: DashedLine(
                color: PaperStyle.onInk.withValues(alpha: 0.35),
                thickness: 1,
              ),
            ),
            row,
          ],
        ),
      );
    }
    return Container(
      key: const ValueKey('bank-card'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A5BE0), Color(0xFF2B3181)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D16163F),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: row,
    );
  }

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
            KeyedSubtree(
              key: undoKey,
              child: SizedBox(
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
            ),
            KeyedSubtree(
              key: bankKey,
              child: DragTile(
                id: Transaction.bank,
                enabled: true,
                accent: _bankColor,
                radius: _bankRadius,
                feedbackLabel: 'ธนาคาร',
                dragging: dragging,
                onDrop: onDrop,
                child: _bankCard(context, text, theme),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
