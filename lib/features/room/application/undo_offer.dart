import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

/// How long the "undo" bar is offered. The room allows a little longer
/// (6.5 seconds); the rest is room for the answer to travel.
final undoOfferWindowProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

/// The press that can be taken back right now.
class UndoOffer {
  const UndoOffer(this.entry, this.window);

  final RoomEntry entry;
  final Duration window;

  int get seq => entry.seq;
}

const _undoable = {
  EntryKind.receive,
  EntryKind.passGo,
  EntryKind.payBank,
  EntryKind.transfer,
};

/// Offers to take back this person's latest press, for a few seconds, as long
/// as it is still the latest entry of the game. Only a press that arrives
/// while the screen is open is offered: one that was already there when it
/// opened (a reload) is too old to be taken back.
class UndoOfferController extends Notifier<UndoOffer?> {
  UndoOfferController(this.code);

  final String code;
  int? _baseline;
  Timer? _timer;

  @override
  UndoOffer? build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(roomGameProvider(code), (_, next) {
      final view = next.value;
      if (view == null) return;
      final entries = view.entries;
      final baseline = _baseline;
      if (baseline == null) {
        _baseline = entries.isEmpty ? -1 : entries.last.seq;
        return;
      }
      final last = entries.isEmpty ? null : entries.last;
      final offered =
          last != null &&
          last.seat == view.mySeat &&
          last.seq == view.state.seq - 1 &&
          last.seq > baseline &&
          last.at != null &&
          !last.voided &&
          _undoable.contains(last.kind) &&
          // The request it paid would stay "paid" with nothing paid.
          last.reason != requestReason;
      if (offered) {
        if (state?.seq != last.seq) {
          final window = ref.read(undoOfferWindowProvider);
          _timer?.cancel();
          _timer = Timer(window, _clear);
          state = UndoOffer(last, window);
        }
      } else if (state != null) {
        _clear();
      }
    }, fireImmediately: true);
    return null;
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}

final undoOfferProvider = NotifierProvider.autoDispose
    .family<UndoOfferController, UndoOffer?, String>(UndoOfferController.new);
