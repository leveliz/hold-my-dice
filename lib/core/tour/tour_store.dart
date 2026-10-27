import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/storage/json_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Names of the first-run tours and tips, as they are saved.
abstract final class TourIds {
  static const bank = 'bank';
  static const score = 'score';
  static const point = 'point';
  static const roomLobby = 'room-lobby';
  static const roomPlay = 'room-play';
  static const bankMoneyTip = 'bank-tip-money';
  static const bankUndoTip = 'bank-tip-undo';
  static const bankTips = [bankMoneyTip, bankUndoTip];

  /// Everything shown for one helper: its tour and the tips that go with it.
  static List<String> of(String helperId) => switch (helperId) {
    bank => [bank, ...bankTips, roomLobby, roomPlay],
    _ => [helperId],
  };
}

/// Which tours the person has already seen, so each shows only once. Kept
/// under a key of its own: the app settings key is rewritten whole whenever
/// the theme changes, which would wipe this list.
class TourStorage {
  TourStorage(this._store) : _seen = _load(_store);

  static const key = 'app.tour.v1';

  final JsonStore _store;
  final Set<String> _seen;

  static Set<String> _load(JsonStore store) {
    final raw = store.read(key)?['seen'];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  bool isSeen(String id) => _seen.contains(id);

  void markSeen(Iterable<String> ids) {
    _seen.addAll(ids);
    _save();
  }

  void forget(Iterable<String> ids) {
    _seen.removeAll(ids);
    _save();
  }

  // The session keeps its own copy, so a store that cannot write (a private
  // browser window) only means the tour may come back next visit.
  void _save() {
    unawaited(
      _store.write(key, {'seen': _seen.toList()}).catchError((Object _) {}),
    );
  }
}

/// Remembers in memory only.
class MemoryTourStorage extends TourStorage {
  MemoryTourStorage() : super(MemoryJsonStore());
}

class PrefsTourStorage extends TourStorage {
  PrefsTourStorage(SharedPreferences prefs) : super(PrefsJsonStore(prefs));
}

/// What tests get unless they ask for more: every tour counts as seen and
/// nothing can change that, so no test is covered by a tour it never meant to
/// open.
class AllSeenTourStorage extends MemoryTourStorage {
  @override
  bool isSeen(String id) => true;

  @override
  void markSeen(Iterable<String> ids) {}

  @override
  void forget(Iterable<String> ids) {}
}

final tourStorageProvider = Provider<TourStorage>(
  (ref) => AllSeenTourStorage(),
);
