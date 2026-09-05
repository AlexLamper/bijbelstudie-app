import 'dart:math' as math;

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

/// The header re-entry indicator (`RETENTION_PLAN.md` §3.1). Daily-streak
/// readers get a 7-segment week ring around a streak count; week-goal readers
/// get a `count / target` progress ring. A `free`-rhythm reader, or one with no
/// data yet, sees nothing here (the old bare "N dagen" pill is gone).
///
/// Tapping it opens [showStreakDetailSheet], which explains whichever of the
/// two this reader is actually looking at — plain rings alone don't say what
/// they mean.
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
        child: WeeklyGoalRing(done: done, target: cadence.weekGoalTarget),
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

class StreakRing extends StatelessWidget {
  const StreakRing({
    super.key,
    required this.streak,
    this.segmentsFilled = 0,
    this.hasFreeze = false,
    this.size = 48,
  });

  final int streak;
  final int segmentsFilled;
  final bool hasFreeze;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Reeks van $streak dagen',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _SegmentRingPainter(
                filled: segmentsFilled.clamp(0, 7),
                total: 7,
                track: scheme.outline,
                fill: AppTheme.flame,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$streak',
                  style: AppTheme.bodyStrong.copyWith(
                    fontSize: size * 0.34,
                    height: 1,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            if (hasFreeze)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(Icons.ac_unit, size: size * 0.28, color: AppTheme.teal),
              ),
          ],
        ),
      ),
    );
  }
}

class WeeklyGoalRing extends StatelessWidget {
  const WeeklyGoalRing({
    super.key,
    required this.done,
    required this.target,
    this.size = 48,
  });

  final int done;
  final int target;

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = target <= 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
    return Semantics(
      label: '$done van $target lessen deze week',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _ArcRingPainter(
                progress: progress,
                track: scheme.outline,
                fill: AppTheme.teal,
              ),
            ),
            Text(
              '$done/$target',
              style: AppTheme.bodyStrong.copyWith(
                fontSize: size * 0.30,
                height: 1,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentRingPainter extends CustomPainter {
  _SegmentRingPainter({
    required this.filled,
    required this.total,
    required this.track,
    required this.fill,
  });

  final int filled;
  final int total;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 3;
    const gap = 0.20; // radians between segments
    final sweep = (2 * math.pi / total) - gap;
    final stroke = size.width * 0.11;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < total; i++) {
      final start = -math.pi / 2 + i * (2 * math.pi / total) + gap / 2;
      paint.color = i < filled ? fill : track;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentRingPainter old) =>
      old.filled != filled || old.fill != fill || old.track != track;
}

class _ArcRingPainter extends CustomPainter {
  _ArcRingPainter({required this.progress, required this.track, required this.fill});

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = (Offset.zero & size).center;
    final radius = size.width / 2 - 3;
    final stroke = size.width * 0.11;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, base);

    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcRingPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}

/// Studies helper reused by the continue card.
int firstUndoneDayFor(CuratedStudy study, Set<int> completedDays) {
  for (final lesson in study.lessons) {
    if (!completedDays.contains(lesson.day)) return lesson.day;
  }
  return study.firstLesson?.day ?? 1;
}
