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
///
/// A device only holds the newest entries of a long game, which cannot be
/// added up (the balances they start from are not known). Then it only checks
/// that the entries are in an unbroken row ending at `state.seq - 1`; that the
/// money is right is the Firestore rules' job.
BalanceCheck checkBalances({
  required RoomState state,
  required List<RoomEntry> entries,
  required RoomSettings settings,
}) {
  final first = entries.isEmpty ? 0 : entries.first.seq;
  if (first > 0) {
    if (entries.last.seq != state.seq - 1) return BalanceCheck.syncing;
    for (final (i, entry) in entries.indexed) {
      if (entry.seq != first + i || entry.at == null) {
        return BalanceCheck.syncing;
      }
    }
    return BalanceCheck.ok;
  }
  if (entries.length != state.seq) return BalanceCheck.syncing;
  for (final (i, entry) in entries.indexed) {
    if (entry.seq != i || entry.at == null) return BalanceCheck.syncing;
  }
  final held = _replay(state, entries, settings);
  // An entry the rules refuse is a fault, whatever the balances say.
  if (held == null) return BalanceCheck.mismatch;
  if (_same(held, state.balances)) return BalanceCheck.ok;
  // An undo changes the newest entry and the balances at the same time but
  // reaches this device in two pieces; if the balances fit the entry the
  // other way round, the other piece is on its way.
  if (entries.isNotEmpty) {
    final last = entries.last;
    final flipped = [
      ...entries.take(entries.length - 1),
      last.copyWith(voided: !last.voided),
    ];
    final other = _replay(state, flipped, settings);
    if (other != null && _same(other, state.balances)) {
      return BalanceCheck.syncing;
    }
  }
  return BalanceCheck.mismatch;
}

/// The balances the entries add up to from the start, or null when the rules
/// of the money refuse one of them.
Map<String, int>? _replay(
  RoomState state,
  List<RoomEntry> entries,
  RoomSettings settings,
) {
  var ledger = Ledger.initial(
    state.seats,
    settings.startingCash,
    bankLimit: settings.bankLimit,
  );
  for (final entry in entries) {
    final result = Ledger.apply(ledger, entry);
    if (result is! Applied) return null;
    ledger = result.state;
  }
  return ledger.balances;
}

bool _same(Map<String, int> held, Map<String, int> stored) =>
    held.length == stored.length &&
    held.entries.every((e) => stored[e.key] == e.value);
