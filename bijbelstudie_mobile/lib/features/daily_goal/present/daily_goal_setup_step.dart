import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import 'daily_goal_providers.dart';
import 'daily_goal_sheet.dart';

/// The setup wizard's daily-goal step (`setup_flow_screen.dart`): 5, 10, 15
/// or 20 minutes a day. Self-contained so the wizard only lists it.
///
/// Optional like every step there: "Volgende" without a pick keeps the
/// default of 10 minutes, unchosen, and Start then says "Kies je dagdoel".
class DailyGoalSetupStep extends ConsumerWidget {
  const DailyGoalSetupStep({super.key});

  static const _hints = {
    5: 'Rustig beginnen. Eén hoofdstuk of de tekst van de dag.',
    10: 'Een hoofdstuk en even nadenken. Voor de meeste mensen goed te doen.',
    15: 'Een hele les uit een studie.',
    20: 'Diep erin, elke dag.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(dailyGoalProvider.select((s) => s.goal));
    final hint = goal.chosen ? _hints[goal.minutes] : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Dagdoel'),
          const SizedBox(height: 16),
          Text('Hoeveel tijd wil je per dag lezen?', style: AppTheme.displayLarge),
          const SizedBox(height: 12),
          Text(
            'Een klein doel dat je echt haalt, werkt beter dan een groot doel. '
            'Haal je het, dan groeit je boom een stukje extra. Je kunt dit altijd aanpassen.',
            style: AppTheme.bodyLead,
          ),
          const SizedBox(height: 28),
          const DailyGoalChoices(source: 'setup'),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              hint ?? 'Minuten per dag',
              key: ValueKey(hint),
              style: AppTheme.bodyMuted,
            ),
          ),
        ],
      ),
    );
  }
}
