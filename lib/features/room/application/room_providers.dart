import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

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

/// The room as it is now and as it changes; null when there is none or it has
/// ended.
final roomMetaProvider = StreamProvider.autoDispose.family<RoomMeta?, String>(
  (ref, code) => ref
      .watch(roomRepositoryProvider)
      .watchMeta(code)
      .map((meta) => meta?.status == RoomStatus.ended ? null : meta),
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

/// The link a friend opens to join: on the web the page's own address, in the
/// installed app the public site.
String roomShareLink(String code) =>
    '${kIsWeb ? Uri.base.origin : 'https://hold-my-dice.pages.dev'}/room/$code';
