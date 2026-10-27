import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

/// When a provider that failed is tried again by itself. Riverpod's own rule
/// tries ten times, and each try of a room read costs quota, so a room that is
/// not there, a newer layout or a refusal is not tried again: the page says so
/// and offers its own button. Only a lost connection is waited out. Other
/// errors keep Riverpod's rule.
Duration? roomRetry(int retryCount, Object error) {
  if (error is RoomException) {
    return error.error == RoomError.offline
        ? ProviderContainer.defaultRetry(retryCount, error)
        : null;
  }
  return ProviderContainer.defaultRetry(retryCount, error);
}

/// Who this device is. Tests get a made-up person; `productionOverrides`
/// swaps in Firebase Auth once Firebase is set up.
final authServiceProvider = Provider<AuthService>(
  (ref) => FakeAuthService('test-user'),
);

/// The rooms. Tests get an in-memory fake that never touches the network;
/// `productionOverrides` swaps in Firestore.
final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => FakeRoomRepository(FakeRoomStore(), ref.watch(authServiceProvider)),
);

/// Whether the multi-device mode is offered. Only a build with Firebase set up
/// can have rooms, so `productionOverrides` turns it on then.
final multiDeviceEnabledProvider = Provider<bool>((ref) => false);

/// The room as it is now and as it changes (also once it has ended, for the
/// summary); null when there is none.
final roomMetaProvider = StreamProvider.autoDispose.family<RoomMeta?, String>(
  (ref, code) => ref.watch(roomRepositoryProvider).watchMeta(code),
);

/// Everyone in the room, live. Only members may read it.
final roomMembersProvider = StreamProvider.autoDispose
    .family<List<Member>, String>(
      (ref, code) => ref.watch(roomRepositoryProvider).watchMembers(code),
    );

/// This person's own place in the room, null if they have not joined. Refresh
/// it (`ref.invalidate`) after joining.
final myMemberProvider = FutureProvider.autoDispose.family<Member?, String>(
  (ref, code) => ref.watch(roomRepositoryProvider).readMyMember(code),
);

/// The eight seats, null where nobody sits. Read once; refresh after joining.
final roomSeatsProvider = FutureProvider.autoDispose
    .family<List<Seat?>, String>(
      (ref, code) => ref.watch(roomRepositoryProvider).readSeats(code),
    );

/// The balances and progress of the game; null until it starts. Members only.
final roomStateProvider = StreamProvider.autoDispose.family<RoomState?, String>(
  (ref, code) => ref.watch(roomRepositoryProvider).watchState(code),
);

/// The history of the game, oldest first, live. Members only.
final roomEntriesProvider = StreamProvider.autoDispose
    .family<List<RoomEntry>, String>(
      (ref, code) => ref.watch(roomRepositoryProvider).watchEntries(code),
    );

/// Whether this device can reach the service.
final roomOnlineProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, code) => ref.watch(roomRepositoryProvider).watchOnline(code),
);

/// The link a friend opens to join: on the web the page's own address, in the
/// installed app the public site.
String roomShareLink(String code) =>
    '${kIsWeb ? Uri.base.origin : 'https://hold-my-dice.pages.dev'}/room/$code';

/// Every request to pay of the room, live (also the closed ones).
final roomRequestsProvider = StreamProvider.autoDispose
    .family<List<RoomRequest>, String>(
      (ref, code) => ref.watch(roomRepositoryProvider).watchRequests(code),
    );
