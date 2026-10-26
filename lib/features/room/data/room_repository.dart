import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

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
  if (draft.kind == EntryKind.receive) {
    throw const RoomException(RoomError.reasonRequired);
  }
  return null;
}

/// What a refusal by the money rules is called to the person.
RoomError roomErrorOf(LedgerRejection rejection) => switch (rejection) {
  LedgerRejection.insufficient => RoomError.insufficientFunds,
  LedgerRejection.bankLimit => RoomError.bankEmpty,
  LedgerRejection.notActive => RoomError.notAPlayer,
  LedgerRejection.invalidAmount => RoomError.invalidAmount,
  LedgerRejection.invalidParties => RoomError.invalidParties,
  LedgerRejection.notUndoable => RoomError.tooLate,
  _ => RoomError.unknown,
};

class RoomException implements Exception {
  const RoomException(this.error, [this.detail]);

  final RoomError error;
  final String? detail;

  @override
  String toString() =>
      'RoomException($error${detail == null ? '' : ': $detail'})';
}

/// How many of the newest entries a device listens to.
const historyWindow = 30;

/// A press that was given up on waiting for but may still be going through.
/// [settled] completes (never with an error) when the attempt is over, written
/// or not; until then pressing again could count the same money twice.
class UnsureException extends RoomException {
  UnsureException(this.settled) : super(RoomError.unsure);

  final Future<void> settled;
}

/// Whether the stored entry [data] is the press with code [cid] made from
/// [seat]. The same press must never be written twice.
bool entryIsMine(Map<String, Object?>? data, String cid, String seat) =>
    data != null && data['cid'] == cid && data['seat'] == seat;

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

  /// The newest [historyWindow] entries of the game, oldest first, live.
  /// Members only. A long game is not read whole: every device would pay for
  /// all of it each time it opens the room.
  Stream<List<RoomEntry>> watchEntries(String code);

  /// Whether this device can reach the service, live (see `onlineFrom`).
  Stream<bool> watchOnline(String code);

  /// Records that this person is still here (their own presence only).
  Future<void> heartbeat(String code);
}
