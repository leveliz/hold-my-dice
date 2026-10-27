import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hold_my_dice/app.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/core/firebase/firebase_bootstrap.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart'
    show roomRetry;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // /room/ABC234 instead of /#/room/ABC234, so a room link can be shared.
  usePathUrlStrategy();
  final prefs = await SharedPreferences.getInstance();
  // Without --dart-define=FIREBASE_ENV the app stays single-device.
  final env = firebaseEnvFromDefines();
  if (env != null) await initializeFirebase(env);
  runApp(
    ProviderScope(
      retry: roomRetry,
      overrides: productionOverrides(prefs, firebase: env != null),
      child: const HoldMyDiceApp(),
    ),
  );
}
