import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/bank/application/bank_session.dart';
import 'package:hold_my_dice/features/bank/data/bank_storage.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:hold_my_dice/features/score/application/score_session.dart';
import 'package:hold_my_dice/features/score/data/score_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerResume());
  }

  /// Games left in a backup (the app was closed mid-game) can be resumed.
  /// Each helper with one is asked about in turn; resuming one opens it and
  /// leaves any other backup for the next launch.
  Future<void> _offerResume() async {
    final offers = <_ResumeOffer>[];

    if (ref.read(bankProvider) == null) {
      final storage = ref.read(bankStorageProvider);
      final saved = storage.loadGame();
      if (saved != null && saved.isOver) {
        await storage.clearGame();
      } else if (saved != null) {
        offers.add(
          _ResumeOffer(
            helper: 'Pocket Banker',
            detail: '${saved.activePlayers.length} คน',
            clear: storage.clearGame,
            open: () {
              ref.read(bankProvider.notifier).restore(saved);
              context.push('/bank/play');
            },
          ),
        );
      }
    }

    if (ref.read(scoreProvider) == null) {
      final storage = ref.read(scoreStorageProvider);
      final saved = storage.loadGame();
      if (saved != null && saved.isOver) {
        await storage.clearGame();
      } else if (saved != null) {
        offers.add(
          _ResumeOffer(
            helper: 'Score Snitch',
            detail: 'รอบ ${saved.roundNumber}/${saved.roundCount}',
            clear: storage.clearGame,
            open: () {
              ref.read(scoreProvider.notifier).restore(saved);
              context.push('/score/play');
            },
          ),
        );
      }
    }

    for (final offer in offers) {
      if (!mounted) return;
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          key: const ValueKey('resume-dialog'),
          title: const Text('เล่นเกมต่อไหม?'),
          content: Text(
            '${offer.helper}: มีเกมที่เล่นค้างอยู่ (${offer.detail}) '
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
        offer.open();
        return;
      }
      await offer.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(toolbarHeight: 72, title: const Text('Hold My Dice')),
      body: GridView.count(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        crossAxisCount: 2,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        children: [for (final h in helpers) _HelperCard(helper: h)],
      ),
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

class _ResumeOffer {
  const _ResumeOffer({
    required this.helper,
    required this.detail,
    required this.clear,
    required this.open,
  });

  final String helper;
  final String detail;
  final Future<void> Function() clear;
  final VoidCallback open;
}
