import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/thousands_formatter.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';
import 'package:hold_my_dice/features/bank/presentation/player_colors.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class _Draft {
  _Draft(this.id, String name, this.color)
    : name = TextEditingController(text: name);

  final String id;
  final TextEditingController name;
  Color color;
}

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  static const _minPlayers = 2;

  final _drafts = <_Draft>[];
  final _startCash = TextEditingController();
  final _goCash = TextEditingController();
  var _nextId = 1;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _minPlayers; i++) {
      _addPlayer();
    }
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.name.dispose();
    }
    _startCash.dispose();
    _goCash.dispose();
    super.dispose();
  }

  Set<int> get _usedColors => {for (final d in _drafts) d.color.toARGB32()};

  String _defaultName() {
    final taken = {for (final d in _drafts) d.name.text.trim()};
    var n = 1;
    while (taken.contains('ผู้เล่น $n')) {
      n++;
    }
    return 'ผู้เล่น $n';
  }

  void _addPlayer() {
    _drafts.add(
      _Draft('p${_nextId++}', _defaultName(), randomPlayerColor(_usedColors)),
    );
  }

  int get _startValue => parseMoney(_startCash.text) ?? 0;
  int get _goValue => parseMoney(_goCash.text) ?? 0;

  bool get _canStart =>
      _drafts.length >= _minPlayers && _startValue > 0 && _goValue > 0;

  Future<void> _pickColor(_Draft d) async {
    final taken = {
      for (final o in _drafts)
        if (o != d) o.color.toARGB32(),
    };
    final picked = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final c in playerPalette)
              if (!taken.contains(c.toARGB32()))
                GestureDetector(
                  key: ValueKey('swatch-${c.toARGB32()}'),
                  onTap: () => Navigator.pop(context, c),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: c == d.color
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => d.color = picked);
  }

  void _start() {
    final players = [
      for (final (i, d) in _drafts.indexed)
        Player(
          id: d.id,
          name: d.name.text.trim().isEmpty
              ? 'ผู้เล่น ${i + 1}'
              : d.name.text.trim(),
          color: d.color.toARGB32(),
        ),
    ];
    ref
        .read(bankProvider.notifier)
        .start(players: players, startingCash: _startValue, goAmount: _goValue);
    context.pushReplacement('/bank/play');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final dark = theme.brightness == Brightness.dark;
    final tile = dark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.07),
            theme.colorScheme.surface,
          )
        : Colors.white;

    Widget row({required List<Widget> children}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tile,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: children),
    );

    Widget section(String label) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2, left: 4),
      child: Text(
        label,
        style: text.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
        ),
      ),
    );

    Widget moneyField(String key, String label, TextEditingController c) {
      return row(
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
              decoration: const InputDecoration(
                hintText: 'ใส่จำนวน',
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const Text('ตั้งค่าเกม')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  section('ผู้เล่น (อย่างน้อย $_minPlayers คน)'),
                  for (final d in _drafts) ...[
                    const SizedBox(height: 8),
                    row(
                      children: [
                        GestureDetector(
                          key: ValueKey('color-${d.id}'),
                          onTap: () => _pickColor(d),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: d.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: ValueKey('name-${d.id}'),
                            controller: d.name,
                            style: text.titleMedium,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_drafts.length > _minPlayers)
                          IconButton(
                            key: ValueKey('remove-${d.id}'),
                            tooltip: 'ลบผู้เล่น',
                            icon: const Icon(LucideIcons.x),
                            onPressed: () => setState(() {
                              d.name.dispose();
                              _drafts.remove(d);
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  _AddPlayerButton(
                    key: const ValueKey('add-player'),
                    onTap: () => setState(_addPlayer),
                  ),
                  section('เงิน'),
                  const SizedBox(height: 8),
                  moneyField('start-cash', 'เงินเริ่มต้นของทุกคน', _startCash),
                  const SizedBox(height: 8),
                  moneyField('go-cash', 'เงินผ่านจุดเริ่ม', _goCash),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton(
                key: const ValueKey('start-game'),
                onPressed: _canStart ? _start : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  textStyle: text.titleLarge,
                ),
                child: const Text('เริ่มเกม'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed, rounded "add" slot at the end of the player list.
class _AddPlayerButton extends StatelessWidget {
  const _AddPlayerButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: onSurface.withValues(alpha: 0.3),
        radius: 18,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              '+ เพิ่มผู้เล่น',
              style: theme.textTheme.titleMedium?.copyWith(
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 7.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(radius),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
