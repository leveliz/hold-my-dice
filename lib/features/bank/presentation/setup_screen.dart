import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/player_setup.dart';
import 'package:hold_my_dice/core/widgets/replace_saved_game_dialog.dart';
import 'package:hold_my_dice/core/widgets/section_label.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final PlayerSetupController _players;
  final _startCash = TextEditingController();
  final _goCash = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Names, colours and money come from the last game; all still editable.
    final last = ref.read(bankStorageProvider).loadSettings();
    _players = PlayerSetupController(initial: last?.players);
    if (last != null && last.players.length >= _players.minPlayers) {
      _startCash.text = formatMoney(last.startingCash);
      _goCash.text = formatMoney(last.goAmount);
    }
  }

  @override
  void dispose() {
    _players.dispose();
    _startCash.dispose();
    _goCash.dispose();
    super.dispose();
  }

  int get _startValue => parseMoney(_startCash.text) ?? 0;
  int get _goValue => parseMoney(_goCash.text) ?? 0;

  bool get _canStart => _players.hasEnough && _startValue > 0 && _goValue > 0;

  Future<void> _start() async {
    final saved = ref.read(bankStorageProvider).loadGame();
    if (saved != null && !saved.isOver) {
      if (!await confirmReplaceSavedGame(context, 'Pocket Banker')) return;
      if (!mounted) return;
    }
    unawaited(
      ref
          .read(bankStorageProvider)
          .saveSettings(
            GameSettings(
              players: _players.toSettings(),
              startingCash: _startValue,
              goAmount: _goValue,
            ),
          ),
    );
    ref
        .read(bankProvider.notifier)
        .start(
          players: _players.toPlayers(),
          startingCash: _startValue,
          goAmount: _goValue,
        );
    context.pushReplacement('/bank/play');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    Widget moneyField(String key, String label, TextEditingController c) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: tileDecoration(context),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.titleMedium)),
            SizedBox(
              width: 130,
              child: TextField(
                key: ValueKey(key),
                controller: c,
                textAlign: TextAlign.end,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsFormatter()],
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
                  const SectionLabel('เงิน'),
                  const SizedBox(height: 8),
                  moneyField('start-cash', 'เงินเริ่มต้นของทุกคน', _startCash),
                  const SizedBox(height: 8),
                  moneyField('go-cash', 'เงินผ่านจุดเริ่ม', _goCash),
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
