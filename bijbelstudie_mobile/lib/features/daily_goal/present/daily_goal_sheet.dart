import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/daily_goal.dart';
import 'daily_goal_providers.dart';
import 'daily_goal_ring.dart';

/// The goal, close up: the big ring, what counts, and the four goals to pick
/// from. Opened from the ring on Start.
Future<void> showDailyGoalSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _DailyGoalSheet(),
  );
}

class _DailyGoalSheet extends ConsumerWidget {
  const _DailyGoalSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final state = ref.watch(dailyGoalProvider);
    final p = state.progress;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DailyGoalRing(
              progress: p.progress,
              size: 120,
              stroke: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${p.minutesRead}', style: AppTheme.statNumber),
                  Text('van ${p.minutes} min', style: AppTheme.caption),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              p.reached ? 'Dagdoel gehaald' : 'Nog ${p.minutesLeft} ${p.minutesLeft == 1 ? 'minuut' : 'minuten'} vandaag',
              style: AppTheme.displaySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              p.reached
                  ? 'Je boom kreeg er 10 XP bij. Morgen weer?'
                  : 'Elke minuut in de lezer of in een les telt mee. Haal je je doel, dan krijgt je boom 10 XP extra.',
              style: AppTheme.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Je dagdoel', style: AppTheme.bodyStrong),
            ),
            const SizedBox(height: 10),
            DailyGoalChoices(source: 'start'),
            const SizedBox(height: 8),
            Text(
              'Hetzelfde doel op de website. Aanpassen kan ook bij Instellingen.',
              style: AppTheme.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The four goals as one row of chips. Used by the sheet, the setup step and
/// Instellingen; [source] says which, for `daily_goal_set`.
class DailyGoalChoices extends ConsumerWidget {
  const DailyGoalChoices({super.key, required this.source, this.onChosen});

  final String source;
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final goal = ref.watch(dailyGoalProvider.select((s) => s.goal));
    return Row(
      children: [
        for (final (i, minutes) in kDailyGoalOptions.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _GoalChip(
              minutes: minutes,
              selected: goal.chosen && goal.minutes == minutes,
              onTap: () async {
                final ok = await ref
                    .read(dailyGoalProvider.notifier)
                    .choose(minutes, source: source);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Opslaan is niet gelukt. Probeer het later opnieuw.'),
                  ));
                  return;
                }
                onChosen?.call();
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({required this.minutes, required this.selected, required this.onTap});

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$minutes minuten per dag',
      child: Material(
        color: selected ? AppTheme.teal : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: BorderSide(color: selected ? AppTheme.teal : scheme.outline),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$minutes',
                  style: AppTheme.bodyStrong.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.ink,
                  ),
                ),
                Text(
                  'min',
                  style: AppTheme.caption.copyWith(
                    color: selected ? Colors.white.withValues(alpha: 0.85) : AppTheme.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
