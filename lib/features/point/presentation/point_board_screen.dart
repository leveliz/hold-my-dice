import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/tour/tour_host.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:hold_my_dice/features/point/presentation/point_setup_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _serveYellow = Color(0xFFFFD60A);

/// A swipe down faster than this takes a point off.
const _swipeVelocity = 250.0;

Color _colorOf(Side side) => side == Side.red ? pointRed : pointBlue;

/// The scoreboard while playing: the screen is split in two halves, tap a
/// half for +1 and swipe down on it for -1.
class PointBoardScreen extends ConsumerStatefulWidget {
  const PointBoardScreen({super.key});

  @override
  ConsumerState<PointBoardScreen> createState() => _PointBoardScreenState();
}

class _PointBoardScreenState extends ConsumerState<PointBoardScreen>
    with TourHost<PointBoardScreen> {
  late final ScreenAwake _awake;
  late final ScreenMode _mode;
  var _asking = false;

  // What the first-run tour points at: things on the left and right halves of
  // the screen, whichever teams are sitting there.
  final _leftKey = GlobalKey();
  final _rightKey = GlobalKey();
  final _leftNameKey = GlobalKey();
  final _leftServeKey = GlobalKey();
  final _stripKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider)..enable();
    _mode = ref.read(screenModeProvider)..enterLandscapeImmersive();
    // A game saved between two rounds comes back asking who serves next.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final game = ref.read(pointProvider);
      if (mounted && game != null && game.betweenRounds && !game.isOver) {
        _askFirstServer();
      }
      // Offered once that question is on the screen, so the tour waits for it.
      if (!mounted) return;
      offerTour(
        storage: ref.read(tourStorageProvider),
        id: TourIds.point,
        // The board is laid out for a screen held sideways; measure it then.
        ready: () {
          final size = MediaQuery.sizeOf(context);
          return size.width > size.height;
        },
        steps: _tourSteps,
      );
    });
  }

  @override
  void dispose() {
    _mode.restore();
    _awake.disable();
    super.dispose();
  }

  PointNotifier get _notifier => ref.read(pointProvider.notifier);

  List<TourStep> _tourSteps() => [
    TourStep(
      title: 'แตะเพื่อเพิ่มแต้ม',
      body: 'แตะฝั่งไหน ฝั่งนั้นได้ 1 แต้มและได้เสิร์ฟ',
      target: _leftKey,
      gesture: TourGesture.tap,
    ),
    TourStep(
      title: 'ปัดลงเพื่อลดแต้ม',
      body: 'ปัดนิ้วลงเร็ว ๆ บนฝั่งไหน ฝั่งนั้นลด 1 แต้ม ปัดช้า ๆ จะไม่ลด',
      target: _rightKey,
      gesture: TourGesture.swipeDown,
    ),
    TourStep(
      title: 'ชื่อทีม',
      body: 'แตะชื่อทีมเพื่อแก้ชื่อ',
      target: _leftNameKey,
      gesture: TourGesture.tap,
    ),
    TourStep(
      title: 'ปุ่มกลางจอ',
      body:
          'เรียงจากบนลงล่าง: ย้อนกลับ · สลับฝั่ง · จบรอบ · รีเซ็ต (กดค้าง) · จบเกม',
      target: _stripKey,
    ),
    TourStep(
      title: 'เสิร์ฟ',
      body: 'แตะปุ่มเสิร์ฟเพื่อเปลี่ยนคนเสิร์ฟ',
      target: _leftServeKey,
      gesture: TourGesture.tap,
    ),
  ];

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
      _notifier.end();
      context.go('/');
    }
  }

  Future<void> _confirmEnd() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('end-dialog'),
        title: const Text('จบเกมตอนนี้?'),
        content: const Text('จะดูสรุปผลทุกรอบที่จบไปแล้ว'),
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
    if (end == true && mounted) _endGame();
  }

  void _endGame() {
    _notifier.endGame();
    context.pushReplacement('/point/summary');
  }

  Future<void> _finishRound() async {
    _notifier.finishRound();
    await _askFirstServer();
  }

  /// Between rounds: who serves first in the next one (or stop here).
  Future<void> _askFirstServer() async {
    if (_asking) return;
    _asking = true;
    final game = ref.read(pointProvider)!;
    final choice = await showDialog<Side?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Widget serveButton(Side side) => FilledButton(
          key: ValueKey('serve-first-${side.name}'),
          onPressed: () => Navigator.pop(context, side),
          style: FilledButton.styleFrom(
            backgroundColor: _colorOf(side),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
          ),
          child: Text(
            game.nameOf(side),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
        return PopScope(
          canPop: false,
          child: AlertDialog(
            key: const ValueKey('next-round-dialog'),
            title: Text(
              'เริ่มรอบที่ ${game.roundsFinished + 1} · ใครเสิร์ฟก่อน?',
            ),
            content: Row(
              children: [
                Expanded(child: serveButton(game.leftSide)),
                const SizedBox(width: 12),
                Expanded(child: serveButton(game.rightSide)),
              ],
            ),
            actions: [
              TextButton.icon(
                key: const ValueKey('end-after-round'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.flag),
                label: const Text('จบเกม'),
              ),
            ],
          ),
        );
      },
    );
    _asking = false;
    if (!mounted) return;
    if (choice == null) {
      _endGame();
    } else {
      _notifier.startNextRound(firstServer: choice);
    }
  }

  Future<void> _rename(Side side) async {
    final game = ref.read(pointProvider)!;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: game.nameOf(side)),
    );
    if (name != null && mounted) _notifier.rename(side, name);
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(pointProvider);
    if (game == null) {
      return const Scaffold(body: Center(child: Text('ยังไม่ได้เริ่มเกม')));
    }

    final upright =
        ref.watch(needsManualRotationProvider) &&
        MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: upright
            ? _RotateNotice(onLeave: _confirmLeave)
            : Stack(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: KeyedSubtree(
                          key: _leftKey,
                          child: _half(game, game.leftSide),
                        ),
                      ),
                      Expanded(
                        child: KeyedSubtree(
                          key: _rightKey,
                          child: _half(game, game.rightSide),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: KeyedSubtree(
                      key: _stripKey,
                      child: _ControlStrip(
                        game: game,
                        onUndo: _notifier.undo,
                        onSwap: _notifier.swapSides,
                        onFinish: _finishRound,
                        onReset: _notifier.reset,
                        onEnd: _confirmEnd,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    // Only the top is kept clear: a camera cut-out on one side must
                    // not push the chips off the seam between the halves.
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 8 + MediaQuery.paddingOf(context).top,
                      ),
                      child: _StatusChips(game: game),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _half(PointGame game, Side side) => _Half(
    game: game,
    side: side,
    onAdd: () => _notifier.addPoint(side),
    onRemove: () => _notifier.removePoint(side),
    onRename: () => _rename(side),
    onServe: () => _notifier.chooseServer(side),
    nameKey: side == game.leftSide ? _leftNameKey : null,
    serveKey: side == game.leftSide ? _leftServeKey : null,
  );
}

/// Shown in a browser while the device is upright: the board is built for a
/// screen held sideways and a web page cannot turn it.
class _RotateNotice extends StatelessWidget {
  const _RotateNotice({required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Center(
        key: const ValueKey('rotate-notice'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.smartphone, size: 56),
              const SizedBox(height: 16),
              Text('กรุณาหมุนจอ', style: text.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Point Blank เล่นในแนวนอน เกมที่เล่นอยู่ยังอยู่ครบ',
                textAlign: TextAlign.center,
                style: text.bodyLarge,
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                key: const ValueKey('rotate-leave'),
                onPressed: onLeave,
                icon: const Icon(LucideIcons.logOut),
                label: const Text('ออกจากเกม'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({
    required this.game,
    required this.side,
    required this.onAdd,
    required this.onRemove,
    required this.onRename,
    required this.onServe,
    this.nameKey,
    this.serveKey,
  });

  /// Mark the team name and the serve button for the first-run tour.
  final GlobalKey? nameKey;
  final GlobalKey? serveKey;

  final PointGame game;
  final Side side;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onRename;
  final VoidCallback onServe;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final points = game.pointsOf(side);
    final wins = game.roundsWon(side);
    final serving = game.serving == side;
    final inset = MediaQuery.paddingOf(context);

    return Semantics(
      label: '${game.nameOf(side)} $points แต้ม',
      button: true,
      child: GestureDetector(
        key: ValueKey('half-${side.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onAdd,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > _swipeVelocity) onRemove();
        },
        child: Container(
          color: _colorOf(side),
          padding: EdgeInsets.fromLTRB(
            16 + (side == game.leftSide ? inset.left : 0),
            12 + inset.top,
            16 + (side == game.leftSide ? 0 : inset.right),
            12 + inset.bottom,
          ),
          child: Column(
            children: [
              const SizedBox(height: 40),
              KeyedSubtree(
                key: nameKey,
                child: GestureDetector(
                  key: ValueKey('name-${side.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onRename,
                  child: Text(
                    game.nameOf(side),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ),
              Text(
                'ชนะ $wins รอบ',
                key: ValueKey('wins-${side.name}'),
                style: text.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$points',
                      key: ValueKey('score-${side.name}'),
                      style: text.displayLarge?.copyWith(
                        color: Colors.white,
                        fontSize: 240,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              KeyedSubtree(
                key: serveKey,
                child: GestureDetector(
                  key: ValueKey('serve-${side.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onServe,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: serving ? _serveYellow : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: serving
                            ? _serveYellow
                            : Colors.white.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'เสิร์ฟ',
                      style: text.titleMedium?.copyWith(
                        color: serving
                            ? Colors.black87
                            : Colors.white.withValues(alpha: 0.7),
                      ),
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

/// "รอบ 2 · เป้า 21 ดิวส์", and who has won the round once the rules say so.
class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.game});

  final PointGame game;

  String get _rulesText {
    final target = game.rules.target;
    if (target == null) return 'ไม่จำกัดแต้ม';
    final deuce = game.rules.deuce ? ' ดิวส์' : '';
    return 'เป้า ${formatMoney(target)}$deuce';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final winner = game.roundWinner;

    Widget pill(Key key, String label, {Color? fill, Color? ink}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: fill ?? Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: text.titleSmall?.copyWith(color: ink ?? Colors.white),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill(
          const ValueKey('round-chip'),
          'รอบ ${game.roundNumber} · $_rulesText',
        ),
        if (winner != null && game.canFinishRound) ...[
          const SizedBox(height: 6),
          pill(
            const ValueKey('round-winner-banner'),
            '${game.nameOf(winner)} ชนะรอบนี้ · กดจบรอบ',
            fill: _serveYellow,
            ink: Colors.black87,
          ),
        ],
      ],
    );
  }
}

/// The small column of buttons on the seam between the two halves.
class _ControlStrip extends StatelessWidget {
  const _ControlStrip({
    required this.game,
    required this.onUndo,
    required this.onSwap,
    required this.onFinish,
    required this.onReset,
    required this.onEnd,
  });

  final PointGame game;
  final VoidCallback onUndo;
  final VoidCallback onSwap;
  final VoidCallback onFinish;
  final VoidCallback onReset;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final decided = game.roundWinner != null && game.canFinishRound;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StripButton(
            key: const ValueKey('undo-button'),
            icon: LucideIcons.undo2,
            tooltip: 'เลิกทำ',
            onPressed: game.canUndo ? onUndo : null,
          ),
          _StripButton(
            key: const ValueKey('swap-button'),
            icon: LucideIcons.arrowLeftRight,
            tooltip: 'สลับฝั่ง',
            onPressed: onSwap,
          ),
          _StripButton(
            key: const ValueKey('finish-round'),
            icon: LucideIcons.check,
            tooltip: 'จบรอบ',
            highlighted: decided,
            onPressed: game.canFinishRound ? onFinish : null,
          ),
          _StripButton(
            key: const ValueKey('reset-button'),
            icon: LucideIcons.rotateCcw,
            tooltip: 'กดค้างเพื่อรีเซ็ตแต้มรอบนี้',
            onLongPress: onReset,
          ),
          _StripButton(
            key: const ValueKey('end-game-button'),
            icon: LucideIcons.flag,
            tooltip: 'จบเกม',
            onPressed: onEnd,
          ),
        ],
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  const _StripButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.onLongPress,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null || onLongPress != null;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed ?? (onLongPress == null ? null : () {}),
        onLongPress: onLongPress,
        radius: 28,
        child: Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlighted ? _serveYellow : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 24,
            color: highlighted
                ? Colors.black87
                : Colors.white.withValues(alpha: enabled ? 1 : 0.35),
          ),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('rename-dialog'),
      title: const Text('เปลี่ยนชื่อทีม'),
      content: TextField(
        key: const ValueKey('rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 12,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        FilledButton.icon(
          key: const ValueKey('rename-confirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          icon: const Icon(LucideIcons.check),
          label: const Text('ตกลง'),
        ),
      ],
    );
  }
}
