enum RoomStatus { lobby, playing, ended }

enum MemberRole { player, spectator }

/// How a room is set up. Money amounts are whole baht.
class RoomSettings {
  const RoomSettings({
    required this.startingCash,
    required this.goAmount,
    this.maxPlayers = 8,
    this.hideOthers = false,
    this.allowSpectators = true,
    this.bankLimit,
  });

  final int startingCash;
  final int goAmount;
  final int maxPlayers;

  /// Hides the other players' balances on screen; the data is still shared.
  final bool hideOthers;
  final bool allowSpectators;

  /// How much cash the bank holds; null means unlimited.
  final int? bankLimit;
}

/// The room document: what anyone who knows the code may see.
class RoomMeta {
  const RoomMeta({
    required this.code,
    required this.ownerUid,
    required this.status,
    required this.settings,
    required this.hasPassword,
  });

  final String code;
  final String ownerUid;
  final RoomStatus status;
  final RoomSettings settings;
  final bool hasPassword;
}

/// Who sits at a seat. [id] is `p1` to `p8`.
class Seat {
  const Seat({
    required this.id,
    required this.uid,
    required this.name,
    required this.color,
  });

  final String id;
  final String uid;
  final String name;
  final int color;
}

/// A person in the room: a player at a seat, or a spectator.
class Member {
  const Member({
    required this.uid,
    required this.name,
    required this.color,
    required this.role,
    this.seat,
  });

  final String uid;
  final String name;
  final int color;
  final MemberRole role;

  /// The seat id for a player; null for a spectator.
  final String? seat;
}

/// The money and progress of a started game.
class RoomState {
  const RoomState({
    required this.seq,
    required this.seats,
    required this.balances,
    required this.bankrupt,
    required this.bankerSeat,
    required this.status,
  });

  /// How many entries the game has; the next one has this number.
  final int seq;

  /// The seats that play, in order.
  final List<String> seats;
  final Map<String, int> balances;
  final List<String> bankrupt;
  final String? bankerSeat;
  final RoomStatus status;
}
