import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/page_background.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/hub/hub_nav_bar.dart';
import 'package:hold_my_dice/features/hub/saved_games.dart';
import 'package:hold_my_dice/features/hub/saved_games_tab.dart';
import 'package:hold_my_dice/features/hub/settings_tab.dart';
import 'package:hold_my_dice/features/hub/start_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _headerBody = 112.0;
const _sheetRadius = 32.0;

class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  var _tab = HubTab.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerResume());
  }

  /// Games left in a backup (the app was closed mid-game) can be resumed.
  /// Each helper with one is asked about in turn; resuming one opens it and
  /// leaves any other backup for the next launch.
  Future<void> _offerResume() async {
    final games = await loadSavedGames(ref.read);
    for (final game in games) {
      if (!mounted) return;
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          key: const ValueKey('resume-dialog'),
          title: const Text('เล่นเกมต่อไหม?'),
          content: Text(
            '${game.helperName}: มีเกมที่เล่นค้างอยู่ (${game.detail}) '
            'ยังเล่นต่อได้จากจุดเดิม',
          ),
          actions: [
            TextButton.icon(
              key: const ValueKey('resume-discard'),
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(LucideIcons.trash2),
              label: const Text('ทิ้งเกมนี้'),
            ),
            FilledButton.icon(
              key: const ValueKey('resume-continue'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(LucideIcons.play),
              label: const Text('เล่นต่อ'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (resume == true) {
        game.restore();
        context.push(game.route);
        return;
      }
      await game.clear();
    }
  }

  void _showRulesSoon() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('rules-soon'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            bottom + hubNavBarHeight + hubNavOverhang + 20,
          ),
          content: const Text('คลังกฎกำลังจะมา เร็ว ๆ นี้'),
        ),
      );
  }

  (String, String) get _titles => switch (_tab) {
    HubTab.home => ('Hold My Dice', 'เลือกตัวช่วยสำหรับวงเกมวันนี้'),
    HubTab.saved => ('เกมค้าง', 'เล่นต่อจากจุดเดิมได้เลย'),
    HubTab.settings => ('ตั้งค่า', 'ปรับแอพให้เข้ากับคุณ'),
  };

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    final navSpace = hubNavBarHeight + hubNavOverhang + 20 + inset.bottom;
    final (title, subtitle) = _titles;

    final body = switch (_tab) {
      HubTab.home => _HomeTab(bottomSpace: navSpace),
      HubTab.saved => SavedGamesTab(bottomSpace: navSpace),
      HubTab.settings => SettingsTab(bottomSpace: navSpace),
    };

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _HubHeader(
              title: title,
              subtitle: subtitle,
              height: inset.top + _headerBody + _sheetRadius,
              topInset: inset.top,
            ),
          ),
          Positioned(
            top: inset.top + _headerBody,
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              key: const ValueKey('hub-sheet'),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_sheetRadius),
              ),
              child: PageBackground(child: body),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 8 + inset.bottom,
            child: HubNavBar(
              selected: _tab,
              onSelect: (tab) => setState(() => _tab = tab),
              onStart: () => showStartSheet(context),
              onRules: _showRulesSoon,
            ),
          ),
        ],
      ),
    );
  }
}

/// The curved header of the hub: the app name over a cobalt gradient, with the
/// page sheet rolling up over its lower edge.
class _HubHeader extends StatelessWidget {
  const _HubHeader({
    required this.title,
    required this.subtitle,
    required this.height,
    required this.topInset,
  });

  final String title;
  final String subtitle;
  final double height;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final text = theme.textTheme;
    return Container(
      key: const ValueKey('hub-header'),
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Palette.auroraHeaderStart, Palette.auroraHeaderEnd]
              : const [Color(0xFF6B86FF), Color(0xFF3340D6)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, topInset + 18, 24, 0),
      alignment: Alignment.topLeft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    key: const ValueKey('hub-title'),
                    style: text.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontSize: 34,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.dices, color: Palette.cobalt),
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.bottomSpace});

  final double bottomSpace;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: EdgeInsets.fromLTRB(20, 22, 20, bottomSpace),
      crossAxisCount: 2,
      mainAxisSpacing: 18,
      crossAxisSpacing: 18,
      children: [for (final h in helpers) _HelperCard(helper: h)],
    );
  }
}

class _HelperCard extends StatelessWidget {
  const _HelperCard({required this.helper});

  final Helper helper;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return GradientCard(
      key: ValueKey('helper-${helper.id}'),
      accent: helper.color,
      onTap: () => context.push(helper.route),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: helper.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(helper.icon, size: 28, color: helper.color),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                // Scales down on narrow screens instead of overflowing.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(helper.name, style: text.titleLarge),
                      Text(
                        helper.subtitle,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
