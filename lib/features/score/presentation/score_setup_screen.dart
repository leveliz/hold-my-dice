import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/player_setup.dart';
import 'package:hold_my_dice/core/widgets/section_label.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:hold_my_dice/features/score/domain/score_game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ScoreSetupScreen extends ConsumerStatefulWidget {
  const ScoreSetupScreen({super.key});

  @override
  ConsumerState<ScoreSetupScreen> createState() => _ScoreSetupScreenState();
}

class _ScoreSetupScreenState extends ConsumerState<ScoreSetupScreen> {
  late final PlayerSetupController _players;
  final _rounds = TextEditingController();
  final _target = TextEditingController();
  var _winMode = WinMode.highest;

  @override
  void initState() {
    super.initState();
    // Everything comes from the last game; all still editable.
    final last = ref.read(scoreStorageProvider).loadSettings();
    _players = PlayerSetupController(initial: last?.players);
    if (last != null && last.players.length >= _players.minPlayers) {
      _rounds.text = formatMoney(last.roundCount);
      _winMode = last.winMode;
      final target = last.targetScore;
      if (target != null) _target.text = formatMoney(target);
    }
  }

  @override
  void dispose() {
    _players.dispose();
    _rounds.dispose();
    _target.dispose();
    super.dispose();
  }

  int get _roundCount => parseMoney(_rounds.text) ?? 0;
  int? get _targetScore => parseMoney(_target.text);

  bool get _canStart => _players.hasEnough && _roundCount > 0;

  void _start() {
    unawaited(
      ref
          .read(scoreStorageProvider)
          .saveSettings(
            ScoreSettings(
              players: _players.toSettings(),
              roundCount: _roundCount,
              winMode: _winMode,
              targetScore: _targetScore,
            ),
          ),
    );
    ref
        .read(scoreProvider.notifier)
        .start(
          players: _players.toPlayers(),
          roundCount: _roundCount,
          winMode: _winMode,
          targetScore: _targetScore,
        );
    context.pushReplacement('/score/play');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    Widget numberField(String key, String label, TextEditingController c) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: tileDecoration(context),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.titleMedium)),
            SizedBox(
              width: 110,
              child: TextField(
                key: ValueKey(key),
                controller: c,
                textAlign: TextAlign.end,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsFormatter(maxDigits: 6)],
                style: text.headlineSmall,
                decoration: InputDecoration(
                  hintText: 'ใส่จำนวน',
                  hintStyle: text.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: HelperAppBar(toolbarHeight: 72, title: const Text('ตั้งค่าเกม')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  PlayerSetupList(controller: _players),
                  const SectionLabel('กติกา'),
                  const SizedBox(height: 8),
                  numberField('rounds', 'จำนวนรอบ', _rounds),
                  const SizedBox(height: 8),
                  SegmentedButton<WinMode>(
                    key: const ValueKey('win-mode'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: WinMode.highest,
                        icon: Icon(LucideIcons.arrowUpWideNarrow),
                        label: Text('มากสุดชนะ'),
                      ),
                      ButtonSegment(
                        value: WinMode.lowest,
                        icon: Icon(LucideIcons.arrowDownNarrowWide),
                        label: Text('น้อยสุดชนะ'),
                      ),
                    ],
                    selected: {_winMode},
                    onSelectionChanged: (s) =>
                        setState(() => _winMode = s.first),
                  ),
                  const SizedBox(height: 8),
                  numberField('target', 'คะแนนเป้าหมาย (ไม่บังคับ)', _target),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(
                      'ถ้าตั้งเป้า ใครถึงเป้าแล้ว เล่นจนจบรอบนั้นก่อน ค่อยจบเกม',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton.icon(
                key: const ValueKey('start-game'),
                onPressed: _canStart ? _start : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: text.titleLarge,
                ),
                icon: const Icon(LucideIcons.play),
                label: const Text('เริ่มเกม'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
