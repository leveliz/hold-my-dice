import 'dart:async';

import 'package:hold_my_dice/features/room/data/room_repository.dart';

/// Tells a room that this person is still there: one beat at once, then one
/// every [every]. The others read these beats to see whether a seat or the
/// room has been left alone for over 2 minutes. A beat that fails (no signal)
/// is dropped; the next one tries again.
class PresenceBeater {
  PresenceBeater(
    this._repository,
    this._code, {
    this.every = const Duration(seconds: 60),
  });

  final RoomRepository _repository;
  final String _code;
  final Duration every;
  Timer? _timer;

  /// Starts beating; does nothing if it already is.
  void start() {
    if (_timer != null) return;
    _beat();
    _timer = Timer.periodic(every, (_) => _beat());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _beat() => unawaited(_repository.heartbeat(_code).catchError((_) {}));
}
