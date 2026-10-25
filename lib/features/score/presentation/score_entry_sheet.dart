import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/core/widgets/balance_chip.dart';
import 'package:hold_my_dice/core/widgets/key_tile.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/domain/score_expression.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Opens the score keypad on [playerIndex]'s cell of [round]. Confirming moves
/// on to the next player of the same round; after the last one it closes.
Future<void> showScoreEntrySheet(
  BuildContext context, {
  required int round,
  required int playerIndex,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ScoreEntrySheet(round: round, startIndex: playerIndex),
  );
}

class ScoreEntrySheet extends ConsumerStatefulWidget {
  const ScoreEntrySheet({
    super.key,
    required this.round,
    required this.startIndex,
  });

  final int round;
  final int startIndex;

  @override
  ConsumerState<ScoreEntrySheet> createState() => _ScoreEntrySheetState();
}

class _ScoreEntrySheetState extends ConsumerState<ScoreEntrySheet> {
  static const _maxLength = 40;

  late var _index = widget.startIndex;
  var _expression = '';

  void _type(String ch) {
    if (_expression.length >= _maxLength) return;
    if (_isDigit(ch)) {
      // A number has at most [maxScoreDigits] digits.
      var run = 0;
      for (var i = _expression.length - 1; i >= 0; i--) {
        if (!_isDigit(_expression[i])) break;
        run++;
      }
      if (run >= maxScoreDigits) return;
    }
    setState(() => _expression += ch);
  }

  void _backspace() {
    if (_expression.isEmpty) return;
    setState(
      () => _expression = _expression.substring(0, _expression.length - 1),
    );
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(scoreProvider);
    if (game == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);

    final player = game.players[_index];
    final accent = Color(player.color);
    final isLast = _index == game.players.length - 1;
    final value = evaluateScore(_expression);
    final shown = previewScore(_expression);
    final existing = game.scoreOf(widget.round, player.id);

    void confirm() {
      if (value == null) return;
      ref
          .read(scoreProvider.notifier)
          .setScore(round: widget.round, playerId: player.id, score: value);
      if (isLast) {
        Navigator.pop(context);
      } else {
        setState(() {
          _index++;
          _expression = '';
        });
      }
    }

    Widget key(String label, {String? id, VoidCallback? onTap, Widget? child}) {
      return KeyTile(
        inkKey: ValueKey('score-key-${id ?? label}'),
        onTap: onTap ?? () => _type(label),
        child: child ?? Text(label, style: text.headlineSmall),
      );
    }

    Widget keyRow(List<Widget> keys, {List<int>? flex}) => Expanded(
      child: Row(
        children: [
          for (final (i, k) in keys.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(flex: flex?[i] ?? 1, child: k),
          ],
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const ValueKey('score-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    player.name,
                    key: const ValueKey('score-sheet-player'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'รอบ ${widget.round + 1}',
                  key: const ValueKey('score-sheet-round'),
                  style: text.titleMedium?.copyWith(color: muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: Center(
                child: Text(
                  _expression,
                  key: const ValueKey('score-expr'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall?.copyWith(color: muted),
                ),
              ),
            ),
            Text(
              shown == null ? '0' : '$shown',
              key: const ValueKey('score-result'),
              style: text.displayMedium?.copyWith(
                color: shown == null ? muted : null,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'ยอดรวมตอนนี้ ',
                  style: text.bodySmall?.copyWith(color: muted),
                ),
                BalanceChip(
                  key: const ValueKey('score-sheet-total'),
                  amount: game.totalOf(player.id),
                  accent: accent,
                  style: text.titleMedium,
                ),
                if (existing != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    'ค่าเดิมของรอบนี้ $existing',
                    key: const ValueKey('score-sheet-existing'),
                    style: text.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 4 * 52 + 3 * 8,
              child: Column(
                children: [
                  keyRow([
                    key('7'),
                    key('8'),
                    key('9'),
                    key(
                      '',
                      id: 'back',
                      onTap: _backspace,
                      child: const Icon(LucideIcons.delete),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  keyRow([key('4'), key('5'), key('6'), key('+', id: 'plus')]),
                  const SizedBox(height: 8),
                  keyRow([
                    key('1'),
                    key('2'),
                    key('3'),
                    key(
                      '-',
                      id: 'minus',
                      child: Text('−', style: text.headlineSmall),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  keyRow(
                    [
                      key('0'),
                      key(
                        '',
                        id: 'clear',
                        onTap: () => setState(() => _expression = ''),
                        child: Text('ล้าง', style: text.titleMedium),
                      ),
                    ],
                    flex: const [3, 1],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('score-ok'),
              onPressed: value == null ? null : confirm,
              icon: const Icon(LucideIcons.check),
              label: Text(
                isLast
                    ? 'ตกลง'
                    : 'ตกลง · ต่อไป ${game.players[_index + 1].name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: text.titleLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
