import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/app.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: productionOverrides(prefs),
      child: const HoldMyDiceApp(),
    ),
  );
}
