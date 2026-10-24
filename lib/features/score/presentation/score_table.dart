import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';

const _roundColumnWidth = 44.0;
const _minPlayerColumnWidth = 76.0;
const _rowHeight = 40.0;
const _rowGap = 6.0;
const _headerHeight = 48.0;
const _totalsHeight = 54.0;

/// The scoreboard: one row per round, one column per player. The round
/// numbers stay on the left and the totals stay at the bottom while the rows
/// scroll; with many players the columns scroll sideways.
class ScoreTable extends StatefulWidget {
  const ScoreTable({super.key, required this.game, this.onCellTap});

  final ScoreGame game;

  /// Called with (round, player index) when a score cell is tapped. Null makes
  /// the table read-only.
  final void Function(int round, int playerIndex)? onCellTap;

  @override
  State<ScoreTable> createState() => _ScoreTableState();
}

class _ScoreTableState extends State<ScoreTable> {
  final _leftRows = ScrollController();
  final _rightRows = ScrollController();
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _leftRows.addListener(() => _follow(_leftRows, _rightRows));
    _rightRows.addListener(() => _follow(_rightRows, _leftRows));
  }

  /// Keeps the round column and the score rows scrolled to the same place.
  void _follow(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    _syncing = true;
    final max = to.position.maxScrollExtent;
    to.jumpTo(from.offset.clamp(0.0, max));
    _syncing = false;
  }

  @override
  void didUpdateWidget(ScoreTable old) {
    super.didUpdateWidget(old);
    if (widget.game.roundsOnBoard > old.game.roundsOnBoard) {
      // A new round started: bring it into view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_rightRows.hasClients) return;
        // The end of the list, from the row heights rather than the reported
        // extent, which may still be the old one in this frame.
        final position = _rightRows.position;
        final end =
            widget.game.roundsOnBoard * (_rowHeight + _rowGap) -
            position.viewportDimension;
        _rightRows.animateTo(
          end < 0 ? 0 : end,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _leftRows.dispose();
    _rightRows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final surface = theme.colorScheme.surface;
    final navy = dark ? const Color(0xFF2B3181) : const Color(0xFF232A7C);
    final leaders = {for (final p in game.leaders) p.id};

    Color tint(Color accent, double alpha) =>
        Color.alphaBlend(accent.withValues(alpha: alpha), surface);

    return LayoutBuilder(
      builder: (context, constraints) {
        final players = game.players;
        final available = constraints.maxWidth - _roundColumnWidth;
        final columnWidth = (available / players.length).clamp(
          _minPlayerColumnWidth,
          double.infinity,
        );

        Widget header(int i) {
          final p = players[i];
          final accent = Color(p.color);
          return SizedBox(
            width: columnWidth,
            child: Container(
              key: ValueKey('score-header-${p.id}'),
              margin: const EdgeInsets.fromLTRB(3, 0, 3, _rowGap),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: tint(accent, dark ? 0.45 : 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
            ),
          );
        }

        Widget cell(int round, int i) {
          final p = players[i];
          final accent = Color(p.color);
          final score = game.scoreOf(round, p.id);
          final isCurrent = round == game.currentRound && !game.isOver;
          final tappable = widget.onCellTap != null;
          final Widget body;
          if (score == null) {
            body = DashedBorder(
              color: muted,
              radius: 12,
              strokeWidth: 1.5,
              child: Center(
                child: Text(
                  '–',
                  key: ValueKey('score-empty-$round-${p.id}'),
                  style: text.titleMedium?.copyWith(color: muted),
                ),
              ),
            );
          } else {
            body = Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint(accent, dark ? 0.2 : 0.1),
                    tint(accent, dark ? 0.42 : 0.34),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: isCurrent
                    ? Border.all(
                        color: dark
                            ? accent
                            : Color.lerp(accent, Colors.black, 0.35)!,
                        width: 2,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$score',
                key: ValueKey('score-value-$round-${p.id}'),
                style: text.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          }
          return SizedBox(
            width: columnWidth,
            height: _rowHeight + _rowGap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(3, 0, 3, _rowGap),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  body,
                  if (tappable)
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        key: ValueKey('score-cell-$round-${p.id}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => widget.onCellTap!(round, i),
                      ),
                    )
                  else
                    SizedBox.shrink(key: ValueKey('score-cell-$round-${p.id}')),
                ],
              ),
            ),
          );
        }

        Widget roundLabel(int round) {
          final current = round == game.currentRound && !game.isOver;
          return SizedBox(
            height: _rowHeight + _rowGap,
            child: Padding(
              padding: const EdgeInsets.only(bottom: _rowGap),
              child: Center(
                child: Text(
                  '${round + 1}',
                  key: ValueKey('score-round-$round'),
                  style: text.titleMedium?.copyWith(
                    color: current ? theme.colorScheme.onSurface : muted,
                  ),
                ),
              ),
            ),
          );
        }

        Widget total(int i) {
          final p = players[i];
          final lead = leaders.contains(p.id);
          return SizedBox(
            width: columnWidth,
            child: Center(
              child: Container(
                key: ValueKey('score-total-${p.id}'),
                constraints: BoxConstraints(minWidth: columnWidth - 16),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: lead ? Colors.white.withValues(alpha: 0.22) : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${game.totalOf(p.id)}',
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          );
        }

        final rows = game.roundsOnBoard;
        final contentWidth = columnWidth * players.length;

        return Row(
          children: [
            SizedBox(
              width: _roundColumnWidth,
              child: Column(
                children: [
                  SizedBox(
                    height: _headerHeight,
                    child: Center(
                      child: Text(
                        'รอบ',
                        style: text.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _leftRows,
                      itemExtent: _rowHeight + _rowGap,
                      itemCount: rows,
                      itemBuilder: (context, round) => roundLabel(round),
                    ),
                  ),
                  Container(
                    height: _totalsHeight,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: navy,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(18),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'รวม',
                      style: text.bodyMedium?.copyWith(
                        color: const Color(0xFFC9CFFC),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('score-columns-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: _headerHeight,
                        child: Row(
                          children: [
                            for (var i = 0; i < players.length; i++) header(i),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _rightRows,
                          itemExtent: _rowHeight + _rowGap,
                          itemCount: rows,
                          itemBuilder: (context, round) => Row(
                            children: [
                              for (var i = 0; i < players.length; i++)
                                cell(round, i),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        height: _totalsHeight,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: navy,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(18),
                          ),
                        ),
                        child: Row(
                          children: [
                            for (var i = 0; i < players.length; i++) total(i),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
