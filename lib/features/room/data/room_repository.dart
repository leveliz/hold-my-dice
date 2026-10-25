import 'package:hold_my_dice/features/room/domain/room_models.dart';

/// What went wrong with a room operation, in terms a person can be told.
enum RoomError {
  roomNotFound,
  wrongPassword,
  roomFull,
  alreadyStarted,
  seatTaken,
  seatStillActive,
  notOwner,
  notEnoughPlayers,
  spectatorsNotAllowed,
  notAMember,
  unsupportedVersion,
  offline,
  unknown,
}

class RoomException implements Exception {
  const RoomException(this.error, [this.detail]);

  final RoomError error;
  final String? detail;

  @override
  String toString() =>
      'RoomException($error${detail == null ? '' : ': $detail'})';
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

  Stream<List<Member>> watchMembers(String code);

  /// Owner only: starts the game with the seats taken so far.
  Future<void> startGame(String code);

  /// Null until the game starts.
  Stream<RoomState?> watchState(String code);

  /// Records that this person is still here (their own presence only).
  Future<void> heartbeat(String code);
}
