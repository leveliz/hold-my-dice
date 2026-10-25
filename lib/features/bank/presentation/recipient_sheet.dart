import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/core/widgets/gradient_card.dart';
import 'package:hold_my_dice/core/widgets/player_avatar.dart';
import 'package:hold_my_dice/features/bank/domain/player.dart';

class RecipientOption {
  const RecipientOption(this.player, this.balance);

  final Player player;

  /// Null when balances are hidden.
  final int? balance;
}

/// Lets the payer pick who to transfer to. Returns the chosen player, or
/// null if dismissed.
Future<Player?> showRecipientSheet(
  BuildContext context, {
  required Player from,
  required List<RecipientOption> options,
}) {
  return showModalBottomSheet<Player>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RecipientSheet(from: from, options: options),
  );
}

class _RecipientSheet extends StatelessWidget {
  const _RecipientSheet({required this.from, required this.options});

  final Player from;
  final List<RecipientOption> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const ValueKey('recipient-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('โอนจาก ${from.name}', style: text.titleLarge),
            Text(
              'โอนให้ใคร?',
              style: text.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final o = options[i];
                  final accent = Color(o.player.color);
                  return SizedBox(
                    height: 64,
                    child: GradientCard(
                      key: ValueKey('recipient-${o.player.id}'),
                      accent: accent,
                      radius: 20,
                      onTap: () => Navigator.pop(context, o.player),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            PlayerAvatar(
                              name: o.player.name,
                              color: accent,
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                o.player.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium,
                              ),
                            ),
                            Text(
                              o.balance == null
                                  ? '••••'
                                  : formatMoney(o.balance!),
                              style: text.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
