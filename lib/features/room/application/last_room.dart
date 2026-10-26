import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:hold_my_dice/features/room/application/room_code.dart';

/// The room this device was last in, so the mode picker can offer the way
/// back after the app was closed.
class LastRoomStorage {
  LastRoomStorage(this._store);

  static const key = 'app.room.last.v1';

  final JsonStore _store;

  /// The saved code, or null when there is none or it is not a room code.
  String? read() {
    final code = _store.read(key)?['code'];
    return code is String ? normalizeRoomCode(code) : null;
  }

  // A store that cannot write (a private browser window) only means the way
  // back is not offered next time.
  void save(String code) {
    unawaited(_store.write(key, {'code': code}).catchError((Object _) {}));
  }
}

/// Remembers in memory only; what tests get.
class MemoryLastRoomStorage extends LastRoomStorage {
  MemoryLastRoomStorage() : super(MemoryJsonStore());
}

final lastRoomStorageProvider = Provider<LastRoomStorage>(
  (ref) => MemoryLastRoomStorage(),
);

/// The code of the room this device was last in, null if none.
class LastRoom extends Notifier<String?> {
  @override
  String? build() => ref.read(lastRoomStorageProvider).read();

  void remember(String code) {
    if (state == code) return;
    ref.read(lastRoomStorageProvider).save(code);
    state = code;
  }
}

final lastRoomProvider = NotifierProvider<LastRoom, String?>(LastRoom.new);
