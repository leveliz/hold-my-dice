import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';

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
