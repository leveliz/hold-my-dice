import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

const _bankKinds = {EntryKind.receive, EntryKind.passGo, EntryKind.payBank};

/// Entries older than this, next to the newest one, are history that a late
/// snapshot brought along, not news.
const _newsAge = Duration(seconds: 60);

/// Finds, in the history as it changes, what the person should be told: money
/// that was transferred to them, such a transfer being taken back, and another
/// player going out of the game. It does not tell what was there when the
/// screen opened, and tells each thing once.
class IncomingTracker {
  IncomingTracker({required this.mySeat});

  final String mySeat;

  /// The newest number in the first list seen; everything up to it is old.
  int? _baseline;
  final _announced = <int>{};
  final _cancelled = <int>{};

  /// The lines to show now (empty most of the time). Call it with every new
  /// version of the list; it is safe to call with the same list again.
  List<String> update(
    List<RoomEntry> entries,
    String Function(String seat) nameOf, {
    String? Function(RoomEntry e)? pressedByOther,
  }) {
    final baseline = _baseline;
    if (baseline == null) {
      _baseline = entries.isEmpty ? -1 : entries.last.seq;
      return const [];
    }
    final newestAt = entries.isEmpty ? null : entries.last.at;
    final lines = <String>[];
    for (final e in entries) {
      final out = e.kind == EntryKind.bankrupt && e.seat != mySeat;
      final forMe =
          e.kind == EntryKind.transfer && e.to == mySeat && e.seat != mySeat;
      final bankerName =
          e.seat == mySeat &&
              (_bankKinds.contains(e.kind) || e.kind == EntryKind.bankrupt)
          ? pressedByOther?.call(e)
          : null;
      if (!forMe && !out && bankerName == null) continue;
      if (bankerName != null && e.voided) continue;
      final who = nameOf(e.seat);
      final amount = formatMoney(e.amount ?? 0);
      if (e.voided && forMe) {
        if (_announced.contains(e.seq) && _cancelled.add(e.seq)) {
          lines.add('$who ยกเลิกการโอน $amount');
        }
        continue;
      }
      if (e.seq <= baseline || _announced.contains(e.seq)) continue;
      final at = e.at;
      if (at != null &&
          newestAt != null &&
          newestAt.difference(at) > _newsAge) {
        continue;
      }
      _announced.add(e.seq);
      if (bankerName != null) {
        final amount = formatMoney(e.amount ?? 0);
        final mortgage = e.mortgage == null
            ? ''
            : ' (จำนอง ${formatMoney(e.mortgage!)})';
        lines.add(switch (e.kind) {
          EntryKind.passGo => 'นายธนาคาร $bankerName กด GO ให้คุณ +$amount',
          EntryKind.payBank =>
            'นายธนาคาร $bankerName หักจากคุณ -$amount$mortgage',
          EntryKind.bankrupt => 'นายธนาคาร $bankerName ประกาศให้คุณล้มละลาย',
          _ => 'นายธนาคาร $bankerName ให้คุณ +$amount',
        });
        continue;
      }
      if (out) {
        final info = e.bankrupt;
        lines.add(
          info != null && info.creditorSeat == mySeat
              ? '$who ล้มละลาย คุณได้รับ +${formatMoney(info.owed)}'
              : '$who ล้มละลาย',
        );
        continue;
      }
      lines.add(
        e.reason == requestReason
            ? '$who จ่ายตามที่เรียกเก็บ +$amount'
            : '$who โอนให้คุณ +$amount',
      );
    }
    return lines;
  }
}

/// A set of lines to show together; [id] tells one batch from the next.
class IncomingBatch {
  const IncomingBatch(this.id, this.lines);

  final int id;
  final List<String> lines;
}

/// Watches the history of a room for things to tell this person.
class IncomingEvents extends Notifier<IncomingBatch?> {
  IncomingEvents(this.code);

  final String code;
  IncomingTracker? _tracker;
  var _count = 0;

  @override
  IncomingBatch? build() {
    ref.listen(roomGameProvider(code), (_, next) {
      final view = next.value;
      if (view == null) return;
      final seat = view.mySeat;
      if (seat == null) return;
      final tracker = _tracker ??= IncomingTracker(mySeat: seat);
      final lines = tracker.update(
        view.entries,
        view.nameOf,
        pressedByOther: view.pressedByOther,
      );
      if (lines.isNotEmpty) state = IncomingBatch(++_count, lines);
    }, fireImmediately: true);
    return null;
  }
}

final incomingEventsProvider = NotifierProvider.autoDispose
    .family<IncomingEvents, IncomingBatch?, String>(IncomingEvents.new);
