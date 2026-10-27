import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart'
    show undoWindow;
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

/// How long the "undo" bar is offered. The room allows a little longer
/// (6.5 seconds); the rest is room for the answer to travel.
final undoOfferWindowProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

/// What is kept back from the time the room allows, for the answer to travel.
const _undoMargin = Duration(seconds: 1);

/// Less than this is left: not worth offering.
const _undoLeast = Duration(seconds: 1);

/// A press this much older than this device's clock says is not about the
/// connection but about the clocks: the room's time is not trusted. (One that
/// is newer than the clock leaves more than the offer lasts, so it is not
/// shortened.)
const _clockDoubt = Duration(seconds: 30);

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
          last.by == view.myUid &&
          last.seq == view.state.seq - 1 &&
          last.seq > baseline &&
          last.at != null &&
          !last.voided &&
          _undoable.contains(last.kind) &&
          // The request it paid would stay "paid" with nothing paid.
          last.reason != requestReason;
      // The room allows a press to be taken back for a little longer than the
      // offer lasts, counted from its own time. News that comes late leaves
      // less of it: the offer is shortened to what is left, and not made when
      // that is too little.
      final entry = offered ? last : null;
      final window = entry == null ? null : _windowFor(entry);
      if (entry != null && window != null) {
        if (state?.seq != entry.seq) {
          _timer?.cancel();
          _timer = Timer(window, _clear);
          state = UndoOffer(entry, window);
        }
      } else if (state != null) {
        _clear();
      }
    }, fireImmediately: true);
    return null;
  }

  /// How long to offer taking back [entry] (it has its time), or null if it
  /// is too late.
  Duration? _windowFor(RoomEntry entry) {
    final window = ref.read(undoOfferWindowProvider);
    final age = ref.read(roomClockProvider)().difference(entry.at!);
    if (age > _clockDoubt) return window;
    final left = undoWindow - age - _undoMargin;
    if (left < _undoLeast) return null;
    return left < window ? left : window;
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}

final undoOfferProvider = NotifierProvider.autoDispose
    .family<UndoOfferController, UndoOffer?, String>(UndoOfferController.new);
