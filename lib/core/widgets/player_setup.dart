import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/players/player_colors.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';
import 'package:hold_my_dice/core/widgets/section_label.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One row of the player list while it is being edited.
class PlayerDraft {
  PlayerDraft(this.id, String name, this.color)
    : name = TextEditingController(text: name);

  final String id;
  final TextEditingController name;
  Color color;
}

/// The players being set up for a game: default names, unique random colours,
/// at least [minPlayers]. Shared by every helper that has a player list.
class PlayerSetupController extends ChangeNotifier {
  PlayerSetupController({List<PlayerSetting>? initial, this.minPlayers = 2}) {
    if (initial != null && initial.length >= minPlayers) {
      // Names and colours come from the last game; all still editable.
      for (final p in initial) {
        _drafts.add(PlayerDraft(_newId(), p.name, Color(p.color)));
      }
    } else {
      for (var i = 0; i < minPlayers; i++) {
        _addDraft();
      }
    }
  }

  final int minPlayers;
  final _drafts = <PlayerDraft>[];
  var _nextId = 1;

  List<PlayerDraft> get drafts => List.unmodifiable(_drafts);
  bool get hasEnough => _drafts.length >= minPlayers;
  bool get canRemove => _drafts.length > minPlayers;

  String _newId() => 'p${_nextId++}';

  Set<int> get _usedColors => {for (final d in _drafts) d.color.toARGB32()};

  String _defaultName() {
    final taken = {for (final d in _drafts) d.name.text.trim()};
    var n = 1;
    while (taken.contains('ผู้เล่น $n')) {
      n++;
    }
    return 'ผู้เล่น $n';
  }

  void _addDraft() {
    _drafts.add(
      PlayerDraft(_newId(), _defaultName(), randomPlayerColor(_usedColors)),
    );
  }

  void add() {
    _addDraft();
    notifyListeners();
  }

  void remove(PlayerDraft draft) {
    draft.name.dispose();
    _drafts.remove(draft);
    notifyListeners();
  }

  void setColor(PlayerDraft draft, Color color) {
    draft.color = color;
    notifyListeners();
  }

  Set<int> colorsTakenByOthers(PlayerDraft draft) => {
    for (final d in _drafts)
      if (d != draft) d.color.toARGB32(),
  };

  /// The players as they will play: a blank name falls back to its default.
  List<Player> toPlayers() => [
    for (final (i, d) in _drafts.indexed)
      Player(
        id: d.id,
        name: d.name.text.trim().isEmpty
            ? 'ผู้เล่น ${i + 1}'
            : d.name.text.trim(),
        color: d.color.toARGB32(),
      ),
  ];

  List<PlayerSetting> toSettings() => [
    for (final p in toPlayers()) PlayerSetting(name: p.name, color: p.color),
  ];

  @override
  void dispose() {
    for (final d in _drafts) {
      d.name.dispose();
    }
    super.dispose();
  }
}

/// The editable player list: colour dot (tap to change), name, remove, and a
/// dashed "add player" slot.
class PlayerSetupList extends StatelessWidget {
  const PlayerSetupList({super.key, required this.controller});

  final PlayerSetupController controller;

  Future<void> _pickColor(BuildContext context, PlayerDraft d) async {
    final taken = controller.colorsTakenByOthers(d);
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
    if (picked != null) controller.setColor(d, picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('ผู้เล่น (อย่างน้อย ${controller.minPlayers} คน)'),
          for (final d in controller.drafts) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: tileDecoration(context),
              child: Row(
                children: [
                  GestureDetector(
                    key: ValueKey('color-${d.id}'),
                    onTap: () => _pickColor(context, d),
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
                  if (controller.canRemove)
                    IconButton(
                      key: ValueKey('remove-${d.id}'),
                      tooltip: 'ลบผู้เล่น',
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => controller.remove(d),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          _AddPlayerButton(
            key: const ValueKey('add-player'),
            onTap: controller.add,
          ),
        ],
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
    final paper = PaperStyle.maybeOf(context) != null;
    final radius = paper ? PaperStyle.radius : 18.0;
    return DashedBorder(
      color: paper ? PaperStyle.kraft : onSurface.withValues(alpha: 0.3),
      radius: radius,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
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
