import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/features/bank/presentation/game_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/setup_screen.dart';
import 'package:hold_my_dice/features/hub/hub_screen.dart';

GoRouter createRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HubScreen()),
    GoRoute(path: '/bank', builder: (context, state) => const SetupScreen()),
    GoRoute(
      path: '/bank/play',
      builder: (context, state) => const GameScreen(),
    ),
  ],
);

final router = createRouter();
