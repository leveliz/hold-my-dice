import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/features/bank/bank_screen.dart';
import 'package:hold_my_dice/features/hub/hub_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HubScreen()),
    GoRoute(path: '/bank', builder: (context, state) => const BankScreen()),
  ],
);
