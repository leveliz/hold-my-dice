import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';
import 'package:hold_my_dice/core/widgets/helper_scope.dart';
import 'package:hold_my_dice/core/widgets/section_label.dart';
import 'package:hold_my_dice/features/point/application/point_session.dart';
import 'package:hold_my_dice/features/point/data/point_storage.dart';
import 'package:hold_my_dice/features/point/domain/point_game.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Blue is the second team's colour on the board; the same shade here.
const pointBlue = Palette.cobalt;
const pointRed = Palette.rose;

class PointSetupScreen extends ConsumerStatefulWidget {
  const PointSetupScreen({super.key});

  @override
  ConsumerState<PointSetupScreen> createState() => _PointSetupScreenState();
}

class _PointSetupScreenState extends ConsumerState<PointSetupScreen> {
  final _redName = TextEditingController();
  final _blueName = TextEditingController();
  final _target = TextEditingController();
  final _cap = TextEditingController();
  var _deuce = false;

  @override
  void initState() {
    super.initState();
    // Everything comes from the last game; all still editable.
    final last = ref.read(pointStorageProvider).loadSettings();
    if (last == null) return;
    _redName.text = last.redName;
    _blueName.text = last.blueName;
    final rules = last.rules;
    if (rules.target != null) _target.text = formatMoney(rules.target!);
    _deuce = rules.deuce;
    if (rules.cap != null) _cap.text = formatMoney(rules.cap!);
  }

  @override
  void dispose() {
    _redName.dispose();
    _blueName.dispose();
    _target.dispose();
    _cap.dispose();
    super.dispose();
  }

  int? get _targetValue => parseMoney(_target.text);
  bool get _deuceOn => _deuce && _targetValue != null;
  int? get _capValue => _deuceOn ? parseMoney(_cap.text) : null;

  /// A cap has to sit above the target, or the round could never reach it.
  bool get _capTooLow =>
      _capValue != null && _targetValue != null && _capValue! <= _targetValue!;

  PointRules get _rules =>
      PointRules(target: _targetValue, deuce: _deuceOn, cap: _capValue);

  void _start() {
    final rules = _rules;
    final red = _redName.text.trim();
    final blue = _blueName.text.trim();
    final game = PointGame.start(redName: red, blueName: blue, rules: rules);
    unawaited(
      ref
          .read(pointStorageProvider)
          .saveSettings(
            PointSettings(
              redName: game.redName,
              blueName: game.blueName,
              rules: rules,
            ),
          ),
    );
    ref
        .read(pointProvider.notifier)
        .start(redName: red, blueName: blue, rules: rules);
    context.pushReplacement('/point/play');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    Widget row({required Widget label, required Widget field}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: tileDecoration(context),
      child: Row(
        children: [
          Expanded(child: label),
          SizedBox(width: 130, child: field),
        ],
      ),
    );

    Widget teamField(
      String key,
      TextEditingController c,
      String hint,
      Color dot,
    ) {
      return row(
        label: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Text('ชื่อทีม', style: text.titleMedium),
          ],
        ),
        field: TextField(
          key: ValueKey(key),
          controller: c,
          textAlign: TextAlign.end,
          maxLength: 12,
          style: text.titleLarge,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            border: InputBorder.none,
            hintStyle: text.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      );
    }

    Widget numberField(String key, String label, TextEditingController c) {
      return row(
        label: Text(label, style: text.titleMedium),
        field: TextField(
          key: ValueKey(key),
          controller: c,
          textAlign: TextAlign.end,
          keyboardType: TextInputType.number,
          inputFormatters: const [ThousandsFormatter(maxDigits: 3)],
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
                  const SectionLabel('ทีม'),
                  const SizedBox(height: 8),
                  teamField('red-name', _redName, 'แดง', pointRed),
                  const SizedBox(height: 8),
                  teamField('blue-name', _blueName, 'น้ำเงิน', pointBlue),
                  const SectionLabel('กติกา'),
                  const SizedBox(height: 8),
                  numberField('target', 'แต้มเป้าหมายต่อรอบ', _target),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(
                      'ไม่ตั้งก็ได้ แอพจะนับไปเรื่อย ๆ และให้กดจบรอบเอง',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  if (_targetValue != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: tileDecoration(context),
                      child: SwitchListTile(
                        key: const ValueKey('deuce'),
                        value: _deuce,
                        onChanged: (v) => setState(() => _deuce = v),
                        title: Text('ดิวส์', style: text.titleMedium),
                        subtitle: const Text('ต้องชนะห่าง 2 แต้ม'),
                      ),
                    ),
                  ],
                  if (_deuceOn) ...[
                    const SizedBox(height: 8),
                    numberField('cap', 'เพดานแต้ม (ไม่บังคับ)', _cap),
                    if (_capTooLow)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: Text(
                          'เพดานต้องมากกว่าแต้มเป้าหมาย',
                          key: const ValueKey('cap-error'),
                          style: text.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton.icon(
                key: const ValueKey('start-game'),
                onPressed: _capTooLow ? null : _start,
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
