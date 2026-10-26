import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:hold_my_dice/features/bank/presentation/money_sheet.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/entry_text.dart';
import 'package:hold_my_dice/features/room/application/incoming_events.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/application/relative_time.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/application/undo_offer.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/presentation/room_error_text.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// What "now" is for the times in the history; tests replace it.
final roomClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

const _reasonChips = ['ค่าเช่า', 'การ์ดโอกาส', 'ภาษี'];

/// The amount a history title ends with; the row shows it on its own.
final _trailingAmount = RegExp(r' [+-]?[\d,]+$');
const _plusColor = Color(0xFF10A15F);
const _minusColor = Color(0xFFD6336C);

/// The screen of a started game: my balance, the others, the history and the
/// buttons that write to the room.
class RoomGameScreen extends ConsumerWidget {
  const RoomGameScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(roomGameProvider(code));
    return Scaffold(
      key: const ValueKey('room-playing'),
      appBar: HelperAppBar(
        title: Text('โต๊ะ $code'),
        actions: [
          if (game.value?.online ?? false)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: LiveMark(
                  // Aurora's header is a green band; paper has none.
                  color: PaperStyle.maybeOf(context) == null
                      ? Colors.white
                      : const Color(0xFF10B981),
                ),
              ),
            ),
        ],
      ),
      body: game.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                roomErrorText(e),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('room-retry'),
                onPressed: () {
                  ref.invalidate(roomStateProvider(code));
                  ref.invalidate(roomEntriesProvider(code));
                  ref.invalidate(myMemberProvider(code));
                },
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
        data: (view) => _GameBody(code: code, view: view),
      ),
    );
  }
}

class _GameBody extends ConsumerWidget {
  const _GameBody({required this.code, required this.view});

  final String code;
  final RoomGameView view;

  Color _color(String seat) => Color(view.colorOf(seat) ?? 0xFF8A8A8A);

  /// Shows [message] above the buttons, so they stay in reach while it is up.
  /// (The undo bar never has to share the place with an announcement: whatever
  /// is announced came after the press the bar is for, and ends the offer.)
  void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 96),
          ),
        );

  /// Sends [draft] and tells the person if the room said no.
  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    EntryDraft draft,
  ) async {
    // Things may have changed while a sheet was open.
    final now = ref.read(roomGameProvider(code)).value;
    if (now == null || now.block != PressBlock.none) return;
    final error = await ref
        .read(pressControllerProvider(code).notifier)
        .press(draft);
    if (error != null && context.mounted) {
      _say(context, roomErrorText(RoomException(error)));
    }
  }

  Player get _me {
    final seat = view.mySeat!;
    return Player(
      id: seat,
      name: view.nameOf(seat),
      color: view.colorOf(seat) ?? 0xFF8A8A8A,
    );
  }

  Future<void> _receive(BuildContext context, WidgetRef ref) async {
    final result = await showMoneySheet(
      context,
      player: _me,
      balance: view.myBalance ?? 0,
      isPay: false,
      recent: const [],
      allowMortgage: false,
      reason: const ReasonOptions(
        chips: _reasonChips,
        formatter: ReasonLimitFormatter(),
      ),
    );
    if (result == null || !context.mounted) return;
    await _send(context, ref, EntryDraft.receive(result.amount, result.reason));
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final result = await showMoneySheet(
      context,
      player: _me,
      balance: view.myBalance ?? 0,
      isPay: true,
      recent: const [],
    );
    if (result == null || !context.mounted) return;
    await _send(context, ref, EntryDraft.payBank(result.amount));
  }

  Future<void> _transfer(
    BuildContext context,
    WidgetRef ref,
    String toSeat,
  ) async {
    final result = await showMoneySheet(
      context,
      player: _me,
      balance: view.myBalance ?? 0,
      isPay: true,
      recent: const [],
      recipient: Player(
        id: toSeat,
        name: view.nameOf(toSeat),
        color: view.colorOf(toSeat) ?? 0xFF8A8A8A,
      ),
    );
    if (result == null || !context.mounted) return;
    await _send(context, ref, EntryDraft.transfer(toSeat, result.amount));
  }

  void _openHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HistorySheet(code: code),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.color?.withValues(alpha: 0.65);
    final others = [
      for (final s in view.seats)
        if (s != view.mySeat) s,
    ];
    final canPress = view.block == PressBlock.none;
    final offer = ref.watch(undoOfferProvider(code));
    ref.listen(incomingEventsProvider(code), (_, batch) {
      if (batch != null) _say(context, batch.lines.join('\n'));
    });

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              children: [
                _StatusBand(view: view),
                if (view.mySeat case final seat?) ...[
                  Container(
                    key: const ValueKey('my-balance-card'),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: tileDecoration(context),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            PlayerAvatar(
                              name: view.nameOf(seat),
                              color: _color(seat),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'ยอดของฉัน · ${view.nameOf(seat)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(color: muted),
                              ),
                            ),
                          ],
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatMoney(view.myBalance ?? 0),
                            key: const ValueKey('my-balance'),
                            style: serifStyle(
                              text.displayLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!view.isSpectator && view.seatActive) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(LucideIcons.users, size: 14, color: muted),
                        const SizedBox(width: 6),
                        Text(
                          'แตะชื่อเพื่อนเพื่อโอนเงิน',
                          key: const ValueKey('friends-hint'),
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
                for (final seat in view.isSpectator ? view.seats : others) ...[
                  _FriendRow(
                    seat: seat,
                    name: view.nameOf(seat),
                    color: _color(seat),
                    balance: view.balances[seat] ?? 0,
                    out: view.state.bankrupt.contains(seat),
                    onTap: canPress && !view.state.bankrupt.contains(seat)
                        ? () => _transfer(context, ref, seat)
                        : null,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              children: [
                _HistoryStrip(
                  code: code,
                  view: view,
                  onOpen: () => _openHistory(context),
                ),
                if (offer != null)
                  _UndoBar(
                    key: ValueKey('undo-${offer.seq}'),
                    code: code,
                    offer: offer,
                    nameOf: view.nameOf,
                    onSay: (m) => _say(context, m),
                  ),
                if (!view.isSpectator) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _DockButton(
                        id: 'press-pay',
                        icon: LucideIcons.minus,
                        label: 'จ่ายธนาคาร',
                        onPressed: canPress ? () => _pay(context, ref) : null,
                      ),
                      const SizedBox(width: 8),
                      _DockButton(
                        id: 'press-go',
                        icon: LucideIcons.flag,
                        label: 'GO',
                        onPressed: canPress
                            ? () => _send(context, ref, EntryDraft.passGo())
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _DockButton(
                        id: 'press-receive',
                        icon: LucideIcons.plus,
                        label: 'รับเงิน',
                        filled: true,
                        onPressed: canPress
                            ? () => _receive(context, ref)
                            : null,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the three money buttons: the icon over a one-line label that
/// shrinks on a narrow screen.
class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = (filled ? FilledButton.styleFrom : OutlinedButton.styleFrom)(
      minimumSize: const Size.fromHeight(64),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ],
    );
    return Expanded(
      child: filled
          ? FilledButton(
              key: ValueKey(id),
              onPressed: onPressed,
              style: style,
              child: content,
            )
          : OutlinedButton(
              key: ValueKey(id),
              onPressed: onPressed,
              style: style,
              child: content,
            ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.seat,
    required this.name,
    required this.color,
    required this.balance,
    required this.out,
    required this.onTap,
  });

  final String seat;
  final String name;
  final Color color;
  final int balance;
  final bool out;

  /// Opens the transfer to this person; null when it cannot be done now.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // The row reads as its name and balance; a button with a hint when it
    // can be tapped.
    return Semantics(
      button: onTap != null,
      hint: onTap == null ? null : 'แตะเพื่อโอนเงิน',
      child: InkWell(
        key: ValueKey('friend-$seat'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(PaperStyle.radius),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: tileDecoration(context),
          child: Row(
            children: [
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
              if (out) ...[
                const RoomChip('ออกจากเกม'),
                const SizedBox(width: 8),
              ],
              Text(
                formatMoney(balance),
                style: serifStyle(
                  text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the person just did and the few seconds to take it back.
class _UndoBar extends ConsumerStatefulWidget {
  const _UndoBar({
    super.key,
    required this.code,
    required this.offer,
    required this.nameOf,
    required this.onSay,
  });

  final String code;
  final UndoOffer offer;
  final String Function(String seat) nameOf;
  final void Function(String message) onSay;

  @override
  ConsumerState<_UndoBar> createState() => _UndoBarState();
}

class _UndoBarState extends ConsumerState<_UndoBar> {
  late int _left = widget.offer.window.inSeconds;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _left > 1) setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _label(RoomEntry e) {
    final amount = formatMoney(e.amount ?? 0);
    return switch (e.kind) {
      EntryKind.transfer => 'โอน $amount ให้${widget.nameOf(e.to ?? '')}แล้ว',
      EntryKind.receive => 'รับเงิน $amount แล้ว',
      EntryKind.payBank => 'จ่ายธนาคาร $amount แล้ว',
      EntryKind.passGo => 'ผ่านจุดเริ่ม +$amount แล้ว',
      _ => 'ทำรายการแล้ว',
    };
  }

  Future<void> _undo() async {
    final error = await ref
        .read(pressControllerProvider(widget.code).notifier)
        .undo(widget.offer.seq);
    if (error != null && mounted) {
      widget.onSay(roomErrorText(RoomException(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        key: const ValueKey('undo-bar'),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _label(widget.offer.entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: on),
              ),
            ),
            TextButton(
              key: const ValueKey('undo-button'),
              onPressed: _undo,
              style: TextButton.styleFrom(
                foregroundColor: on,
                side: BorderSide(color: on.withValues(alpha: 0.6)),
                shape: const StadiumBorder(),
              ),
              child: Text('เลิกทำ $_left'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line saying why the buttons are off, or that the history is catching up.
class _StatusBand extends StatelessWidget {
  const _StatusBand({required this.view});

  final RoomGameView view;

  @override
  Widget build(BuildContext context) {
    final (key, icon, title, detail, color) = switch (view.block) {
      PressBlock.spectator => (
        'band-spectator',
        LucideIcons.eye,
        'คุณเป็นผู้ชม',
        'ดูได้อย่างเดียว',
        _plusColor,
      ),
      PressBlock.out => (
        'band-out',
        LucideIcons.logOut,
        'คุณออกจากเกมแล้ว',
        'ดูต่อได้ แต่กดเงินไม่ได้',
        _plusColor,
      ),
      PressBlock.unsure => (
        'band-unsure',
        LucideIcons.clock,
        'ไม่แน่ใจว่าบันทึกแล้วหรือยัง',
        'ดูประวัติก่อน ปุ่มจะเปิดเมื่อรู้ผลหรือครบ 20 วินาที',
        const Color(0xFF3D5AFE),
      ),
      PressBlock.offline => (
        'band-offline',
        LucideIcons.wifiOff,
        'ออฟไลน์',
        'ปุ่มเงินปิดจนกว่าสัญญาณกลับมา',
        const Color(0xFFD97706),
      ),
      PressBlock.mismatch => (
        'band-mismatch',
        LucideIcons.triangleAlert,
        'ยอดไม่ตรงกับประวัติ',
        'ปุ่มเงินปิดอยู่ ระบบตรวจซ้ำให้เอง และหายเองเมื่อกลับตรงกัน',
        const Color(0xFFE11D48),
      ),
      _ when view.check == BalanceCheck.syncing => (
        'band-syncing',
        LucideIcons.refreshCw,
        'กำลังซิงก์',
        'ยอดกับประวัติยังมาไม่ครบ',
        _plusColor,
      ),
      _ => (null, null, '', '', _plusColor),
    };
    if (key == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: ValueKey(key),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: ' $detail'),
                  ],
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- the history ---------------------------------------------------------

class _HistoryStrip extends StatelessWidget {
  const _HistoryStrip({
    required this.code,
    required this.view,
    required this.onOpen,
  });

  final String code;
  final RoomGameView view;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final latest = view.entries.isEmpty ? null : view.entries.last;
    final label = latest == null
        ? null
        : describeRoomEntry(latest, view.nameOf);
    final line = latest == null
        ? 'ยังไม่มีรายการ'
        : [label!.title, ?label.subtitle].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('history-strip'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(PaperStyle.radius),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: tileDecoration(context),
          child: Row(
            children: [
              const Icon(LucideIcons.list, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  line,
                  key: const ValueKey('history-latest'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              const RoomChip('ทั้งหมด ▲'),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySheet extends ConsumerStatefulWidget {
  const _HistorySheet({required this.code});

  final String code;

  @override
  ConsumerState<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<_HistorySheet> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The "x minutes ago" of the rows moves on while the sheet is open.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(roomGameProvider(widget.code)).value;
    final now = ref.read(roomClockProvider)();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    final entries = view == null
        ? <RoomEntry>[]
        : view.entries.reversed.toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'ประวัติทั้งหมด',
                    style: headingStyle(context, text.titleMedium),
                  ),
                  const Spacer(),
                  const LiveMark(),
                ],
              ),
              // Longer than what a device holds: only the newest are listed.
              if (entries.isNotEmpty && entries.last.seq > 0)
                Text(
                  'แสดง ${entries.length} รายการล่าสุด',
                  key: const ValueKey('history-window'),
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'ยังไม่มีรายการ',
                          key: const ValueKey('history-empty'),
                          style: text.bodyMedium?.copyWith(color: muted),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          final label = describeRoomEntry(e, view!.nameOf);
                          final when = e.at == null
                              ? null
                              : relativeTime(e.at!, now);
                          final sub = [?label.subtitle, ?when].join(' · ');
                          final sign = switch (e.kind) {
                            EntryKind.receive || EntryKind.passGo => '+',
                            EntryKind.payBank => '−',
                            EntryKind.transfer =>
                              e.to == view.mySeat
                                  ? '+'
                                  : e.seat == view.mySeat
                                  ? '−'
                                  : '',
                            _ => '',
                          };
                          return Padding(
                            key: ValueKey('history-row-${e.seq}'),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Color(
                                      view.colorOf(e.seat) ?? 0xFF8A8A8A,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label.title.replaceFirst(
                                          _trailingAmount,
                                          '',
                                        ),
                                        style: text.titleSmall,
                                      ),
                                      if (sub.isNotEmpty)
                                        Text(
                                          sub,
                                          style: text.bodySmall?.copyWith(
                                            color: muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (sign.isNotEmpty ||
                                    e.kind == EntryKind.transfer)
                                  Text(
                                    '$sign${formatMoney(e.amount ?? 0)}',
                                    style: serifStyle(
                                      text.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: e.voided || sign.isEmpty
                                            ? muted
                                            : (sign == '+'
                                                  ? _plusColor
                                                  : _minusColor),
                                        decoration: e.voided
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
