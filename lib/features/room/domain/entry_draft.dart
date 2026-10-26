import 'dart:math';

import 'package:hold_my_dice/features/room/domain/room_entry.dart';

const _codeAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

String _newCode(Random? random) {
  final rng = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 20; i++)
      _codeAlphabet.codeUnitAt(rng.nextInt(_codeAlphabet.length)),
  ]);
}

/// What a person asks the room to write when they press a button. The room
/// fills in the seat, the number in the history, who pressed and when.
///
/// Every press has a code of its own ([cid]). A press that is sent again (the
/// answer was lost, the phone asked twice) carries the same code, so the room
/// can tell it from a new one and write it once.
class EntryDraft {
  EntryDraft.receive(int amount, String? reason, {String? cid, Random? random})
    : this._(EntryKind.receive, amount, reason, cid ?? _newCode(random));

  /// The amount is the room's own pass-over-GO amount, not the person's.
  EntryDraft.passGo({String? cid, Random? random})
    : this._(EntryKind.passGo, null, null, cid ?? _newCode(random));

  EntryDraft.payBank(int amount, {String? reason, String? cid, Random? random})
    : this._(EntryKind.payBank, amount, reason, cid ?? _newCode(random));

  const EntryDraft._(this.kind, this.amount, this.reason, this.cid);

  final EntryKind kind;
  final int? amount;
  final String? reason;
  final String cid;
}
