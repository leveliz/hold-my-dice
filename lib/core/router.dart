import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/page_background.dart';
import 'package:hold_my_dice/features/bank/presentation/game_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/history_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/setup_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/shortfall_screen.dart';
import 'package:hold_my_dice/features/bank/presentation/summary_screen.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/hub/hub_screen.dart';
import 'package:hold_my_dice/features/hub/settings_screen.dart';
import 'package:hold_my_dice/features/point/presentation/point_board_screen.dart';
import 'package:hold_my_dice/features/point/presentation/point_setup_screen.dart';
import 'package:hold_my_dice/features/point/presentation/point_summary_screen.dart';
import 'package:hold_my_dice/features/room/application/room_code.dart';
import 'package:hold_my_dice/features/room/presentation/create_room_screen.dart';
import 'package:hold_my_dice/features/room/presentation/enter_code_screen.dart';
import 'package:hold_my_dice/features/room/presentation/mode_picker_screen.dart';
import 'package:hold_my_dice/features/room/presentation/room_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_board_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_setup_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_summary_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_table_screen.dart';
import 'package:hold_my_dice/features/splash/splash_screen.dart';

/// A route whose page paints the sky gradient itself; [helper] gives its
/// header that helper's colour.
GoRoute _route(
  String path,
  Widget Function(GoRouterState state) build, {
  String? helper,
}) => GoRoute(
  path: path,
  pageBuilder: (context, state) {
    Widget page = build(state);
    if (helper != null) {
      final h = helperById(helper);
      page = HelperScope(color: h.color, paperColor: h.paperColor, child: page);
    }
    return MaterialPage<void>(
      key: state.pageKey,
      child: PageBackground(child: page),
    );
  },
);

GoRouter createRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    _route('/splash', (_) => const SplashScreen()),
    _route('/', (_) => const HubScreen()),
    _route('/settings', (_) => const SettingsScreen()),
    _route('/bank', (_) => const BankEntryScreen(), helper: 'bank'),
    _route('/bank/solo', (_) => const SetupScreen(), helper: 'bank'),
    _route('/bank/play', (_) => const GameScreen(), helper: 'bank'),
    _route(
      '/bank/play/shortfall',
      (state) => ShortfallScreen(args: state.extra! as ShortfallArgs),
      helper: 'bank',
    ),
    _route('/bank/history', (_) => const HistoryScreen(), helper: 'bank'),
    _route('/bank/summary', (_) => const SummaryScreen(), helper: 'bank'),
    _route('/score', (_) => const ScoreSetupScreen(), helper: 'score'),
    _route('/score/play', (_) => const ScoreBoardScreen(), helper: 'score'),
    _route(
      '/score/summary',
      (_) => const ScoreSummaryScreen(),
      helper: 'score',
    ),
    _route('/score/table', (_) => const ScoreTableScreen(), helper: 'score'),
    _route('/room/create', (_) => const CreateRoomScreen(), helper: 'bank'),
    _route('/room/join', (_) => const EnterCodeScreen(), helper: 'bank'),
    _route(
      '/room/:code',
      (state) =>
          RoomScreen(code: normalizeRoomCode(state.pathParameters['code']!)),
      helper: 'bank',
    ),
    _route('/point', (_) => const PointSetupScreen(), helper: 'point'),
    _route('/point/play', (_) => const PointBoardScreen(), helper: 'point'),
    _route(
      '/point/summary',
      (_) => const PointSummaryScreen(),
      helper: 'point',
    ),
  ],
);

/// The app opens on the splash, which hands over to the hub.
final router = createRouter(initialLocation: '/splash');
