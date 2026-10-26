import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

/// What adding up the history says about the balances.
enum BalanceCheck {
  /// The history and the state do not describe the same moment yet (they come
  /// from two listeners), so nothing can be said.
  syncing,

  /// The history adds up to exactly the balances.
  ok,

  /// The history and the balances disagree.
  mismatch,
}

/// Adds the history up from the start of the game with the rules of the money
/// and compares it with the balances in [state]. It only compares when the
/// history is whole: the entries numbered 0 up to `state.seq - 1`, none still
/// on its way. Otherwise it says [BalanceCheck.syncing], so a state that
/// arrives a moment before its entry is not taken for a fault.
BalanceCheck checkBalances({
  required RoomState state,
  required List<RoomEntry> entries,
  required RoomSettings settings,
}) {
  if (entries.length != state.seq) return BalanceCheck.syncing;
  for (final (i, entry) in entries.indexed) {
    if (entry.seq != i || entry.at == null) return BalanceCheck.syncing;
  }
  var ledger = Ledger.initial(
    state.seats,
    settings.startingCash,
    bankLimit: settings.bankLimit,
  );
  for (final entry in entries) {
    final result = Ledger.apply(ledger, entry);
    if (result is! Applied) return BalanceCheck.mismatch;
    ledger = result.state;
  }
  final held = ledger.balances;
  final stored = state.balances;
  final same =
      held.length == stored.length &&
      held.entries.every((e) => stored[e.key] == e.value);
  return same ? BalanceCheck.ok : BalanceCheck.mismatch;
}
