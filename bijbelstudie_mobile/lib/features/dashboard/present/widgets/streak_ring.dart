import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/notifications/notification_scheduler.dart';
import '../../../../core/notifications/retention_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../levensboom/domain/tree_state.dart';
import '../../../levensboom/present/levensboom_providers.dart';
import '../../../levensboom/present/mini_tree.dart';
import '../../../studies/data/study_models.dart';
import '../../../studies/data/study_plan_store.dart';
import '../../../studies/present/studies_providers.dart';
import '../../data/dashboard_models.dart';
import '../streak_detail_sheet.dart';

/// The header re-entry indicator (`RETENTION_PLAN.md` §3.1): a miniature
/// Levensboom that grows with whatever the reader is being measured on, with
/// the number tucked into a corner badge. Daily-streak readers grow it with the
/// streak; week-goal readers grow it with this week's `done / target`. Both are
/// visibly the same tree family, and the same tree as the one on Profiel — the
/// seed is the account's. A `free`-rhythm reader, or one with no data yet, sees
/// nothing here (the old bare "N dagen" pill is gone).
///
/// Tapping it opens [showStreakDetailSheet], which explains whichever of the
/// two this reader is actually looking at — a tree alone doesn't say what it
/// means.
class HomeStreakIndicator extends ConsumerWidget {
  const HomeStreakIndicator({
    super.key,
    required this.serverStreak,
    required this.freezes,
    required this.weekDays,
  });

  final int serverStreak;
  final int freezes;

  /// The same 7-day activity strip the "Deze week" card renders, reused here
  /// so the detail sheet doesn't need a second source of truth for it.
  final List<WeekDay> weekDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cadence = _resolveCadence(ref);

    // Seed, wilt and the motion pref all come from the account's own tree
    // state, so the header tree is literally the reader's tree and not a
    // lookalike. `health` is the server's (`/api/v1/gamification`,
    // TREE_FEATURE_PLAN §5.4) rather than anything re-derived from `weekDays`:
    // the server knows `lastStreakDate` and already absorbs Pro freezes into
    // it. Before the first fetch lands there is no tree state yet, so the
    // header falls back to a healthy tree on a constant seed rather than
    // flashing a wilted one.
    final tree = ref.watch(treeStateProvider).value;

    if (cadence.model == RetentionModel.weekGoal) {
      final store = ref.watch(retentionStoreProvider);
      final done = ref.read(retentionStoreProvider.notifier).completionsThisWeek;
      final _ = store; // rebuild on change
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
        child: WeeklyGoalRing(
          done: done,
          target: cadence.weekGoalTarget,
          tree: tree,
        ),
      );
    }

    if (serverStreak <= 0) return const SizedBox.shrink();

    ref.watch(retentionStoreProvider);
    final thisWeek = ref.read(retentionStoreProvider.notifier).completionsThisWeek;
    return _Tappable(
      tooltip: 'Bekijk je leesreeks',
      hint: 'Open uitleg over je leesreeks en weekoverzicht',
      onTap: () => showStreakDetailSheet(
        context,
        cadence: cadence,
        streak: serverStreak,
        freezes: freezes,
        completionsThisWeek: thisWeek,
        weekDays: weekDays,
      ),
      child: StreakRing(
        streak: serverStreak,
        segmentsFilled: thisWeek.clamp(0, 7),
        hasFreeze: freezes > 0,
        tree: tree,
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
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The daily-streak variant: the reader's own tree - level, species, scene -
/// with the streak count in the badge.
///
/// Kept under its original name because it is still the header's streak mark
/// and every call site and test refers to it by this name; only what it draws
/// changed.
class StreakRing extends StatelessWidget {
  const StreakRing({
    super.key,
    required this.streak,
    this.segmentsFilled = 0,
    this.hasFreeze = false,
    this.tree,
    this.size = 48,
  });

  final int streak;

  /// Days done this week. The tree grows on the streak itself, so this now only
  /// reaches the detail sheet; the parameter stays so call sites and the sheet's
  /// week strip keep one source of truth.
  final int segmentsFilled;

  final bool hasFreeze;

  /// The account's tree state, for seed, wilt and the motion pref. Null until
  /// the first fetch lands, or when the reader has switched the tree off.
  final TreeState? tree;

  final double size;

  @override
  Widget build(BuildContext context) {
    // A streak of 0 renders as a muted, intentional "not started" state rather
    // than a blank slot. (HomeStreakIndicator hides it entirely today, but the
    // widget stays safe if shown directly, e.g. in previews.)
    final isDormant = streak <= 0;

    // "Boom verbergen" means no tree anywhere (TREE_FEATURE_PLAN §10), header
    // included — the streak itself still has to be readable, so it falls back
    // to a plain count pill.
    final days = streak == 1 ? 'dag' : 'dagen';

    if (tree?.disabled == true) {
      return _CountPill(
        label: '$streak',
        semanticsLabel: 'Reeks van $streak $days',
        dormant: isDormant,
        size: size,
      );
    }

    return MiniTree(
      tree: tree,
      dormant: isDormant,
      hasFreeze: hasFreeze,
      badge: '$streak',
      semanticsLabel: hasFreeze
          ? 'Je boom — reeks van $streak $days, met een vrije dag'
          : 'Je boom — reeks van $streak $days',
      size: size,
    );
  }
}

/// The week-goal variant: the same tree, grown by this week's fraction, with
/// `done/target` in the badge instead of a day count.
class WeeklyGoalRing extends StatelessWidget {
  const WeeklyGoalRing({
    super.key,
    required this.done,
    required this.target,
    this.tree,
    this.size = 48,
  });

  final int done;
  final int target;

  /// See [StreakRing.tree].
  final TreeState? tree;

  final double size;

  @override
  Widget build(BuildContext context) {
    // See StreakRing: with the tree switched off the week fraction still has to
    // be readable.
    final lessons = target == 1 ? 'les' : 'lessen';

    if (tree?.disabled == true) {
      return _CountPill(
        label: '$done/$target',
        semanticsLabel: '$done van $target $lessons deze week',
        dormant: done <= 0,
        size: size,
      );
    }

    return MiniTree(
      tree: tree,
      dormant: done <= 0,
      badge: '$done/$target',
      semanticsLabel: 'Je boom — $done van $target $lessons deze week',
      size: size,
    );
  }
}

/// The no-tree fallback for readers who turned the Levensboom off.
///
/// Keeps the header slot the same [size] the tree occupies so nothing beside it
/// shifts, and stays a plain, quiet count — the point of switching the tree off
/// is not to get a differently decorated one.
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.semanticsLabel,
    required this.dormant,
    required this.size,
  });

  final String label;
  final String semanticsLabel;
  final bool dormant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = dormant ? scheme.onSurfaceVariant : AppTheme.positive;

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Container(
            constraints: BoxConstraints(minWidth: size * 0.62),
            padding: EdgeInsets.symmetric(
              horizontal: size * 0.14,
              vertical: size * 0.10,
            ),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: scheme.outlineVariant),
            ),
            // Fixed box + scaleDown so 1, 2 and 3 digits (and "3/5") all fit
            // without the footprint moving.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: AppTheme.bodyStrong.copyWith(
                  fontSize: size * 0.30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Used only before the first `/api/v1/gamification` response lands, or in
/// previews and tests. Constant rather than random so the header does not
/// reshuffle its tree between frames; the account's real seed replaces it as
/// soon as the fetch resolves.

/// Studies helper reused by the continue card.
int firstUndoneDayFor(CuratedStudy study, Set<int> completedDays) {
  for (final lesson in study.lessons) {
    if (!completedDays.contains(lesson.day)) return lesson.day;
  }
  return study.firstLesson?.day ?? 1;
}
