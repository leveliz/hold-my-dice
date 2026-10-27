import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';

/// The passwords of the rooms this device made, kept on this device only so
/// the owner can read it again in the waiting room: the room itself keeps just
/// a proof of the password. Only the latest few are kept.
class RoomPasswordStorage {
  RoomPasswordStorage(this._store);

  static const key = 'app.room.passwords.v1';

  /// How many rooms' passwords are remembered.
  static const keep = 5;

  final JsonStore _store;

  /// Newest last; anything that is not a code and a password is dropped.
  List<({String code, String password})> _items() {
    final raw = _store.read(key)?['items'];
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map && item['code'] is String && item['password'] is String)
          (code: item['code'] as String, password: item['password'] as String),
    ];
  }

  /// The password this device gave the room [code], or null if it does not
  /// know one.
  String? read(String code) {
    for (final item in _items().reversed) {
      if (item.code == code) return item.password;
    }
    return null;
  }

  // A store that cannot write (a private browser window) only means the owner
  // is told the password is not known on this device.
  void save(String code, String password) {
    final items = [
      for (final item in _items())
        if (item.code != code) item,
      (code: code, password: password),
    ];
    final latest = items.length > keep
        ? items.sublist(items.length - keep)
        : items;
    unawaited(
      _store
          .write(key, {
            'items': [
              for (final item in latest)
                {'code': item.code, 'password': item.password},
            ],
          })
          .catchError((Object _) {}),
    );
  }

  void forget(String code) {
    final items = [
      for (final item in _items())
        if (item.code != code) item,
    ];
    unawaited(
      _store
          .write(key, {
            'items': [
              for (final item in items)
                {'code': item.code, 'password': item.password},
            ],
          })
          .catchError((Object _) {}),
    );
  }
}

/// Remembers in memory only; what tests get.
class MemoryRoomPasswordStorage extends RoomPasswordStorage {
  MemoryRoomPasswordStorage() : super(MemoryJsonStore());
}

final roomPasswordStorageProvider = Provider<RoomPasswordStorage>(
  (ref) => MemoryRoomPasswordStorage(),
);
