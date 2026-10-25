import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/settings/app_settings.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real storage, wakelock, haptics, screen mode and browser used by the installed app. Tests
/// leave the providers at their harmless defaults.
List<Override> productionOverrides(SharedPreferences prefs) => [
  appSettingsStorageProvider.overrideWithValue(PrefsAppSettingsStorage(prefs)),
  tourStorageProvider.overrideWithValue(PrefsTourStorage(prefs)),
  bankStorageProvider.overrideWithValue(PrefsBankStorage(prefs)),
  scoreStorageProvider.overrideWithValue(PrefsScoreStorage(prefs)),
  pointStorageProvider.overrideWithValue(PrefsPointStorage(prefs)),
  screenAwakeProvider.overrideWithValue(const WakelockScreenAwake()),
  hapticsProvider.overrideWithValue(const SystemHaptics()),
  screenModeProvider.overrideWithValue(const SystemScreenMode()),
  needsManualRotationProvider.overrideWithValue(kIsWeb),
  linkOpenerProvider.overrideWithValue(const BrowserLinkOpener()),
];
