import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/domain/standings.dart';
import 'package:hold_my_dice/features/room/presentation/room_error_text.dart';
import 'package:hold_my_dice/features/room/presentation/room_game_screen.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _gold = Color(0xFFC8962A);

/// How long after the end the room is taken down by a player's phone (the
/// rules let a player do it from then on; the owner may at any time).
const closeRoomAfter = Duration(minutes: 5);

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

class _Summary extends ConsumerStatefulWidget {
  const _Summary({required this.code, required this.view});

  final String code;
  final RoomGameView view;

  @override
  ConsumerState<_Summary> createState() => _SummaryState();
}

class _SummaryState extends ConsumerState<_Summary> {
  var _busy = false;

  String get code => widget.code;
  RoomGameView get view => widget.view;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _say(roomErrorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The owner opens the next game: a lobby with the same settings.
  Future<void> _playAgain(RoomMeta? meta) async {
    String? password;
    if (meta?.hasPassword ?? false) {
      password = await showDialog<String>(
        context: context,
        builder: (_) => const _AgainPasswordDialog(),
      );
      if (password == null) return;
    }
    await _run(() async {
      final next = await ref
          .read(roomRepositoryProvider)
          .playAgain(code, password: password);
      if (mounted) context.go('/room/${next.code}');
    });
  }

  /// The owner takes the room down after one question, then goes home.
  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('close-room-dialog'),
        title: const Text('ปิดห้องนี้?'),
        content: const Text(
          'ทุกคนจะดูสรุปและประวัติไม่ได้อีก และเอากลับมาไม่ได้',
        ),
        actions: [
          TextButton(
            key: const ValueKey('close-room-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ไม่ปิด'),
          ),
          FilledButton(
            key: const ValueKey('close-room-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ปิดห้อง'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await ref.read(roomRepositoryProvider).closeRoom(code);
      if (mounted) context.go('/');
    });
  }

  /// Follows the owner to the next game: a player of this game sits down in it
  /// at once; a watcher, or a room that asks for its password, goes to its
  /// join form.
  Future<void> _joinNext(String next) => _run(() async {
    final repo = ref.read(roomRepositoryProvider);
    final me = await repo.readMyMember(code);
    if (me != null && me.role == MemberRole.player) {
      try {
        await repo.joinAsPlayer(code: next, name: me.name, color: me.color);
      } on RoomException catch (e) {
        if (e.error != RoomError.wrongPassword) rethrow;
      }
    }
    if (mounted) context.go('/room/$next');
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meta = ref.watch(roomMetaProvider(code)).value;
    final nextCode = meta?.nextCode;
    final endedAt = meta?.endedAt;
    final owner = view.iAmOwner;
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
                const SizedBox(height: 12),
                if (nextCode != null)
                  _NextRoomBanner(
                    owner: owner,
                    busy: _busy,
                    onJoin: () => _joinNext(nextCode),
                  )
                else if (endedAt != null)
                  _CloseNotice(
                    code: code,
                    endedAt: endedAt,
                    canClose: owner || view.mySeat != null,
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
                if (owner)
                  FilledButton(
                    key: const ValueKey('summary-again'),
                    onPressed: _busy ? null : () => _playAgain(meta),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('เล่นอีกรอบ'),
                  )
                else
                  FilledButton(
                    key: const ValueKey('summary-home'),
                    onPressed: () => context.go('/'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('ออกจากห้อง'),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (owner) ...[
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('summary-close'),
                          onPressed: _busy ? null : _close,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          child: const Text('ปิดห้อง'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton(
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
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks the owner for the password of the next room: the old one only keeps a
/// proof of it, so it cannot be carried over.
class _AgainPasswordDialog extends StatefulWidget {
  const _AgainPasswordDialog();

  @override
  State<_AgainPasswordDialog> createState() => _AgainPasswordDialogState();
}

class _AgainPasswordDialogState extends State<_AgainPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('again-dialog'),
      title: const Text('รหัสผ่านของห้องใหม่'),
      content: TextField(
        key: const ValueKey('again-password'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'ห้องนี้มีรหัสผ่าน ใส่รหัสผ่านของห้องใหม่',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          key: const ValueKey('again-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          key: const ValueKey('again-confirm'),
          onPressed: _controller.text.isEmpty
              ? null
              : () => Navigator.pop(context, _controller.text),
          child: const Text('เล่นอีกรอบ'),
        ),
      ],
    );
  }
}

/// Tells everybody the room goes away, and when. The phone of a player (or of
/// the owner) takes the room down when the time is up; a watcher only sees it.
class _CloseNotice extends ConsumerStatefulWidget {
  const _CloseNotice({
    required this.code,
    required this.endedAt,
    required this.canClose,
  });

  final String code;
  final DateTime endedAt;
  final bool canClose;

  @override
  ConsumerState<_CloseNotice> createState() => _CloseNoticeState();
}

class _CloseNoticeState extends ConsumerState<_CloseNotice> {
  Timer? _tick;
  DateTime? _lastTry;
  var _trying = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration _left() {
    final now = ref.read(roomClockProvider)();
    return widget.endedAt.add(closeRoomAfter).difference(now);
  }

  void _update() {
    if (!mounted) return;
    setState(() {});
    if (!widget.canClose || _trying || _left() > Duration.zero) return;
    final now = ref.read(roomClockProvider)();
    // A phone whose clock runs ahead is told no by the room; try again soon.
    if (_lastTry != null &&
        now.difference(_lastTry!) < const Duration(seconds: 5)) {
      return;
    }
    _lastTry = now;
    _close();
  }

  Future<void> _close() async {
    _trying = true;
    try {
      await ref.read(roomRepositoryProvider).closeRoom(widget.code);
    } catch (_) {
      // Somebody else may be doing it, or the line is down: the next try says.
    }
    _trying = false;
  }

  @override
  Widget build(BuildContext context) {
    final left = _left();
    final text = left > Duration.zero
        ? 'ห้องจะถูกปิดใน ${left.inMinutes}:'
              '${(left.inSeconds % 60).toString().padLeft(2, '0')}'
        : 'กำลังปิดห้อง…';
    return Container(
      key: const ValueKey('summary-close-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: tileDecoration(context),
      child: Row(
        children: [
          const Icon(LucideIcons.timer, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Shown instead of the countdown once the owner has opened the next game.
class _NextRoomBanner extends StatelessWidget {
  const _NextRoomBanner({
    required this.owner,
    required this.busy,
    required this.onJoin,
  });

  final bool owner;
  final bool busy;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('summary-next-banner'),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: tileDecoration(context),
      child: Row(
        children: [
          const Icon(LucideIcons.dices, size: 18),
          const SizedBox(width: 8),
          // Its own node: next to the button it would otherwise be only the
          // label of the whole line, which a browser reads out of the markup.
          Expanded(
            child: Semantics(container: true, child: Text('มีห้องใหม่แล้ว')),
          ),
          FilledButton(
            key: const ValueKey('summary-next-join'),
            onPressed: busy ? null : onJoin,
            child: Text(owner ? 'ไปห้องใหม่' : 'เข้าร่วม'),
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
