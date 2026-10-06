import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../progress_tree/present/progress_tree_providers.dart';
import '../../studies/present/studies_providers.dart';
import '../data/dashboard_models.dart';

/// The detail panel behind the header streak/week-goal ring
/// (`HomeStreakIndicator`). Says, in plain Dutch and as briefly as it can,
/// what today's value is, which of the last 7 days were done, and what keeps
/// the thing running - a daily streak or a "3x per week" week goal, depending
/// on the reader's own study cadence. It is deliberately short: readers scan
/// this sheet, they do not read it.
///
/// All the numbers shown here come from the caller (`HomeStreakIndicator`,
/// which already reads `retentionStoreProvider` and the dashboard's weekly
/// data). The sheet reads `treeStateProvider` on its own only for the motion
/// pref and "beste reeks", which live on that state.
Future<void> showStreakDetailSheet(
  BuildContext context, {
  required CadenceInfo cadence,
  required int streak,
  required int freezes,
  required int completionsThisWeek,
  required List<WeekDay> weekDays,
  bool freezeHolding = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StreakDetailSheet(
      cadence: cadence,
      streak: streak,
      freezes: freezes,
      freezeHolding: freezeHolding,
      completionsThisWeek: completionsThisWeek,
      weekDays: weekDays,
    ),
  );
}

const _kWeekdayLabels = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];

/// The header mark is 48; the sheet shows the same icon, plain, at this size.
const double _kMarkSize = 40;

String _dayWord(int n) => n == 1 ? 'dag' : 'dagen';
String _lessonWord(int n) => n == 1 ? 'les' : 'lessen';

class _StreakDetailSheet extends ConsumerWidget {
  const _StreakDetailSheet({
    required this.cadence,
    required this.streak,
    required this.freezes,
    required this.freezeHolding,
    required this.completionsThisWeek,
    required this.weekDays,
  });

  final CadenceInfo cadence;
  final int streak;
  final int freezes;

  /// The run is standing on a freeze, not on today's reading - see
  /// `HomeStreakIndicator`. The mark and the explainer both change for it.
  final bool freezeHolding;
  final int completionsThisWeek;
  final List<WeekDay> weekDays;

  bool get _isWeekGoal => cadence.model == RetentionModel.weekGoal;

  /// Whether there is anything to show yet: a running streak, or at least
  /// one completion this week. Otherwise the icon stays muted.
  bool get _lit => _isWeekGoal ? completionsThisWeek > 0 : streak > 0;

  /// The same swap the header pill makes: snowflake for flame while a freeze is
  /// holding the run up.
  bool get _frozen => !_isWeekGoal && freezeHolding && streak > 0;

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

  /// The count under the title. Singular and plural are both real cases here:
  /// a streak of 1 is the most common streak there is.
  String get _countLine {
    if (_isWeekGoal) {
      return '$completionsThisWeek van de ${cadence.weekGoalTarget} keer deze week';
    }
    return streak > 0 ? '$streak ${_dayWord(streak)} op rij' : 'Nog geen reeks';
  }

  /// The very mark the reader just tapped in the header, drawn plain: the
  /// flame of `StreakFlamePill`, or its check for a week goal. It used to be
  /// the reader's own progress tree, but the tree reads as a profile avatar
  /// rather than as the thing being explained - the header stopped using it
  /// for that reason, and this sheet now follows.
  Widget _mark() {
    final target = cadence.weekGoalTarget;
    return Semantics(
      label: _isWeekGoal
          ? '$completionsThisWeek van $target ${_lessonWord(target)} deze week'
          : (freezeHolding
                ? 'Reeks van $streak ${_dayWord(streak)}, bevroren met een vriesdag'
                : 'Reeks van $streak ${_dayWord(streak)}'),
      child: Icon(
        _isWeekGoal
            ? Icons.check_circle_outline
            : (_frozen ? Icons.ac_unit : Icons.local_fire_department),
        color: _lit
            ? (_isWeekGoal
                  ? AppTheme.teal
                  : (_frozen ? AppTheme.frost : AppTheme.flame))
            : AppTheme.inkMuted,
        size: _kMarkSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pick = ref.watch(continueStudyProvider);
    final tree = ref.watch(treeStateProvider).value;

    // Same rule as the lesson card and the celebration: the account's own
    // motion pref, or the OS one, and nothing moves.
    final still =
        (tree?.reducedMotion ?? false) ||
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    final best = tree?.longestStreak ?? 0;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _mark(),
                const SizedBox(width: 14),
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
                        _countLine,
                        style: AppTheme.bodyStrong.copyWith(
                          color: AppTheme.teal,
                          fontSize: 13,
                        ),
                      ),
                      if (!_isWeekGoal && best > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          streak >= best
                              ? 'Je beste reeks tot nu toe'
                              : 'Beste reeks: $best ${_dayWord(best)}',
                          style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _WeekStrip(days: weekDays, still: still),
            const SizedBox(height: 20),
            Text(
              _isWeekGoal
                  ? 'Je doel: $_cadenceLabel een hoofdstuk lezen of een les afronden.'
                  : 'Elke dag een hoofdstuk lezen of een les afronden houdt je reeks lopend.',
              style: AppTheme.bodyMuted,
            ),
            if (!_isWeekGoal && (freezes > 0 || freezeHolding)) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.ac_unit, size: 16, color: AppTheme.frost),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      freezeHolding
                          ? 'Een vriesdag houdt je reeks heel voor de dag die je oversloeg. Lees je vandaag, dan loopt hij gewoon door.'
                          : 'Je hebt $freezes vriesdag${freezes == 1 ? '' : 'en'} gespaard: mis je een dag, dan blijft je reeks staan. Je krijgt er een bij elke zevende dag op rij.',
                      style: AppTheme.caption.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ],
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

/// A compact Ma-Zo strip: a filled dot for a day with activity, an outline for
/// one without, and a teal ring around today. The same 7-day data the "Deze
/// week" card on the dashboard renders, so the two never disagree.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.still});

  final List<WeekDay> days;
  final bool still;

  @override
  Widget build(BuildContext context) {
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
                _WeekDot(day: week[i], order: i, still: still),
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

/// One day of the strip. Done days pop in left to right when the sheet opens,
/// so the week reads as being counted up rather than as a static chart. Each
/// dot is its own finite tween on a shared timeline (an [Interval] per
/// position), and days without activity - and every day under reduced
/// motion - are simply drawn.
class _WeekDot extends StatelessWidget {
  const _WeekDot({required this.day, required this.order, required this.still});

  final WeekDay day;
  final int order;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = day.count > 0;

    final dot = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppTheme.teal : scheme.surfaceContainerHighest,
        border: day.isToday ? Border.all(color: AppTheme.teal, width: 2) : null,
      ),
      child: done ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    );

    if (still || !done) return dot;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Interval(0.11 * order, 1, curve: Curves.easeOutBack),
      builder: (context, t, child) => Transform.scale(
        scale: 0.6 + 0.4 * t,
        // easeOutBack overshoots 1 for a moment; opacity must not.
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: dot,
    );
  }
}
