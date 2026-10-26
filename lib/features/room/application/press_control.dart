import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

/// How long the buttons rest after a press, so a double tap is one press.
final pressCooldownProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1500),
);

/// How long, online, a press of unknown fate is waited for before it is taken
/// as not written.
final pressPatienceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 20),
);

/// What is going on with this person's presses.
class PressState {
  const PressState({
    this.sending = false,
    this.cooling = false,
    this.unsureCid,
  });

  /// A press is on its way to the room.
  final bool sending;

  /// A press just went in; the buttons rest for a moment.
  final bool cooling;

  /// The code of a press that may or may not have been written; no new press
  /// is made until it is known.
  final String? unsureCid;
}

/// Why the money buttons cannot be used now, most basic reason first.
enum PressBlock {
  none,
  spectator,
  out,
  unsure,
  offline,
  mismatch,
  sending,
  cooling,
}

/// Whether a press can be made, and if not, why. While the balances are still
/// being added up ([BalanceCheck.syncing]) pressing is allowed: the press is
/// decided by the room, not by this screen.
PressBlock pressBlock({
  required String? mySeat,
  required bool seatActive,
  required bool online,
  required BalanceCheck check,
  required PressState press,
}) {
  if (mySeat == null) return PressBlock.spectator;
  if (!seatActive) return PressBlock.out;
  if (press.unsureCid != null) return PressBlock.unsure;
  if (!online) return PressBlock.offline;
  if (check == BalanceCheck.mismatch) return PressBlock.mismatch;
  if (press.sending) return PressBlock.sending;
  if (press.cooling) return PressBlock.cooling;
  return PressBlock.none;
}

/// Makes the presses of one person in one room, one at a time.
class PressController extends Notifier<PressState> {
  PressController(this.code);

  final String code;
  Timer? _rest;
  Timer? _patience;

  @override
  PressState build() {
    ref.onDispose(() {
      _rest?.cancel();
      _patience?.cancel();
    });
    // A press of unknown fate is settled by the history: if its code shows up
    // there, it was written.
    ref.listen(roomEntriesProvider(code), (_, next) {
      final cid = state.unsureCid;
      if (cid != null && _written(cid, next.value)) _settle();
    });
    // The wait for it only runs while there is a connection.
    ref.listen(roomOnlineProvider(code), (_, next) {
      if (state.unsureCid == null) return;
      next.value == false ? _patience?.cancel() : _startPatience();
    });
    return const PressState();
  }

  /// Makes the press and gives the error to show, or null when it went in
  /// (or when it was left alone because another one is still being settled).
  Future<RoomError?> press(EntryDraft draft) async {
    if (state.sending || state.cooling || state.unsureCid != null) return null;
    state = const PressState(sending: true);
    try {
      await ref.read(roomRepositoryProvider).submitEntry(code, draft);
    } on RoomException catch (e) {
      if (e.error == RoomError.unsure) {
        state = PressState(unsureCid: draft.cid);
        // Its entry may have reached the history while the answer was lost.
        if (_written(draft.cid, ref.read(roomEntriesProvider(code)).value)) {
          _settle();
        } else {
          _startPatience();
        }
      } else {
        state = const PressState();
      }
      return e.error;
    } catch (_) {
      state = const PressState();
      return RoomError.unknown;
    }
    state = const PressState(cooling: true);
    _rest = Timer(
      ref.read(pressCooldownProvider),
      () => state = const PressState(),
    );
    return null;
  }

  static bool _written(String cid, List<RoomEntry>? history) =>
      (history ?? const []).any((e) => e.cid == cid);

  void _startPatience() {
    _patience?.cancel();
    final online = ref.read(roomOnlineProvider(code)).value ?? true;
    if (!online) return;
    _patience = Timer(ref.read(pressPatienceProvider), _settle);
  }

  void _settle() {
    _patience?.cancel();
    state = const PressState();
  }
}

final pressControllerProvider = NotifierProvider.autoDispose
    .family<PressController, PressState, String>(PressController.new);
