import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/settings/app_settings.dart';
import 'package:hold_my_dice/core/theme.dart';

class HoldMyDiceApp extends ConsumerWidget {
  const HoldMyDiceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Hold My Dice',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
    );
  }
}
