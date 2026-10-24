import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while a game is being played.
abstract class ScreenAwake {
  void enable();
  void disable();
}

class NoScreenAwake implements ScreenAwake {
  const NoScreenAwake();

  @override
  void enable() {}

  @override
  void disable() {}
}

class WakelockScreenAwake implements ScreenAwake {
  const WakelockScreenAwake();

  @override
  void enable() => _ignoreFailure(WakelockPlus.enable());

  @override
  void disable() => _ignoreFailure(WakelockPlus.disable());

  // A device that cannot hold a wakelock should not break the game.
  void _ignoreFailure(Future<void> call) {
    call.catchError((Object _) {});
  }
}

/// A light tap felt when a transaction goes through.
abstract class Haptics {
  void transaction();
}

class NoHaptics implements Haptics {
  const NoHaptics();

  @override
  void transaction() {}
}

class SystemHaptics implements Haptics {
  const SystemHaptics();

  @override
  void transaction() {
    HapticFeedback.lightImpact();
  }
}

/// Both default to doing nothing so tests never touch platform channels;
/// `main()` swaps in the real ones (see `productionOverrides`).
final screenAwakeProvider = Provider<ScreenAwake>(
  (ref) => const NoScreenAwake(),
);
final hapticsProvider = Provider<Haptics>((ref) => const NoHaptics());
