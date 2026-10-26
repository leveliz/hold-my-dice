import 'package:hold_my_dice/features/room/domain/ledger.dart';

/// The longest name the Firestore rules accept, measured the way their
/// `size()` does: in UTF-16 units, so an emoji counts as two.
const maxNameLength = 20;

/// The longest reason the rules accept, measured the same way.
const maxReasonLength = 60;

/// [text] cut to [max] UTF-16 units without splitting a character.
String cutText(String text, int max) {
  final out = StringBuffer();
  var units = 0;
  for (final rune in text.runes) {
    final width = rune > 0xFFFF ? 2 : 1;
    if (units + width > max) break;
    out.writeCharCode(rune);
    units += width;
  }
  return out.toString();
}

String cutName(String name) => cutText(name, maxNameLength);

String cutReason(String reason) => cutText(reason, maxReasonLength);

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
    this.endedAt,
    this.nextCode,
  });

  final String code;
  final String ownerUid;
  final RoomStatus status;
  final RoomSettings settings;
  final bool hasPassword;

  /// When the game ended, by the room's clock; null before it ends (and for a
  /// write still on its way).
  final DateTime? endedAt;

  /// The code of the room the owner opened for the next game, once they did.
  final String? nextCode;
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

  /// Reads a stored state. Anything missing or of the wrong kind (a balance
  /// with decimals, say) is a [FormatException] and not a crash deep in a
  /// widget, because one bad document would otherwise break every phone.
  factory RoomState.fromMap(Map<String, Object?> data) {
    T need<T>(String key) {
      final value = data[key];
      if (value is! T) {
        throw FormatException('state field "$key" is missing or wrong: $value');
      }
      return value;
    }

    List<String> strings(String key) {
      final list = need<List<Object?>>(key);
      return [
        for (final item in list)
          item is String
              ? item
              : throw FormatException('state field "$key" holds $item'),
      ];
    }

    final rawBalances = need<Map<Object?, Object?>>('balances');
    final balances = <String, int>{};
    for (final MapEntry(:key, :value) in rawBalances.entries) {
      if (key is! String || value is! int) {
        throw FormatException('state balance "$key" is $value');
      }
      balances[key] = value;
    }
    final statusName = need<String>('status');
    final status = RoomStatus.values
        .where((s) => s.name == statusName)
        .firstOrNull;
    if (status == null) {
      throw FormatException('state field "status" is unknown: $statusName');
    }
    final banker = data['bankerSeat'];
    if (banker != null && banker is! String) {
      throw FormatException('state field "bankerSeat" is $banker');
    }
    return RoomState(
      seq: need<int>('seq'),
      seats: strings('seats'),
      balances: balances,
      bankrupt: strings('bankrupt'),
      bankerSeat: banker as String?,
      status: status,
    );
  }

  /// The money side of this state, for the rules of the ledger. The starting
  /// cash belongs to the room, not to the state.
  LedgerState toLedger(RoomSettings settings) => LedgerState(
    balances: balances,
    bankrupt: bankrupt,
    bankerSeat: bankerSeat,
    startingCash: settings.startingCash,
  );
}
