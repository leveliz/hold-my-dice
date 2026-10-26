import 'package:hold_my_dice/features/bank/domain/transaction.dart' as bank;
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

/// What went wrong with a room operation, in terms a person can be told.
enum RoomError {
  roomNotFound,
  wrongPassword,
  roomFull,
  alreadyStarted,
  seatTaken,
  seatStillActive,
  ownerStillActive,

  /// The game has not started yet.
  notStarted,

  /// The person has no seat that can press (a spectator, or out of the game).
  notAPlayer,

  /// Not enough money for the payment.
  insufficientFunds,

  /// The bank holds less than it was asked to pay.
  bankEmpty,

  /// Receiving from the bank needs a reason.
  reasonRequired,

  /// The amount is not a whole number from 1 to 999,999,999.
  invalidAmount,

  /// A mortgage that is not needed, does not cover what is missing, or leaves
  /// more over than a fifth of the starting cash.
  invalidMortgage,

  /// A bankruptcy of a person who can pay the debt, or of a debt over ten
  /// times the starting cash.
  invalidBankrupt,

  /// The person owed in a bankruptcy is out of the game.
  creditorOut,

  /// A banker is in the game: the bank's buttons are theirs alone.
  bankerPresses,

  /// Only the banker can do this (press for others, hand the seat on), and
  /// only for the bank's buttons.
  notBanker,

  /// The banker was seen less than 2 minutes ago: the seat cannot be taken.
  bankerStillActive,

  /// Other presses kept getting in first and the press was given up.
  conflict,

  /// The press may or may not have been written (no answer in time).
  unsure,

  /// The free daily quota of the service is used up.
  quotaExhausted,

  /// The money cannot go to that person (out of the game, or not a player).
  invalidParties,

  /// Too late to undo: something came after it, or the time is up.
  tooLate,

  /// The person already has a request to pay open to that person.
  requestOpen,

  /// The request is closed, ran out or is not there.
  requestGone,

  /// The request was paid already.
  alreadyPaid,
  notOwner,
  notEnoughPlayers,
  spectatorsNotAllowed,
  notAMember,
  unsupportedVersion,
  offline,
  unknown,
}

/// The reason of a press as it is stored: trimmed, cut to the limit (without
/// splitting an emoji), a GO's own words. A receive without one is refused; a
/// payment without one has none.
String? storedReason(EntryDraft draft) {
  if (draft.kind == EntryKind.passGo) return goReason;
  final text = cutReason((draft.reason ?? '').trim()).trim();
  if (text.isNotEmpty) return text;
  // The banker pressing for somebody else needs no reason.
  if (draft.kind == EntryKind.receive && draft.forSeat == null) {
    throw const RoomException(RoomError.reasonRequired);
  }
  return null;
}

/// The seat a press is for, or the refusal. A person presses for their own
/// seat; with a banker in the game the bank's buttons (receive, GO, pay the
/// bank, and a payment helped by a mortgage) are the banker's alone, and the
/// banker presses them (and declares a bankruptcy owed to the bank) for any
/// seat with [EntryDraft.onBehalfOf].
({String? seat, RoomError? error}) pressTarget(
  EntryDraft draft, {
  required String mySeat,
  required String? bankerSeat,
}) {
  final bankKind =
      draft.kind == EntryKind.receive ||
      draft.kind == EntryKind.passGo ||
      draft.kind == EntryKind.payBank;
  final forOther = draft.forSeat != null && draft.forSeat != mySeat;
  if (forOther) {
    final allowed =
        bankerSeat != null &&
        mySeat == bankerSeat &&
        (bankKind ||
            (draft.kind == EntryKind.bankrupt && draft.creditorSeat == null));
    return allowed
        ? (seat: draft.forSeat, error: null)
        : (seat: null, error: RoomError.notBanker);
  }
  final bankAction =
      bankKind || (draft.kind == EntryKind.transfer && draft.mortgage != null);
  if (bankerSeat != null && bankAction && mySeat != bankerSeat) {
    return (seat: null, error: RoomError.bankerPresses);
  }
  return (seat: mySeat, error: null);
}

/// What a refusal by the money rules is called to the person.
RoomError roomErrorOf(LedgerRejection rejection) => switch (rejection) {
  LedgerRejection.insufficient => RoomError.insufficientFunds,
  LedgerRejection.bankLimit => RoomError.bankEmpty,
  LedgerRejection.notActive => RoomError.notAPlayer,
  LedgerRejection.invalidAmount => RoomError.invalidAmount,
  LedgerRejection.invalidParties => RoomError.invalidParties,
  LedgerRejection.notUndoable => RoomError.tooLate,
  LedgerRejection.invalidMortgage => RoomError.invalidMortgage,
  LedgerRejection.invalidBankrupt => RoomError.invalidBankrupt,
};

class RoomException implements Exception {
  const RoomException(this.error, [this.detail]);

  final RoomError error;
  final String? detail;

  @override
  String toString() =>
      'RoomException($error${detail == null ? '' : ': $detail'})';
}

/// How long after it was written an entry can be taken back, by the room's
/// clock (the rules allow 6.5 seconds; the screen shows less).
const undoWindow = Duration(milliseconds: 6500);

/// How many of the newest entries a device listens to.
const historyWindow = 30;

/// A press that was given up on waiting for but may still be going through.
/// [settled] completes (never with an error) when the attempt is over, written
/// or not; until then pressing again could count the same money twice.
class UnsureException extends RoomException {
  UnsureException(this.settled) : super(RoomError.unsure);

  final Future<void> settled;
}

/// Whether the stored entry [data] is the press with code [cid] made by the
/// person [uid] (not by seat: a banker presses for other seats). The same
/// press must never be written twice.
bool entryIsMine(Map<String, Object?>? data, String cid, String uid) =>
    data != null && data['cid'] == cid && data['by'] == uid;

/// The entry a [draft] becomes when pressed by [uid] for [seat], as the next
/// line [seq]. [cash] is what the seat holds now (the facts of a bankruptcy).
RoomEntry entryOfDraft(
  EntryDraft draft, {
  required int seq,
  required String seat,
  required String uid,
  required int goAmount,
  required String? reason,
  required int cash,
  DateTime? at,
}) {
  if (draft.kind == EntryKind.bankrupt) {
    return RoomEntry(
      seq: seq,
      kind: draft.kind,
      seat: seat,
      by: uid,
      at: at,
      cid: draft.cid,
      bankrupt: BankruptInfo(
        seat: seat,
        creditorSeat: draft.creditorSeat,
        cash: cash,
        owed: draft.owed!,
      ),
    );
  }
  final pays =
      draft.kind == EntryKind.payBank || draft.kind == EntryKind.transfer;
  return RoomEntry(
    seq: seq,
    kind: draft.kind,
    seat: seat,
    by: uid,
    at: at,
    cid: draft.cid,
    from: pays ? seat : bank.Transaction.bank,
    to: draft.kind == EntryKind.payBank
        ? bank.Transaction.bank
        : draft.kind == EntryKind.transfer
        ? draft.toSeat
        : seat,
    amount: draft.kind == EntryKind.passGo ? goAmount : draft.amount,
    mortgage: draft.mortgage,
    reason: reason,
  );
}

/// Who the person using this device is. Anonymous: the same uid comes back
/// after a reload as long as the browser or phone keeps its storage.
abstract class AuthService {
  /// Signs in if needed and returns the uid.
  Future<String> ensureSignedIn();
}

/// Rooms of the multi-device mode. Every method acts as the signed-in person.
abstract class RoomRepository {
  /// Creates a room and sits its creator at p1.
  Future<RoomMeta> createRoom({
    required RoomSettings settings,
    String? password,
    required String name,
    required int color,
  });

  /// The room document; null when there is no such room.
  Stream<RoomMeta?> watchMeta(String code);

  /// The eight seats p1 to p8, null where nobody sits.
  Future<List<Seat?>> readSeats(String code);

  /// Takes the lowest free seat, or the seat already held by this person.
  Future<Seat> joinAsPlayer({
    required String code,
    required String name,
    required int color,
    String? password,
  });

  Future<void> joinAsSpectator({
    required String code,
    required String name,
    required int color,
    String? password,
  });

  /// Takes over [seatId] after losing the identity that held it, allowed when
  /// that identity has not been seen for 2 minutes.
  Future<Seat> claimSeat({
    required String code,
    required String seatId,
    String? password,
  });

  /// This person's own member document, null when they have not joined.
  Future<Member?> readMyMember(String code);

  /// Takes over a lobby whose owner has not been seen for 2 minutes. Taking
  /// over the owner's seat does this too.
  Future<void> claimOwnership(String code);

  Stream<List<Member>> watchMembers(String code);

  /// Owner only: starts the game with the seats taken so far.
  Future<void> startGame(String code);

  /// Null until the game starts.
  Stream<RoomState?> watchState(String code);

  /// Writes what the person pressed, for their own seat, as the next line of
  /// the history and the matching change of the balances. Refused with a
  /// [RoomException] (nothing is written) when it cannot be done.
  Future<void> submitEntry(String code, EntryDraft draft);

  /// Takes back the entry [seq], the person's own and the latest of the game,
  /// within a few seconds of the time the room's clock gave it: the balances
  /// go back and the entry stays in the history as undone. Taking back what
  /// was already taken back by this person does nothing. Refused with
  /// [RoomError.tooLate] when something came after it, it is not theirs, or
  /// the time is up.
  Future<void> undoEntry(String code, int seq);

  /// The banker hands the banker's seat on to the seat [toSeat] of the game.
  /// [RoomError.notBanker] for anybody else, [RoomError.invalidParties] for a
  /// seat that is not another seat of the game.
  Future<void> passBanker(String code, String toSeat);

  /// A person with a seat takes the banker's seat over from a banker who has
  /// not been seen for 2 minutes ([RoomError.bankerStillActive] otherwise).
  /// Their own presence is written with it.
  Future<void> takeOverBanker(String code);

  /// Asks the person at [fromSeat] to pay [amount] to this person. Each pair
  /// has room for one request: asking while the last one is open (and not
  /// older than [requestLifetime]) is [RoomError.requestOpen]; after it is
  /// closed or ran out the new one replaces it.
  Future<void> requestMoney(
    String code, {
    required String fromSeat,
    required int amount,
  });

  /// Closes the request, for the one who asked or the one asked. Closing what
  /// is closed does nothing; what was paid is [RoomError.alreadyPaid].
  Future<void> cancelRequest(String code, String id);

  /// Pays the request as a transfer with the press code [cid], and marks it
  /// paid, in one go. Paying again with the same code does nothing more;
  /// another code on a paid request is [RoomError.alreadyPaid]; a request
  /// that is cancelled, ran out or is missing is [RoomError.requestGone].
  Future<void> payRequest(
    String code,
    String id, {
    required String cid,
    int? mortgage,
  });

  /// Every request of the room (also the closed ones), live.
  Stream<List<RoomRequest>> watchRequests(String code);

  /// The newest [historyWindow] entries of the game, oldest first, live.
  /// Members only. A long game is not read whole: every device would pay for
  /// all of it each time it opens the room.
  Stream<List<RoomEntry>> watchEntries(String code);

  /// Whether this device can reach the service, live (see `onlineFrom`).
  Stream<bool> watchOnline(String code);

  /// Records that this person is still here (their own presence only).
  Future<void> heartbeat(String code);
}
