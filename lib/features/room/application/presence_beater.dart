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
    this.onNotAMember,
  });

  final RoomRepository _repository;
  final String _code;
  final Duration every;

  /// Called when a beat is refused because this person is no longer a member,
  /// for instance because somebody took their seat over.
  final void Function()? onNotAMember;
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

  /// Sends a beat now, for instance when the app comes back to the screen; the
  /// regular schedule goes on as it was.
  void beatNow() => _beat();

  void _beat() => unawaited(
    _repository.heartbeat(_code).catchError((Object error) {
      if (error is RoomException && error.error == RoomError.notAMember) {
        onNotAMember?.call();
      }
    }),
  );
}
