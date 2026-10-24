import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';

class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

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
            const Spacer(),
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
    );
  }
}
