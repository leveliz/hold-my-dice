import 'dart:math';

import 'package:hold_my_dice/features/room/domain/room_entry.dart';

const _codeAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// A new press code: 20 letters and digits nobody else will have drawn.
String newPressCode([Random? random]) => _newCode(random);

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

  /// [mortgage]: what the person raises by mortgage in the same press, when
  /// the cash does not cover [amount].
  EntryDraft.payBank(
    int amount, {
    String? reason,
    int? mortgage,
    String? cid,
    Random? random,
  }) : this._(
         EntryKind.payBank,
         amount,
         reason,
         cid ?? _newCode(random),
         null,
         mortgage,
       );

  /// Money from the person who presses to the person at [toSeat].
  EntryDraft.transfer(
    String toSeat,
    int amount, {
    String? reason,
    int? mortgage,
    String? cid,
    Random? random,
  }) : this._(
         EntryKind.transfer,
         amount,
         reason,
         cid ?? _newCode(random),
         toSeat,
         mortgage,
       );

  /// The person goes out of the game because they cannot pay [owed] to the
  /// seat [creditorSeat] (the bank when null). What they hold at that moment
  /// is read when the press is made, not here.
  EntryDraft.bankrupt(
    this.owed, {
    this.creditorSeat,
    String? cid,
    Random? random,
  }) : kind = EntryKind.bankrupt,
       amount = null,
       reason = null,
       toSeat = null,
       mortgage = null,
       forSeat = null,
       cid = cid ?? _newCode(random);

  const EntryDraft._(
    this.kind,
    this.amount,
    this.reason,
    this.cid, [
    this.toSeat,
    this.mortgage,
  ]) : creditorSeat = null,
       owed = null,
       forSeat = null;

  EntryDraft._copy(EntryDraft d, this.forSeat)
    : kind = d.kind,
      amount = d.amount,
      reason = d.reason,
      cid = d.cid,
      toSeat = d.toSeat,
      mortgage = d.mortgage,
      owed = d.owed,
      creditorSeat = d.creditorSeat;

  /// The same press, made by the banker for the seat [seat] (the one whose
  /// balance changes; another seat than the banker's own). It keeps the press
  /// code.
  EntryDraft onBehalfOf(String seat) => EntryDraft._copy(this, seat);

  final EntryKind kind;
  final int? amount;
  final String? reason;
  final String cid;

  /// Who gets the money; only a transfer has one.
  final String? toSeat;

  /// What is raised by mortgage to make the payment; null for none.
  final int? mortgage;

  /// Of a bankruptcy: the debt, and who is owed (null: the bank).
  final int? owed;
  final String? creditorSeat;

  /// The seat the banker presses for; null when the person presses for their
  /// own seat.
  final String? forSeat;
}
