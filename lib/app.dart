import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/router.dart';
import 'package:hold_my_dice/core/theme.dart';

class HoldMyDiceApp extends StatelessWidget {
  const HoldMyDiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Hold My Dice',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: router,
    );
  }
}
