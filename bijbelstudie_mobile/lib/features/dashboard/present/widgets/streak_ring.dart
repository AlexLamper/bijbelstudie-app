import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/notifications/notification_scheduler.dart';
import '../../../../core/notifications/retention_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../studies/data/study_models.dart';
import '../../../studies/data/study_plan_store.dart';
import '../../../studies/present/studies_providers.dart';
import '../../data/dashboard_models.dart';
import '../streak_detail_sheet.dart';
import 'home_header_actions.dart';

/// The header's streak button (`RETENTION_PLAN.md` §3.1): a pill with an
/// orange flame and the number of days in a row.
///
/// It replaces the miniature ProgressTree that used to sit here with a number in
/// its corner - that read as a profile avatar, not as a streak, and the avatar
/// is already in the tab bar. The tree itself is unchanged on Profiel and in
/// the detail sheet.
///
/// A reader measured on a week goal instead of a daily streak gets the same
/// pill with `done/target` and a check rather than a flame, since a flame
/// would say something untrue about what is being counted.
///
/// When the run is only standing because a banked freeze covers the missed
/// day(s), the flame becomes a frost snowflake - same pill, same shape, a
/// freezing colour - so the reader can see that the streak is being held rather
/// than earned today.
///
/// Tapping it opens [showStreakDetailSheet], which explains whichever of the
/// two this reader is actually looking at.
class HomeStreakIndicator extends ConsumerWidget {
  const HomeStreakIndicator({
    super.key,
    required this.serverStreak,
    required this.freezes,
    required this.weekDays,
    this.freezeHolding = false,
  });

  final int serverStreak;
  final int freezes;

  /// The run is standing on a banked freeze, not on today's reading: the pill
  /// shows a frost snowflake instead of the flame. The server decides it
  /// (`lib/streak.ts`), so both clients agree about what the mark means.
  final bool freezeHolding;

  /// The same 7-day activity strip the "Deze week" card renders, reused here
  /// so the detail sheet doesn't need a second source of truth for it.
  final List<WeekDay> weekDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cadence = _resolveCadence(ref);

    if (cadence.model == RetentionModel.weekGoal) {
      final store = ref.watch(retentionStoreProvider);
      final done = ref.read(retentionStoreProvider.notifier).completionsThisWeek;
      final _ = store; // rebuild on change
      final target = cadence.weekGoalTarget;
      return _Tappable(
        tooltip: 'Bekijk je weekdoel',
        hint: 'Open uitleg over je weekdoel en weekoverzicht',
        onTap: () => showStreakDetailSheet(
          context,
          cadence: cadence,
          streak: serverStreak,
          freezes: freezes,
          completionsThisWeek: done,
          weekDays: weekDays,
        ),
        child: StreakFlamePill(
          label: '$done/$target',
          icon: Icons.check_circle_outline,
          dormant: done <= 0,
          semanticsLabel:
              '$done van $target ${target == 1 ? 'les' : 'lessen'} deze week',
        ),
      );
    }

    ref.watch(retentionStoreProvider);
    final thisWeek = ref.read(retentionStoreProvider.notifier).completionsThisWeek;
    final days = serverStreak == 1 ? 'dag' : 'dagen';
    return _Tappable(
      tooltip: 'Bekijk je leesreeks',
      hint: 'Open uitleg over je leesreeks en weekoverzicht',
      onTap: () => showStreakDetailSheet(
        context,
        cadence: cadence,
        streak: serverStreak,
        freezes: freezes,
        freezeHolding: freezeHolding,
        completionsThisWeek: thisWeek,
        weekDays: weekDays,
      ),
      child: StreakFlamePill(
        label: '$serverStreak',
        dormant: serverStreak <= 0,
        frozen: freezeHolding,
        semanticsLabel: freezeHolding
            ? 'Reeks van $serverStreak $days, bevroren met een vriesdag'
            : (freezes > 0
                  ? 'Reeks van $serverStreak $days, met een vriesdag gespaard'
                  : 'Reeks van $serverStreak $days'),
      ),
    );
  }

  CadenceInfo _resolveCadence(WidgetRef ref) {
    final enrollments = ref.watch(studyEnrollmentsProvider).value ?? const {};
    final plans = ref.watch(studyPlansProvider);

    for (final e in enrollments.values) {
      if (e.isActive && !e.isCompleted) {
        return cadenceFrom(
          rhythm: e.rhythm,
          reminderDays: e.reminderDays,
          startedAt: e.startedAt,
        );
      }
    }
    StudyPlan? plan;
    for (final p in plans.values) {
      if (p.started) plan = p;
    }
    if (plan != null) {
      return cadenceFrom(localCadence: plan.cadence, startedAt: plan.startedAt);
    }
    return const CadenceInfo(model: RetentionModel.dailyStreak, remind: false);
  }
}

/// The ripple, tooltip and semantics that make [HomeStreakIndicator] read as
/// tappable. [child] keeps its own descriptive `Semantics` label (the streak
/// count, or the week fraction); this only adds the "button" role and a hint
/// for what tapping does, merged onto that same node.
class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.child,
    required this.onTap,
    required this.tooltip,
    required this.hint,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          hint: hint,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              onTap: onTap,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Studies helper reused by the continue card.
int firstUndoneDayFor(CuratedStudy study, Set<int> completedDays) {
  for (final lesson in study.lessons) {
    if (!completedDays.contains(lesson.day)) return lesson.day;
  }
  return study.firstLesson?.day ?? 1;
}
