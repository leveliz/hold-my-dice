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
import 'package:hold_my_dice/features/point/presentation/point_board_screen.dart';
import 'package:hold_my_dice/features/point/presentation/point_setup_screen.dart';
import 'package:hold_my_dice/features/point/presentation/point_summary_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_board_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_setup_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_summary_screen.dart';
import 'package:hold_my_dice/features/score/presentation/score_table_screen.dart';

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
    _route('/', (_) => const HubScreen()),
    _route('/bank', (_) => const SetupScreen(), helper: 'bank'),
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
    _route('/point', (_) => const PointSetupScreen(), helper: 'point'),
    _route('/point/play', (_) => const PointBoardScreen(), helper: 'point'),
    _route(
      '/point/summary',
      (_) => const PointSummaryScreen(),
      helper: 'point',
    ),
  ],
);

final router = createRouter();
