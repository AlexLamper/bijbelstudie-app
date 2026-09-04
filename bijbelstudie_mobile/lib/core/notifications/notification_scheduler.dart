import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/dashboard/data/daily_verse_store.dart';
import '../../features/dashboard/data/dashboard_models.dart';
import '../../features/dashboard/present/dashboard_providers.dart';
import '../../features/settings/data/notification_prefs.dart';
import '../../features/studies/data/enrollment_models.dart';
import '../../features/studies/data/study_models.dart';
import '../../features/studies/data/study_plan_store.dart';
import '../../features/studies/present/studies_providers.dart';
import 'notification_copy.dart';
import 'notification_service.dart';
import 'retention_store.dart';

/// The two shapes a "streak" can take, chosen by cadence (`RETENTION_PLAN.md`
/// §2). `none` = the reader picked "geen ritme": no streak, no nudges.
enum RetentionModel { dailyStreak, weekGoal, none }

/// A cadence resolved from the server [StudyRhythm] (preferred) or the local
/// [StudyCadence] (offline fallback), flattened to just what the scheduler
/// needs.
class CadenceInfo {
  const CadenceInfo({
    required this.model,
    this.weekGoalTarget = 1,
    this.fixedWeekdays = const {},
    this.everyOtherDay = false,
    this.anchor,
    this.remind = true,
  });

  static const none = CadenceInfo(model: RetentionModel.none, remind: false);

  final RetentionModel model;

  /// Completions needed inside the ISO week, for [RetentionModel.weekGoal].
  final int weekGoalTarget;

  /// `DateTime` weekday ints (Mon=1..Sun=7). Empty = every day.
  final Set<int> fixedWeekdays;

  final bool everyOtherDay;
  final DateTime? anchor;

  /// False for `ownPace` / `free`: the ring may still show, but no reminder is
  /// scheduled (§4.3).
  final bool remind;

  bool isCadenceDay(DateTime day) {
    if (!remind) return false;
    if (everyOtherDay && anchor != null) {
      final diff = DateTime(day.year, day.month, day.day)
          .difference(DateTime(anchor!.year, anchor!.month, anchor!.day))
          .inDays;
      return diff % 2 == 0;
    }
    if (fixedWeekdays.isEmpty) return true;
    return fixedWeekdays.contains(day.weekday);
  }

  /// How many cadence days remain in [day]'s ISO week, counting [day] itself.
  int cadenceDaysLeftThisWeek(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final sunday = d.add(Duration(days: 7 - d.weekday));
    var count = 0;
    for (var t = d; !t.isAfter(sunday); t = t.add(const Duration(days: 1))) {
      if (isCadenceDay(t)) count++;
    }
    return count;
  }
}

/// Resolve a cadence. [rhythm] wins when present; [localCadence] is the offline
/// fallback.
CadenceInfo cadenceFrom({
  StudyRhythm? rhythm,
  List<int> reminderDays = const [],
  StudyCadence? localCadence,
  DateTime? startedAt,
}) {
  if (rhythm != null) {
    switch (rhythm) {
      case StudyRhythm.daily:
        return const CadenceInfo(model: RetentionModel.dailyStreak);
      case StudyRhythm.threePerWeek:
        return const CadenceInfo(
          model: RetentionModel.weekGoal,
          weekGoalTarget: 3,
          fixedWeekdays: {1, 3, 5},
        );
      case StudyRhythm.weekly:
        final wd = startedAt?.weekday ?? 1;
        return CadenceInfo(
          model: RetentionModel.weekGoal,
          weekGoalTarget: 1,
          fixedWeekdays: {wd},
        );
      case StudyRhythm.ownDays:
        final days = reminderDays
            .map((d) => d == 0 ? 7 : d) // 0=Sun -> DateTime Sun=7
            .toSet();
        return CadenceInfo(
          model: RetentionModel.weekGoal,
          weekGoalTarget: days.isEmpty ? 1 : days.length,
          fixedWeekdays: days,
        );
      case StudyRhythm.free:
        return CadenceInfo.none;
    }
  }

  switch (localCadence) {
    case StudyCadence.daily:
      return const CadenceInfo(model: RetentionModel.dailyStreak);
    case StudyCadence.everyOtherDay:
      return CadenceInfo(
        model: RetentionModel.dailyStreak,
        everyOtherDay: true,
        anchor: startedAt,
      );
    case StudyCadence.threePerWeek:
      return const CadenceInfo(
        model: RetentionModel.weekGoal,
        weekGoalTarget: 3,
        fixedWeekdays: {1, 3, 5},
      );
    case StudyCadence.weekly:
      final wd = startedAt?.weekday ?? 1;
      return CadenceInfo(
        model: RetentionModel.weekGoal,
        weekGoalTarget: 1,
        fixedWeekdays: {wd},
      );
    case StudyCadence.ownPace:
      // Ring shows a daily streak; no reminder is scheduled.
      return const CadenceInfo(model: RetentionModel.dailyStreak, remind: false);
    case null:
      return const CadenceInfo(model: RetentionModel.dailyStreak, remind: false);
  }
}

/// One notification the scheduler wants to write. [when] is a `tz.TZDateTime` in
/// production; tests pass a plain `DateTime`.
class Candidate {
  Candidate({
    required this.type,
    required this.when,
    required this.variant,
    required this.deepLink,
    this.slot = 0,
    this.immediate = false,
  });

  final NotifType type;
  final DateTime when;
  final RenderedVariant variant;
  final String deepLink;
  final int slot;

  /// `showNow` instead of `zonedSchedule` (weeklyGoal "met").
  final bool immediate;

  int get _dayOrdinal => when.year * 10000 + when.month * 100 + when.day;
}

/// The priority + cap ladder (§4.4): at most one capped candidate per calendar
/// day; `dailyVerse` and `milestone` are exempt. When [cappedSentToday] is true,
/// every capped candidate that would fire *today* is dropped.
List<Candidate> applyLadder(
  List<Candidate> candidates, {
  required bool cappedSentToday,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final todayOrdinal = today.year * 10000 + today.month * 100 + today.day;

  final byDay = <int, List<Candidate>>{};
  final kept = <Candidate>[];

  for (final c in candidates) {
    if (!c.type.isCapped) {
      kept.add(c);
      continue;
    }
    byDay.putIfAbsent(c._dayOrdinal, () => []).add(c);
  }

  for (final entry in byDay.entries) {
    final list = [...entry.value]
      ..sort((a, b) => b.type.priority.compareTo(a.type.priority));
    if (entry.key <= todayOrdinal && cappedSentToday) continue; // day already spent
    kept.add(list.first);
  }
  return kept;
}

final notificationRecomputeProvider = FutureProvider<void>((ref) async {
  await NotificationScheduler.recompute(ref);
});

/// The single brain (§4.1). A pure function of cached enrollments + study plans
/// + [RetentionStore] + [NotificationPrefs] + last [DashboardData]; produces a
/// candidate list, applies the ladder, then cancel-then-schedules per type.
class NotificationScheduler {
  static Future<void> recompute(Ref ref) async {
    if (kIsWeb) return;

    final prefsCtl = ref.read(notificationPrefsProvider.notifier);
    await prefsCtl.loaded;
    final prefs = ref.read(notificationPrefsProvider);

    final service = ref.read(notificationServiceProvider);
    await service.initialise();

    if (!prefs.masterEnabled) {
      await service.cancelAllManaged();
      return;
    }
    if (!await service.hasPermission()) {
      // Nothing scheduled without permission; the settings hint covers it.
      return;
    }

    final store = ref.read(retentionStoreProvider.notifier);
    await store.loaded;

    // Timezone change -> wipe and re-derive everything against the new zone.
    final zone = service.localZoneName ?? DateTime.now().timeZoneName;
    if (ref.read(retentionStoreProvider).tzName != zone) {
      await service.cancelAllManaged();
      await store.noteTimezone(zone);
    }

    final now = tz.TZDateTime.now(tz.local);

    // ── Resolve the study we nudge for: most recently active enrollment ──
    final enrollments = ref.read(studyEnrollmentsProvider).value ?? const {};
    final plans = ref.read(studyPlansProvider);
    final curated = ref.read(curatedStudiesProvider).value ?? const <CuratedStudy>[];
    final dashboard = ref.read(dashboardProvider).value;

    StudyEnrollment? enrollment;
    for (final e in enrollments.values) {
      if (e.isCompleted || !e.isActive) continue;
      if (enrollment == null) {
        enrollment = e;
        continue;
      }
      final a = e.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final b = enrollment.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (a.isAfter(b)) enrollment = e;
    }

    StudyPlan? plan;
    for (final p in plans.values) {
      if (!p.started) continue;
      if (plan == null || (p.startedAt?.isAfter(plan.startedAt ?? DateTime(0)) ?? false)) {
        plan = p;
      }
    }

    final studyId = enrollment?.studyId ?? plan?.studyId;
    CuratedStudy? study;
    for (final s in curated) {
      if (s.id == studyId) {
        study = s;
        break;
      }
    }

    final cadence = cadenceFrom(
      rhythm: enrollment?.rhythm,
      reminderDays: enrollment?.reminderDays ?? const [],
      localCadence: plan?.cadence,
      startedAt: enrollment?.startedAt ?? plan?.startedAt,
    );

    final resumeDay = enrollment?.currentLessonDay ??
        _firstUndoneDay(study, plan) ??
        1;
    final deepLink =
        studyId != null ? '/studie/$studyId/$resumeDay' : '/dashboard';

    final lessonTitle = study?.lessonForDay(resumeDay)?.title ??
        (study != null ? 'les $resumeDay' : null);
    final streak = ref.read(retentionStoreProvider).localStreak;
    final tokens = <String, String?>{
      'study': study?.title,
      'lesson': lessonTitle,
      'streak': streak > 0 ? '$streak' : null,
      'name': dashboard?.name.split(' ').first,
    };

    final quiet = prefs.quietHours;
    final candidates = <Candidate>[];

    // ── studyReminder ────────────────────────────────────────────────────
    if (prefs.enabledFor('studyReminder') &&
        !prefs.snoozedNow &&
        cadence.model != RetentionModel.none &&
        cadence.remind) {
      final h = prefs.studyReminderMinutes ~/ 60;
      final m = prefs.studyReminderMinutes % 60;
      var slot = 0;
      for (var offset = 0; offset < 14 && slot < 14; offset++) {
        final day = now.add(Duration(days: offset));
        if (!cadence.isCadenceDay(day)) continue;
        if (offset == 0 && store.studiedToday) continue;
        final fire = service.clampToWaking(
          service.nextInstanceOf(h, m, dayOffset: offset),
          quiet,
          NotifType.studyReminder,
        );
        candidates.add(Candidate(
          type: NotifType.studyReminder,
          when: fire,
          slot: slot,
          deepLink: deepLink,
          variant: pickVariant(NotifType.studyReminder,
              rotation: offset, tokens: tokens),
        ));
        slot++;
      }
    }

    final todayIsCadence = cadence.isCadenceDay(now);
    final completionsThisWeek = store.completionsThisWeek;
    final behindBy = cadence.weekGoalTarget - completionsThisWeek;

    // ── streakAtRisk ─────────────────────────────────────────────────────
    if (prefs.enabledFor('streakAtRisk') &&
        !prefs.snoozedNow &&
        todayIsCadence &&
        !store.studiedToday) {
      final atRisk = cadence.model == RetentionModel.dailyStreak
          ? streak >= 2
          : behindBy > 0 &&
              cadence.cadenceDaysLeftThisWeek(now) <= behindBy;
      if (atRisk) {
        final target = (quiet.startMinutes - 30).clamp(0, 20 * 60 + 30);
        final eveningMinutes = target < 20 * 60 + 30 ? target : 20 * 60 + 30;
        final fire = tz.TZDateTime(
            tz.local, now.year, now.month, now.day, eveningMinutes ~/ 60,
            eveningMinutes % 60);
        if (fire.isAfter(now)) {
          candidates.add(Candidate(
            type: NotifType.streakAtRisk,
            when: fire,
            deepLink: deepLink,
            variant: pickVariant(NotifType.streakAtRisk,
                rotation: now.day, tokens: tokens),
          ));
        }
      }
    }

    // ── streakLost ───────────────────────────────────────────────────────
    if (prefs.enabledFor('streakLost') &&
        cadence.model == RetentionModel.dailyStreak) {
      final last = ref.read(retentionStoreProvider).lastCompletionDay;
      final prevStreak = ref.read(retentionStoreProvider).serverStreakSeen;
      const graceDays = 1;
      if (last != null &&
          retentionDayGap(last, retentionDayKey(now)) > 1 + graceDays &&
          (prevStreak >= 3 || streak >= 3) &&
          !store.sentTypeToday(NotifType.streakLost)) {
        final fire = service.clampToWaking(
          service.nextInstanceOf(9, 0),
          quiet,
          NotifType.streakLost,
        );
        candidates.add(Candidate(
          type: NotifType.streakLost,
          when: fire,
          deepLink: '/dashboard',
          variant: pickVariant(NotifType.streakLost, rotation: now.day, tokens: tokens),
        ));
      }
    }

    // ── lessonHalfway ────────────────────────────────────────────────────
    if (prefs.enabledFor('lessonHalfway') && enrollment != null && !store.studiedToday) {
      final step = enrollment.currentStep;
      final last = enrollment.lastActivityAt;
      final ageHours = last == null ? null : now.difference(last).inHours;
      final midLesson = step != StudyStep.intro && step != StudyStep.done;
      if (midLesson && ageHours != null && ageHours >= 24 && ageHours <= 24 * 7) {
        final fire = service.clampToWaking(
          now.add(const Duration(hours: 26)),
          quiet,
          NotifType.lessonHalfway,
        );
        candidates.add(Candidate(
          type: NotifType.lessonHalfway,
          when: fire,
          deepLink: deepLink,
          variant: pickVariant(NotifType.lessonHalfway, rotation: now.day, tokens: tokens),
        ));
      }
    }

    // ── weeklyGoal ───────────────────────────────────────────────────────
    if (prefs.enabledFor('weeklyGoal') && cadence.model == RetentionModel.weekGoal) {
      if (completionsThisWeek >= cadence.weekGoalTarget) {
        final celebrateId = 'weekgoal-${retentionWeekKey(now)}';
        if (!store.hasMilestone(celebrateId)) {
          candidates.add(Candidate(
            type: NotifType.weeklyGoal,
            when: now,
            immediate: true,
            deepLink: '/dashboard',
            variant: pickVariant(NotifType.weeklyGoal,
                rotation: now.day,
                weeklyGoalMet: true,
                tokens: {
                  ...tokens,
                  'target': '${cadence.weekGoalTarget}',
                  'done': '$completionsThisWeek',
                }),
          ));
          await store.markMilestone(celebrateId);
        }
      } else if (!prefs.snoozedNow && !store.studiedToday) {
        // "Behind": the coming Thursday 18:30.
        final daysToThursday = (4 - now.weekday) % 7;
        if (daysToThursday >= 0 && behindBy > 0) {
          final thursday = now.add(Duration(days: daysToThursday));
          final fire = service.clampToWaking(
            tz.TZDateTime(tz.local, thursday.year, thursday.month, thursday.day, 18, 30),
            quiet,
            NotifType.weeklyGoal,
          );
          if (fire.isAfter(now)) {
            candidates.add(Candidate(
              type: NotifType.weeklyGoal,
              when: fire,
              deepLink: deepLink,
              variant: pickVariant(NotifType.weeklyGoal,
                  rotation: now.day,
                  tokens: {
                    ...tokens,
                    'target': '${cadence.weekGoalTarget}',
                    'done': '$completionsThisWeek',
                    'n': '$behindBy',
                  }),
            ));
          }
        }
      }
    }

    // ── dormant (3 / 7 / 14 / 30) ────────────────────────────────────────
    if (prefs.enabledFor('dormant')) {
      final lastOpen = ref.read(retentionStoreProvider).lastOpenDay;
      if (lastOpen != null) {
        const thresholds = [3, 7, 14, 30];
        final sinceOpen = retentionDayGap(lastOpen, retentionDayKey(now));
        for (var i = 0; i < thresholds.length; i++) {
          final t = thresholds[i];
          if (t <= sinceOpen) continue; // already passed without opening
          final base = DateTime.parse(lastOpen).add(Duration(days: t));
          final fire = service.clampToWaking(
            tz.TZDateTime(tz.local, base.year, base.month, base.day, 10, 0),
            quiet,
            NotifType.dormant,
          );
          candidates.add(Candidate(
            type: NotifType.dormant,
            when: fire,
            slot: i,
            deepLink: enrollment != null ? deepLink : '/dashboard',
            variant: pickVariant(NotifType.dormant, rotation: t, tokens: tokens),
          ));
          break; // only the next unreached threshold is armed
        }
      }
    }

    // ── dailyVerse (independent of cadence and of the cap) ───────────────
    if (prefs.enabledFor('dailyVerse')) {
      final verses = ref.read(dailyVerseStoreProvider).history;
      final latest = verses.isEmpty ? null : verses.first;
      final h = prefs.dailyVerseMinutes ~/ 60;
      final m = prefs.dailyVerseMinutes % 60;
      for (var offset = 0; offset < 14; offset++) {
        final fire = service.clampToWaking(
          service.nextInstanceOf(h, m, dayOffset: offset),
          quiet,
          NotifType.dailyVerse,
        );
        candidates.add(Candidate(
          type: NotifType.dailyVerse,
          when: fire,
          slot: offset,
          deepLink: '/dashboard',
          variant: pickVariant(NotifType.dailyVerse, rotation: offset, tokens: {
            'verse': latest?.text,
            'reference': latest?.reference,
          }),
        ));
      }
    }

    // ── Ladder + write ──────────────────────────────────────────────────
    final kept = applyLadder(
      candidates,
      cappedSentToday: store.cappedSentToday,
      now: now,
    );

    final scheduledTypes = kept.map((c) => c.type).toSet();
    for (final type in NotifType.values) {
      if (type == NotifType.milestone) continue;
      await service.cancelType(type);
    }

    for (final c in kept) {
      if (c.immediate) {
        await service.showNow(c.type, c.variant, deepLink: c.deepLink, slot: c.slot);
      } else {
        final tzWhen = c.when is tz.TZDateTime
            ? c.when as tz.TZDateTime
            : tz.TZDateTime.from(c.when, tz.local);
        await service.scheduleOneShot(c.type, tzWhen, c.variant,
            deepLink: c.deepLink, slot: c.slot);
      }
      // Optimistic cap bookkeeping: a capped one-shot firing today counts as
      // spent, so no second capped type is added today even across restarts. A
      // completion before it fires triggers a recompute that cancels it.
      if (c.type.isCapped &&
          c.when.year == now.year &&
          c.when.month == now.month &&
          c.when.day == now.day) {
        await store.recordNotificationSent(c.type, now: now);
      }
    }

    // Types with nothing kept are already cancelled above.
    scheduledTypes; // (kept for readability / future analytics)
  }

  static int? _firstUndoneDay(CuratedStudy? study, StudyPlan? plan) {
    if (study == null) return null;
    final done = plan?.completedDays ?? const <int>{};
    for (final lesson in study.lessons) {
      if (!done.contains(lesson.day)) return lesson.day;
    }
    return study.firstLesson?.day;
  }

  /// Un-celebrated streak milestones from the latest [DashboardData]. Called
  /// after a completion: fires an immediate `milestone` notification when
  /// backgrounded, otherwise the caller shows an in-app celebration.
  static Future<List<String>> pendingMilestones(WidgetRef ref) async {
    final store = ref.read(retentionStoreProvider.notifier);
    await store.loaded;
    final data = ref.read(dashboardProvider).value;
    if (data == null) return const [];
    final found = <String>[];
    for (final n in const [3, 7, 14, 30, 50, 100]) {
      if (data.streak >= n && !store.hasMilestone('streak-$n')) {
        found.add('streak-$n');
      }
    }
    for (final badge in data.badges) {
      if (!store.hasMilestone('badge-$badge')) found.add('badge-$badge');
    }
    return found;
  }

  /// Fires (backgrounded) or returns (foregrounded) the first pending
  /// milestone, marking it celebrated.
  static Future<RenderedVariant?> celebrateNextMilestone(
    WidgetRef ref, {
    required bool foregrounded,
  }) async {
    final pending = await pendingMilestones(ref);
    if (pending.isEmpty) return null;
    final id = pending.first;
    final store = ref.read(retentionStoreProvider.notifier);
    final data = ref.read(dashboardProvider).value;
    final rotation = id.startsWith('streak-')
        ? int.tryParse(id.substring(7)) ?? 0
        : 8;
    final variant = pickVariant(NotifType.milestone, rotation: rotation, tokens: {
      'streak': '${data?.streak ?? 0}',
      'name': data?.name.split(' ').first,
    });
    await store.markMilestone(id);
    if (!foregrounded) {
      final service = ref.read(notificationServiceProvider);
      await service.showNow(NotifType.milestone, variant, deepLink: '/dashboard');
    }
    return variant;
  }
}
