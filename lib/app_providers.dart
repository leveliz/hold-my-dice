import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real storage, wakelock and haptics used by the installed app. Tests
/// leave the providers at their harmless defaults.
List<Override> productionOverrides(SharedPreferences prefs) => [
  bankStorageProvider.overrideWithValue(PrefsBankStorage(prefs)),
  scoreStorageProvider.overrideWithValue(PrefsScoreStorage(prefs)),
  screenAwakeProvider.overrideWithValue(const WakelockScreenAwake()),
  hapticsProvider.overrideWithValue(const SystemHaptics()),
];
