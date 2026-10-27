import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_host.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:hold_my_dice/features/bank/presentation/money_sheet.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/entry_text.dart';
import 'package:hold_my_dice/features/room/application/incoming_events.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/application/relative_time.dart';
import 'package:hold_my_dice/features/room/application/requests_control.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/application/undo_offer.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';
import 'package:hold_my_dice/features/room/presentation/room_error_text.dart';
import 'package:hold_my_dice/features/room/presentation/room_widgets.dart';
import 'package:hold_my_dice/features/room/presentation/shortfall_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _reasonChips = ['ค่าเช่า', 'การ์ดโอกาส', 'ภาษี'];

/// The amount a history title ends with; the row shows it on its own.
final _trailingAmount = RegExp(r' [+-]?[\d,]+$');
const _plusColor = Color(0xFF10A15F);
const _minusColor = Color(0xFFD6336C);

/// The screen of a started game: my balance, the others, the history and the
/// buttons that write to the room.
class RoomGameScreen extends ConsumerStatefulWidget {
  const RoomGameScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<RoomGameScreen> createState() => _RoomGameScreenState();
}

/// What the first-run tour of the game lights up.
class _TourKeys {
  final end = GlobalKey();
  final balance = GlobalKey();
  final friend = GlobalKey();
  final history = GlobalKey();
  final dock = GlobalKey();
}

class _RoomGameScreenState extends ConsumerState<RoomGameScreen>
    with TourHost<RoomGameScreen> {
  final _keys = _TourKeys();
  var _offered = false;

  String get code => widget.code;

  @override
  void initState() {
    super.initState();
    // Offered once the game has been read: before that nothing is on screen
    // to light up.
    ref.listenManual(roomGameProvider(code), (_, now) {
      if (_offered || !now.hasValue) return;
      _offered = true;
      offerTour(
        storage: ref.read(tourStorageProvider),
        id: TourIds.roomPlay,
        steps: _tourSteps,
      );
    }, fireImmediately: true);
  }

  /// All the steps; the tour leaves out those whose thing is not on this
  /// person's screen (a watcher has no balance or money buttons).
  List<TourStep> _tourSteps() {
    return [
      TourStep(
        title: 'ยอดของฉัน',
        body: 'ตัวเลขใหญ่คือเงินของคุณ ทุกเครื่องในห้องเห็นตรงกันทันที',
        target: _keys.balance,
      ),
      TourStep(
        title: 'รับ จ่าย และ GO',
        body:
            'ใช้กับธนาคาร: รับเงิน จ่ายธนาคาร และ GO ผ่านจุดเริ่ม '
            'พอมีนายธนาคาร ปุ่มพวกนี้จะเป็นของนายธนาคารคนเดียว',
        target: _keys.dock,
        gesture: TourGesture.tap,
      ),
      TourStep(
        title: 'โอนและเรียกเก็บ',
        body: 'แตะชื่อเพื่อนเพื่อโอนเงินให้ หรือขอเงินจากเขา',
        target: _keys.friend,
        gesture: TourGesture.tap,
      ),
      TourStep(
        title: 'ประวัติ',
        body: 'รายการล่าสุดของทุกคน แตะเพื่อดูทั้งหมด',
        target: _keys.history,
        gesture: TourGesture.tap,
      ),
      TourStep(
        title: 'จบเกม',
        body: 'เล่นจบแล้วกดตรงนี้ ทุกคนจะเห็นหน้าสรุปอันดับ',
        target: _keys.end,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(roomGameProvider(code));
    final now = game.value;
    return Scaffold(
      key: const ValueKey('room-playing'),
      appBar: HelperAppBar(
        title: Text('โต๊ะ $code'),
        actions: [
          if (now != null && (now.mySeat != null || now.iAmOwner))
            KeyedSubtree(
              key: _keys.end,
              child: TextButton.icon(
                key: const ValueKey('end-game'),
                icon: const Icon(LucideIcons.flagTriangleRight, size: 18),
                label: const Text('จบเกม'),
                onPressed: () => _confirmEndGame(context, ref, code, now),
              ),
            ),
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
        data: (view) => _GameBody(code: code, view: view, keys: _keys),
      ),
    );
  }
}

/// Asks once, then ends the game for everybody. The owner and the banker may
/// at any time; a player when both have been gone for 10 minutes (the room
/// says no otherwise, and that is told in words).
Future<void> _confirmEndGame(
  BuildContext context,
  WidgetRef ref,
  String code,
  RoomGameView view,
) async {
  final ownerOrBanker = view.iAmOwner || view.iAmBanker;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('end-game-dialog'),
      title: const Text('จบเกมนี้?'),
      content: Text(
        ownerOrBanker
            ? 'ทุกคนในห้องจะเห็นหน้าสรุปอันดับ และเล่นต่อไม่ได้ ย้อนกลับไม่ได้'
            : 'ปกติเจ้าของห้องหรือนายธนาคารเป็นคนจบเกม คุณจบได้เมื่อทั้งสองคน '
                  'หายไปเกิน 10 นาที ทุกคนจะเห็นหน้าสรุปอันดับ และเล่นต่อไม่ได้ '
                  'ย้อนกลับไม่ได้',
      ),
      actions: [
        TextButton(
          key: const ValueKey('end-game-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('กลับไปก่อน'),
        ),
        FilledButton(
          key: const ValueKey('end-game-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('จบเกม'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(roomRepositoryProvider).endGame(code);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(roomErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

/// Tells the owner and the banker that one player is left, with the way to
/// end the game from here (it can be put away).
class _LastOneBand extends StatefulWidget {
  const _LastOneBand({required this.onEnd});

  final VoidCallback onEnd;

  @override
  State<_LastOneBand> createState() => _LastOneBandState();
}

class _LastOneBandState extends State<_LastOneBand> {
  var _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: const ValueKey('band-last-one'),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'เหลือผู้เล่นคนเดียวแล้ว จบเกมเพื่อดูสรุปอันดับ หรือเล่นต่อก็ได้',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              key: const ValueKey('last-one-end'),
              onPressed: widget.onEnd,
              child: const Text('จบเกม'),
            ),
            IconButton(
              key: const ValueKey('last-one-dismiss'),
              tooltip: 'ปิดแถบ',
              icon: const Icon(LucideIcons.x, size: 18),
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameBody extends ConsumerWidget {
  const _GameBody({required this.code, required this.view, this.keys});

  final String code;
  final RoomGameView view;

  /// What the first-run tour lights up; null where there is no tour.
  final _TourKeys? keys;

  Color _color(String seat) => Color(view.colorOf(seat) ?? 0xFF8A8A8A);

  /// Shows [message] above the buttons, so they stay in reach while it is up.
  /// (The undo bar never has to share the place with an announcement: whatever
  /// is announced came after the press the bar is for, and ends the offer.)
  void _say(BuildContext context, String message) {
    // The one who asked may be a bar or a card that is gone by now; the
    // screen under them is what matters.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        ),
      );
  }

  /// Sends [draft] and tells the person if the room said no.
  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    EntryDraft draft,
  ) async {
    // Things may have changed while a sheet was open.
    final now = ref.read(roomGameProvider(code)).value;
    if (now == null) return;
    if (now.block != PressBlock.none) {
      if (pressBlockText(now.block) case final why?) _say(context, why);
      return;
    }
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
    await _payOrShortfall(context, ref, result.amount, null);
  }

  /// Pays [amount] to the bank ([toSeat] null) or to that seat. When the cash
  /// does not cover it, the "not enough money" sheet comes first: mortgage and
  /// pay in one press, or go bankrupt.
  Future<void> _payOrShortfall(
    BuildContext context,
    WidgetRef ref,
    int amount,
    String? toSeat,
  ) async {
    EntryDraft pay([int? mortgage]) => toSeat == null
        ? EntryDraft.payBank(amount, mortgage: mortgage)
        : EntryDraft.transfer(toSeat, amount, mortgage: mortgage);
    final cash = ref.read(roomGameProvider(code)).value?.myBalance ?? 0;
    if (amount <= cash) {
      await _send(context, ref, pay());
      return;
    }
    final choice = await showShortfallSheet(
      context,
      code: code,
      amount: amount,
      toSeat: toSeat,
    );
    if (choice == null || !context.mounted) return;
    await _send(
      context,
      ref,
      choice.bankrupt
          ? EntryDraft.bankrupt(amount, creditorSeat: toSeat)
          : pay(choice.mortgage),
    );
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
    await _payOrShortfall(context, ref, result.amount, toSeat);
  }

  /// A friend was tapped: give or ask.
  Future<void> _friend(BuildContext context, WidgetRef ref, String seat) async {
    final choice = await showModalBottomSheet<_FriendAction>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FriendSheet(
        name: view.nameOf(seat),
        color: _color(seat),
        balance: view.balanceShown(seat) ? view.balances[seat] ?? 0 : null,
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _FriendAction.give:
        await _transfer(context, ref, seat);
      case _FriendAction.ask:
        await _ask(context, ref, seat);
    }
  }

  Future<void> _ask(BuildContext context, WidgetRef ref, String seat) async {
    final result = await showMoneySheet(
      context,
      player: _me,
      balance: view.myBalance ?? 0,
      isPay: false,
      recent: const [],
      allowMortgage: false,
      collectFrom: Player(
        id: seat,
        name: view.nameOf(seat),
        color: view.colorOf(seat) ?? 0xFF8A8A8A,
      ),
    );
    if (result == null || !context.mounted) return;
    final now = ref.read(roomGameProvider(code)).value;
    if (now == null) return;
    if (now.block != PressBlock.none) {
      if (pressBlockText(now.block) case final why?) _say(context, why);
      return;
    }
    try {
      await ref
          .read(roomRepositoryProvider)
          .requestMoney(code, fromSeat: seat, amount: result.amount);
    } catch (e) {
      if (context.mounted) _say(context, roomErrorText(e));
    }
  }

  Player _playerOf(String seat) => Player(
    id: seat,
    name: view.nameOf(seat),
    color: view.colorOf(seat) ?? 0xFF8A8A8A,
  );

  /// The banker gives [seat] money from the bank (no reason is asked).
  Future<void> _bankerReceive(
    BuildContext context,
    WidgetRef ref,
    String seat,
  ) async {
    final result = await showMoneySheet(
      context,
      player: _playerOf(seat),
      balance: view.balances[seat] ?? 0,
      isPay: false,
      recent: const [],
      allowMortgage: false,
    );
    if (result == null || !context.mounted) return;
    await _send(
      context,
      ref,
      EntryDraft.receive(result.amount, null).onBehalfOf(seat),
    );
  }

  /// The banker takes money from [seat] for the bank; when they cannot cover
  /// it, the sheet that mortgages for them or declares them bankrupt.
  Future<void> _bankerPay(
    BuildContext context,
    WidgetRef ref,
    String seat,
  ) async {
    final result = await showMoneySheet(
      context,
      player: _playerOf(seat),
      balance: view.balances[seat] ?? 0,
      isPay: true,
      recent: const [],
    );
    if (result == null || !context.mounted) return;
    final amount = result.amount;
    final cash = ref.read(roomGameProvider(code)).value?.balances[seat] ?? 0;
    if (amount <= cash) {
      await _send(context, ref, EntryDraft.payBank(amount).onBehalfOf(seat));
      return;
    }
    final choice = await showShortfallSheet(
      context,
      code: code,
      amount: amount,
      forSeat: seat,
    );
    if (choice == null || !context.mounted) return;
    await _send(
      context,
      ref,
      (choice.bankrupt
              ? EntryDraft.bankrupt(amount)
              : EntryDraft.payBank(amount, mortgage: choice.mortgage))
          .onBehalfOf(seat),
    );
  }

  Future<void> _bankerGo(BuildContext context, WidgetRef ref, String seat) =>
      _send(context, ref, EntryDraft.passGo().onBehalfOf(seat));

  /// The banker chooses who gets the banker's seat.
  Future<void> _bankerPass(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'ส่งต่อตำแหน่งนายธนาคารให้',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final seat in view.seats)
              if (seat != view.mySeat)
                ListTile(
                  key: ValueKey('banker-pass-$seat'),
                  leading: PlayerAvatar(
                    name: view.nameOf(seat),
                    color: _color(seat),
                    size: 28,
                  ),
                  title: Text(view.nameOf(seat)),
                  trailing: view.state.bankrupt.contains(seat)
                      ? const RoomChip('ออกจากเกม')
                      : const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () => Navigator.pop(context, seat),
                ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    try {
      await ref.read(roomRepositoryProvider).passBanker(code, chosen);
    } catch (e) {
      if (context.mounted) _say(context, roomErrorText(e));
    }
  }

  Future<void> _bankerTakeOver(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(roomRepositoryProvider).takeOverBanker(code);
    } catch (e) {
      if (context.mounted) _say(context, roomErrorText(e));
    }
  }

  void _openHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RoomHistorySheet(code: code),
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
    // A banker who is out presses for the others but has no seat to give from.
    final canTransfer = canPress && view.seatActive;
    final offer = ref.watch(undoOfferProvider(code));
    final requests = ref.watch(requestsControllerProvider(code));
    ref.listen(requestsControllerProvider(code), (before, next) {
      final notice = next.notice;
      if (notice != null && notice.id != before?.notice?.id) {
        _say(context, notice.text);
      }
    });
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
                _BankerBar(
                  view: view,
                  onPass: () => _bankerPass(context, ref),
                  onTakeOver: () => _bankerTakeOver(context, ref),
                ),
                if ((view.iAmOwner || view.iAmBanker) && view.playersIn <= 1)
                  _LastOneBand(
                    onEnd: () => _confirmEndGame(context, ref, code, view),
                  ),
                if (requests.outgoing.isNotEmpty)
                  _OutgoingBand(
                    code: code,
                    pending: requests.outgoing,
                    nameOf: view.nameOf,
                    onSay: (m) => _say(context, m),
                  ),
                if (view.mySeat case final seat?) ...[
                  KeyedSubtree(
                    key: keys?.balance,
                    child: Container(
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
                                  style: text.bodyMedium?.copyWith(
                                    color: muted,
                                  ),
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
                          'แตะชื่อเพื่อนเพื่อโอนหรือเรียกเก็บ',
                          key: const ValueKey('friends-hint'),
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
                for (final (i, seat)
                    in (view.isSpectator ? view.seats : others).indexed) ...[
                  KeyedSubtree(
                    key: i == 0 ? keys?.friend : null,
                    child: _FriendRow(
                      seat: seat,
                      name: view.nameOf(seat),
                      color: _color(seat),
                      balance: view.balances[seat] ?? 0,
                      hidden: !view.balanceShown(seat),
                      out: view.state.bankrupt.contains(seat),
                      onTap: canTransfer && !view.state.bankrupt.contains(seat)
                          ? () => _friend(context, ref, seat)
                          : null,
                      bankerActions:
                          view.iAmBanker && !view.state.bankrupt.contains(seat),
                      onBankerReceive: canPress
                          ? () => _bankerReceive(context, ref, seat)
                          : null,
                      onBankerPay: canPress
                          ? () => _bankerPay(context, ref, seat)
                          : null,
                      onBankerGo: canPress
                          ? () => _bankerGo(context, ref, seat)
                          : null,
                    ),
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
                KeyedSubtree(
                  key: keys?.history,
                  child: _HistoryStrip(
                    code: code,
                    view: view,
                    onOpen: () => _openHistory(context),
                  ),
                ),
                if (requests.incoming.isNotEmpty && view.seatActive)
                  _RequestCard(
                    key: ValueKey(
                      '${requests.incoming.first.request.id}@'
                      '${requests.incoming.first.deadline.microsecondsSinceEpoch}',
                    ),
                    code: code,
                    view: view,
                    pending: requests.incoming.first,
                    more: requests.incoming.length - 1,
                    onSay: (m) => _say(context, m),
                  ),
                if (offer != null)
                  _UndoBar(
                    key: ValueKey('undo-${offer.seq}'),
                    code: code,
                    offer: offer,
                    nameOf: view.nameOf,
                    mySeat: view.mySeat,
                    onSay: (m) => _say(context, m),
                  ),
                // With a banker the bank's buttons are theirs; a banker who is
                // out has no seat to press for.
                if (!view.isSpectator &&
                    (view.bankerSeat == null ||
                        (view.iAmBanker && view.seatActive))) ...[
                  const SizedBox(height: 10),
                  Row(
                    key: keys?.dock,
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
    this.hidden = false,
    required this.out,
    required this.onTap,
    this.bankerActions = false,
    this.onBankerReceive,
    this.onBankerPay,
    this.onBankerGo,
  });

  final String seat;
  final String name;
  final Color color;
  final int balance;

  /// The room hides this balance from the person looking.
  final bool hidden;
  final bool out;

  /// Whether the banker's three buttons for this person are shown; they are
  /// off (and stay in their place) while a press is resting or on its way.
  final bool bankerActions;
  final VoidCallback? onBankerReceive;
  final VoidCallback? onBankerPay;
  final VoidCallback? onBankerGo;

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
          child: Column(
            children: [
              Row(
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
                  if (hidden)
                    Semantics(
                      label: 'ซ่อนยอด',
                      child: ExcludeSemantics(
                        child: Text(
                          '•••',
                          key: ValueKey('balance-hidden-$seat'),
                          style: serifStyle(
                            text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      formatMoney(balance),
                      style: serifStyle(
                        text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              if (bankerActions)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      for (final (id, label, icon, action) in [
                        ('receive', 'รับ', LucideIcons.plus, onBankerReceive),
                        ('pay', 'จ่าย', LucideIcons.minus, onBankerPay),
                        ('go', 'GO', LucideIcons.flag, onBankerGo),
                      ]) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: ValueKey('banker-$id-$seat'),
                            onPressed: action,
                            icon: Icon(icon, size: 16),
                            label: Text(label),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ),
                        if (id != 'go') const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FriendAction { give, ask }

/// What to do with a friend: give them money or ask them for some.
class _FriendSheet extends StatelessWidget {
  const _FriendSheet({
    required this.name,
    required this.color,
    required this.balance,
  });

  final String name;
  final Color color;

  /// What they hold; null when the room hides it from this person.
  final int? balance;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.color?.withValues(alpha: 0.65);
    Widget tile(
      Key key,
      IconData icon,
      String title,
      String sub,
      _FriendAction action,
    ) => Semantics(
      button: true,
      child: InkWell(
        key: key,
        onTap: () => Navigator.pop(context, action),
        borderRadius: BorderRadius.circular(PaperStyle.radius),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: tileDecoration(context),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    Text(sub, style: text.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                PlayerAvatar(name: name, color: color, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: headingStyle(context, text.titleMedium),
                      ),
                      if (balance != null)
                        Text(
                          'มี ${formatMoney(balance!)}',
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            tile(
              const ValueKey('friend-action-give'),
              LucideIcons.arrowRightLeft,
              'โอนให้ $name',
              'จ่ายเงินให้ตรง ๆ',
              _FriendAction.give,
            ),
            const SizedBox(height: 10),
            tile(
              const ValueKey('friend-action-ask'),
              LucideIcons.clock,
              'เรียกเก็บจาก $name',
              'กดจ่ายเองภายใน 2 นาที',
              _FriendAction.ask,
            ),
          ],
        ),
      ),
    );
  }
}

String _mmss(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// "รอแพรจ่าย 300 · 1:48 · ยกเลิก": a request this person made, waiting.
class _OutgoingBand extends ConsumerStatefulWidget {
  const _OutgoingBand({
    required this.code,
    required this.pending,
    required this.nameOf,
    required this.onSay,
  });

  final String code;
  final List<PendingRequest> pending;
  final String Function(String seat) nameOf;
  final void Function(String message) onSay;

  @override
  ConsumerState<_OutgoingBand> createState() => _OutgoingBandState();
}

class _OutgoingBandState extends ConsumerState<_OutgoingBand> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cancel(RoomRequest r) async {
    // Taken before the await: the answer can come after this bar is gone.
    final requests = ref.read(requestsControllerProvider(widget.code).notifier);
    final repo = ref.read(roomRepositoryProvider);
    final say = widget.onSay;
    try {
      await repo.cancelRequest(widget.code, r.id);
    } on RoomException catch (e) {
      if (e.error == RoomError.requestGone ||
          e.error == RoomError.alreadyPaid) {
        requests.dismiss(r.id);
      }
      say(roomErrorText(e));
    } catch (e) {
      say(roomErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF3D5AFE);
    final first = widget.pending.first;
    final r = first.request;
    final left = first.deadline.difference(ref.read(roomClockProvider)());
    final more = widget.pending.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: const ValueKey('request-waiting'),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: blue.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.clock, size: 18, color: blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'รอ${widget.nameOf(r.fromSeat)}จ่าย ${formatMoney(r.amount)}'
                ' · ${_mmss(left)}${more > 0 ? ' (อีก $more)' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              key: const ValueKey('request-cancel'),
              onPressed: () => _cancel(r),
              child: const Text('ยกเลิก'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A request to pay that is asked of this person, above the buttons. The pay
/// button waits a moment before it works, so a card that appears just as a
/// finger comes down is not paid by accident.
class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({
    super.key,
    required this.code,
    required this.view,
    required this.pending,
    required this.more,
    required this.onSay,
  });

  final String code;
  final RoomGameView view;
  final PendingRequest pending;
  final int more;
  final void Function(String message) onSay;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  static const _guard = Duration(milliseconds: 600);
  var _armed = false;
  Timer? _tick;
  Timer? _arm;

  @override
  void initState() {
    super.initState();
    _arm = Timer(_guard, () {
      if (mounted) setState(() => _armed = true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _arm?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  RoomRequest get _r => widget.pending.request;

  // Answers can come after this card is gone (the asker took the request
  // back meanwhile), so what is needed after an await is taken before it.
  static void _dropIfGone(RequestsController requests, String id, RoomError e) {
    if (e == RoomError.requestGone || e == RoomError.alreadyPaid) {
      requests.dismiss(id);
    }
  }

  Future<void> _pay() async {
    final requests = ref.read(requestsControllerProvider(widget.code).notifier);
    final press = ref.read(pressControllerProvider(widget.code).notifier);
    final say = widget.onSay;
    final r = _r;
    final id = r.id;
    RoomError? error;
    if ((ref.read(roomGameProvider(widget.code)).value?.myBalance ?? 0) >=
        r.amount) {
      error = await press.payRequest(id);
    } else {
      final choice = await showShortfallSheet(
        context,
        code: widget.code,
        amount: r.amount,
        toSeat: r.toSeat,
      );
      if (choice == null) return;
      error = choice.bankrupt
          ? await press.press(
              EntryDraft.bankrupt(r.amount, creditorSeat: r.toSeat),
            )
          : await press.payRequest(id, mortgage: choice.mortgage);
    }
    if (error == null) return;
    _dropIfGone(requests, id, error);
    say(roomErrorText(RoomException(error)));
  }

  Future<void> _decline() async {
    final requests = ref.read(requestsControllerProvider(widget.code).notifier);
    final repo = ref.read(roomRepositoryProvider);
    final say = widget.onSay;
    final id = _r.id;
    try {
      await repo.cancelRequest(widget.code, id);
    } on RoomException catch (e) {
      _dropIfGone(requests, id, e.error);
      say(roomErrorText(e));
    } catch (e) {
      say(roomErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFD97706);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = text.bodySmall?.color?.withValues(alpha: 0.65);
    final view = widget.view;
    final r = _r;
    final left = widget.pending.deadline.difference(
      ref.read(roomClockProvider)(),
    );
    final mine = view.myBalance ?? 0;
    final enough = mine >= r.amount;
    final canPay =
        _armed && left > Duration.zero && view.block == PressBlock.none;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        key: const ValueKey('request-card'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: amber, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              container: true,
              label:
                  '${view.nameOf(r.toSeat)} เรียกเก็บ ${formatMoney(r.amount)}',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    PlayerAvatar(
                      name: view.nameOf(r.toSeat),
                      color: Color(view.colorOf(r.toSeat) ?? 0xFF8A8A8A),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${view.nameOf(r.toSeat)} เรียกเก็บ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                    ),
                    const Icon(LucideIcons.clock, size: 14, color: amber),
                    const SizedBox(width: 4),
                    Text(
                      left > Duration.zero
                          ? 'หมดอายุใน ${_mmss(left)}'
                          : 'หมดอายุ',
                      key: const ValueKey('request-timer'),
                      style: text.bodySmall?.copyWith(color: amber),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              formatMoney(r.amount),
              key: const ValueKey('request-amount'),
              style: serifStyle(
                text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (enough)
              Text(
                'คุณมี ${formatMoney(mine)} · จะเหลือ ${formatMoney(mine - r.amount)}',
                style: text.bodySmall?.copyWith(color: muted),
              )
            else ...[
              Text(
                'คุณมี ${formatMoney(mine)} · ไม่พอจ่าย',
                style: text.bodySmall?.copyWith(color: muted),
              ),
              Text(
                'แตะจ่ายเพื่อจำนองหรือล้มละลาย',
                key: const ValueKey('request-short'),
                style: text.bodySmall?.copyWith(color: const Color(0xFFBE123C)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('request-decline'),
                    onPressed: _decline,
                    child: const Text('ไม่จ่าย'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('request-pay'),
                    onPressed: canPay ? _pay : null,
                    child: Text('จ่าย ${formatMoney(r.amount)}'),
                  ),
                ),
              ],
            ),
            if (widget.more > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: Text(
                    'ยังมีอีก ${widget.more} คำขอ',
                    key: const ValueKey('request-more'),
                    style: text.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ),
          ],
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
    required this.mySeat,
    required this.onSay,
  });

  final String code;
  final UndoOffer offer;
  final String Function(String seat) nameOf;
  final String? mySeat;
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
    // The banker's press for somebody else says whose money it was.
    final other = e.seat == widget.mySeat ? null : widget.nameOf(e.seat);
    return switch (e.kind) {
      EntryKind.transfer => 'โอน $amount ให้${widget.nameOf(e.to ?? '')}แล้ว',
      EntryKind.receive =>
        other == null
            ? 'รับเงิน $amount แล้ว'
            : 'รับเงิน $amount ให้$otherแล้ว',
      EntryKind.payBank =>
        other == null
            ? 'จ่ายธนาคาร $amount แล้ว'
            : 'จ่ายธนาคาร $amount จาก$otherแล้ว',
      EntryKind.passGo =>
        other == null
            ? 'ผ่านจุดเริ่ม +$amount แล้ว'
            : 'GO ให้$other +$amount แล้ว',
      _ => 'ทำรายการแล้ว',
    };
  }

  Future<void> _undo() async {
    final error = await ref
        .read(pressControllerProvider(widget.code).notifier)
        .undo(widget.offer.seq);
    if (error != null) widget.onSay(roomErrorText(RoomException(error)));
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

/// Who the banker is: for the banker, that they are and the button to hand the
/// seat on; for the others, that the banker presses the bank's buttons, and the
/// button to take the seat over (the room says no while the banker has been
/// seen in the last 2 minutes; the others' own activity says nothing about
/// whether the banker is there).
class _BankerBar extends StatelessWidget {
  const _BankerBar({
    required this.view,
    required this.onPass,
    required this.onTakeOver,
  });

  final RoomGameView view;
  final VoidCallback onPass;
  final VoidCallback onTakeOver;

  @override
  Widget build(BuildContext context) {
    final banker = view.bankerSeat;
    if (banker == null || view.isSpectator) return const SizedBox.shrink();
    const color = Color(0xFF3D5AFE);
    final text = Theme.of(context).textTheme;
    final mine = view.iAmBanker;
    final title = mine
        ? 'คุณเป็นนายธนาคาร'
        : 'นายธนาคาร ${view.nameOf(banker)}';
    final detail = mine
        ? (view.seatActive
              ? ' กดรับ จ่าย และ GO ให้เพื่อนได้ด้วยปุ่มใต้ชื่อ'
              : ' คุณออกจากเกมแล้ว กดรับ จ่าย และ GO ให้เพื่อนได้')
        : view.seatActive
        ? ' เป็นคนกดรับเงิน จ่ายธนาคาร และ GO ให้คุณ'
        : ' เป็นคนกดรับเงิน จ่ายธนาคาร และ GO ให้ผู้เล่น';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: ValueKey(mine ? 'band-banker' : 'band-banker-presses'),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.landmark, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                container: true,
                label: '$title$detail',
                child: ExcludeSemantics(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: detail),
                      ],
                    ),
                    style: text.bodySmall,
                  ),
                ),
              ),
            ),
            if (mine)
              OutlinedButton(
                key: const ValueKey('banker-pass'),
                onPressed: onPass,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('ส่งต่อ'),
              )
            else
              TextButton(
                key: const ValueKey('banker-takeover'),
                onPressed: onTakeOver,
                child: const Text('รับตำแหน่งแทน'),
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
        : describeRoomEntry(
            latest,
            view.nameOf,
            pressedBy: view.pressedByOther(latest),
          );
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

class RoomHistorySheet extends ConsumerStatefulWidget {
  const RoomHistorySheet({super.key, required this.code});

  final String code;

  @override
  ConsumerState<RoomHistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<RoomHistorySheet> {
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
                          final label = describeRoomEntry(
                            e,
                            view!.nameOf,
                            pressedBy: view.pressedByOther(e),
                          );
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
