import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/features/hub/helpers.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The centre button of the hub: pick which helper to start.
Future<void> showStartSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const ValueKey('start-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เริ่มเกมไหน?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final h in helpers) ...[
              SizedBox(
                height: 72,
                child: GradientCard(
                  key: ValueKey('start-${h.id}'),
                  accent: h.color,
                  radius: 22,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push(h.route);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: h.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(h.icon, color: h.color),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                h.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                h.subtitle,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.chevronRight),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    ),
  );
}
