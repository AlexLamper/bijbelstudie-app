import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/dashboard_models.dart';
import 'continue_study_card.dart';

/// The detail panel behind the header streak/week-goal ring
/// (`HomeStreakIndicator`). Explains, in plain Dutch, what the ring is
/// counting, what today's actual value is, which of the last 7 days were
/// done, how a freeze/grace day works, and how the goal itself is set — a
/// daily streak or a "3x per week" week goal, depending on the reader's own
/// study cadence.
///
/// All the numbers shown here come from the caller (`HomeStreakIndicator`,
/// which already reads `retentionStoreProvider` and the dashboard's weekly
/// data) — this sheet invents no new state of its own.
Future<void> showStreakDetailSheet(
  BuildContext context, {
  required CadenceInfo cadence,
  required int streak,
  required int freezes,
  required int completionsThisWeek,
  required List<WeekDay> weekDays,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StreakDetailSheet(
      cadence: cadence,
      streak: streak,
      freezes: freezes,
      completionsThisWeek: completionsThisWeek,
      weekDays: weekDays,
    ),
  );
}

const _kWeekdayLabels = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

class _StreakDetailSheet extends ConsumerWidget {
  const _StreakDetailSheet({
    required this.cadence,
    required this.streak,
    required this.freezes,
    required this.completionsThisWeek,
    required this.weekDays,
  });

  final CadenceInfo cadence;
  final int streak;
  final int freezes;
  final int completionsThisWeek;
  final List<WeekDay> weekDays;

  bool get _isWeekGoal => cadence.model == RetentionModel.weekGoal;

  /// "Elke dag", "3x per week (ma, wo, vr)", …
  String get _cadenceLabel {
    if (!_isWeekGoal) return 'elke dag';
    if (cadence.fixedWeekdays.isEmpty) {
      return '${cadence.weekGoalTarget}x per week';
    }
    final days = cadence.fixedWeekdays.toList()..sort();
    final labels = days.map((d) => _kWeekdayLabels[d - 1]).join(', ');
    return '${cadence.weekGoalTarget}x per week ($labels)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pick = ref.watch(continueStudyProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconChip(
                  icon: _isWeekGoal ? Icons.flag_outlined : Icons.local_fire_department,
                  color: _isWeekGoal ? AppTheme.teal : AppTheme.flame,
                  size: 44,
                  iconSize: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isWeekGoal ? 'Je weekdoel' : 'Je leesreeks',
                        style: AppTheme.displayTitle.copyWith(color: scheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isWeekGoal
                            ? '$completionsThisWeek van de ${cadence.weekGoalTarget} keer deze week'
                            : (streak > 0
                                  ? '$streak ${streak == 1 ? 'dag' : 'dagen'} op rij'
                                  : 'Nog geen reeks'),
                        style: AppTheme.bodyStrong.copyWith(
                          color: AppTheme.teal,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _WeekStrip(days: weekDays),
            const SizedBox(height: 20),
            Text(
              _isWeekGoal
                  ? 'Dit doel telt hoe vaak je deze week een les afrondt of een hoofdstuk leest.'
                  : 'Deze reeks telt de dagen achter elkaar dat je een hoofdstuk leest of een studieles afrondt.',
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 10),
            Text(
              _isWeekGoal
                  ? 'Je studietempo staat op $_cadenceLabel. Rond dat aantal lessen af voor het einde van de week om je doel te halen.'
                  : 'Je studietempo staat op "$_cadenceLabel". Lees je liever een paar vaste dagen per week? Dat stel je in bij de instellingen van je studie.',
              style: AppTheme.bodyMuted,
            ),
            if (!_isWeekGoal) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.ac_unit, size: 16, color: AppTheme.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      freezes > 0
                          ? 'Je hebt $freezes bevriezingsdag${freezes == 1 ? '' : 'en'} gespaard. Mis je toch een dag, dan redt een vrije dag je reeks automatisch - als Pro-lid kun je daarna nog een bevriezingsdag inzetten.'
                          : 'Elke vijf dagen reeks verdien je een bevriezingsdag. Mis je een dag, dan blijft je reeks daarnaast nog één dag lang gespaard.',
                      style: AppTheme.caption.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Tip: lees op een vast moment van de dag - dan wordt het vanzelf een gewoonte.',
              style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
            ),
            const SizedBox(height: 20),
            SiteButton(
              label: pick != null ? 'Verder met ${pick.study.title}' : 'Bekijk bijbelstudies',
              trailingIcon: Icons.arrow_forward,
              onPressed: () {
                Navigator.of(context).pop();
                if (pick != null) {
                  context.push('/studie/${pick.study.id}/${pick.resumeDay}');
                } else {
                  context.push('/studies');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact Ma–Zo strip: a filled dot for a day with activity, an outline for
/// one without, and a teal ring around today. The same 7-day data the "Deze
/// week" card on the dashboard renders, so the two never disagree.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});

  final List<WeekDay> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final week = days.length == 7
        ? days
        : _kWeekdayLabels
              .map((l) => WeekDay(label: l, count: 0, heightPct: 0, isToday: false))
              .toList();

    return Row(
      children: [
        for (var i = 0; i < week.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: week[i].count > 0
                        ? AppTheme.teal
                        : scheme.surfaceContainerHighest,
                    border: week[i].isToday
                        ? Border.all(color: AppTheme.teal, width: 2)
                        : null,
                  ),
                  child: week[i].count > 0
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  week[i].label,
                  style: AppTheme.overline.copyWith(
                    letterSpacing: 0,
                    color: week[i].isToday ? AppTheme.teal : AppTheme.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
