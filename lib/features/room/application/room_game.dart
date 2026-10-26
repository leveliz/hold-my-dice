import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/application/balance_check.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

/// Everything the play screen of a room shows, from one person's point of view.
class RoomGameView {
  const RoomGameView({
    required this.state,
    required this.entries,
    required this.settings,
    required this.mySeat,
    required this.names,
    required this.colors,
    required this.online,
    required this.check,
    required this.press,
    required this.block,
  });

  final RoomState state;

  /// The history, oldest first.
  final List<RoomEntry> entries;
  final RoomSettings settings;

  /// The seat this person presses for; null for a spectator.
  final String? mySeat;

  /// The name and the colour of whoever sits at each seat.
  final Map<String, String> names;
  final Map<String, int> colors;
  final bool online;
  final BalanceCheck check;
  final PressState press;

  /// Why the money buttons are off, or [PressBlock.none].
  final PressBlock block;

  bool get isSpectator => mySeat == null;
  bool get seatActive => mySeat != null && !state.bankrupt.contains(mySeat);

  /// The players in the order of their seats.
  List<String> get seats => state.seats;
  Map<String, int> get balances => state.balances;
  int? get myBalance => mySeat == null ? null : state.balances[mySeat];

  String nameOf(String seat) => names[seat] ?? seat;
  int? colorOf(String seat) => colors[seat];
}

/// The play screen's picture of a room, or loading while a piece is missing
/// (the game not started yet, a stream not delivered) and an error when one of
/// them failed (the room is gone, this person is not in it).
final roomGameProvider = Provider.autoDispose
    .family<AsyncValue<RoomGameView>, String>((ref, code) {
      final state = ref.watch(roomStateProvider(code));
      final entries = ref.watch(roomEntriesProvider(code));
      final meta = ref.watch(roomMetaProvider(code));
      final members = ref.watch(roomMembersProvider(code));
      final me = ref.watch(myMemberProvider(code));
      final online = ref.watch(roomOnlineProvider(code));
      final press = ref.watch(pressControllerProvider(code));

      for (final piece in [state, entries, meta, members, me]) {
        if (piece.hasError) {
          return AsyncError(piece.error!, piece.stackTrace ?? StackTrace.empty);
        }
      }
      final s = state.value;
      final e = entries.value;
      final m = meta.value;
      final people = members.value;
      if (s == null ||
          e == null ||
          m == null ||
          people == null ||
          me.isLoading) {
        return const AsyncLoading();
      }

      final seat = me.value?.seat;
      final seatActive = seat != null && !s.bankrupt.contains(seat);
      final isOnline = online.value ?? true;
      final check = checkBalances(state: s, entries: e, settings: m.settings);
      return AsyncData(
        RoomGameView(
          state: s,
          entries: e,
          settings: m.settings,
          mySeat: seat,
          names: {
            for (final p in people)
              if (p.seat != null) p.seat!: p.name,
          },
          colors: {
            for (final p in people)
              if (p.seat != null) p.seat!: p.color,
          },
          online: isOnline,
          check: check,
          press: press,
          block: pressBlock(
            mySeat: seat,
            seatActive: seatActive,
            online: isOnline,
            check: check,
            press: press,
          ),
        ),
      );
    });
