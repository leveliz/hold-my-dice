import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/features/bank/presentation/game_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/history_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/setup_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/shortfall_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/summary_screen.dart';
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
    GoRoute(
      path: '/bank/play/shortfall',
      builder: (context, state) =>
          ShortfallScreen(args: state.extra! as ShortfallArgs),
    ),
    GoRoute(
      path: '/bank/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/bank/summary',
      builder: (context, state) => const SummaryScreen(),
    ),
  ],
);

final router = createRouter();
