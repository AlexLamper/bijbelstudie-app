import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:timezone/timezone.dart' as tz;

import '../../features/auth/domain/display_name.dart';
import '../../features/auth/present/auth_controller.dart' show authStorageProvider;
import '../../features/dashboard/data/daily_verse_store.dart';
import '../../features/dashboard/data/dashboard_models.dart';
import '../../features/dashboard/present/dashboard_providers.dart';
import '../../features/feedback/data/review_prompt.dart';
import '../../features/levensboom/data/tree_image.dart';
import '../../features/levensboom/present/levensboom_providers.dart';
import '../../features/settings/data/notification_prefs.dart';
import '../../features/studies/data/enrollment_models.dart';
import '../../features/studies/data/enrollment_repository.dart';
import '../../features/studies/data/study_models.dart';
import '../../features/studies/data/study_plan_store.dart';
import '../../features/studies/present/studies_providers.dart';
import '../config/preview_config.dart';
import 'daily_slots.dart';
import 'notification_art.dart';
import 'notification_copy.dart';
import 'notification_schedule.dart';
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
    this.images,
  });

  final NotifType type;
  final DateTime when;
  final RenderedVariant variant;
  final String deepLink;
  final int slot;

  /// The reader's tree, rendered for this notification (treeWilting shows it
  /// as it will look on day three). Null for everything else.
  final TreeImageFiles? images;

  /// `showNow` instead of `zonedSchedule` (weeklyGoal "met").
  final bool immediate;
}

/// The one place the daily total is enforced (DAILY_HABIT_PLAN.md §1): per
/// local calendar day at most [maxPerDay] notifications, counting the ones
/// that day already has in [used] (fired, or armed and kept - see
/// [RetentionStore.usedByDay]). Within a day the highest priority wins - the
/// morning and evening slots outrank every other scheduled type - and a tie
/// goes to the earlier one.
List<Candidate> applyDailyCap(
  List<Candidate> candidates, {
  Map<String, int> used = const {},
  int maxPerDay = kMaxNotificationsPerDay,
}) {
  final byDay = <String, List<Candidate>>{};
  for (final c in candidates) {
    byDay.putIfAbsent(retentionDayKey(c.when), () => []).add(c);
  }
  final kept = <Candidate>[];
  for (final entry in byDay.entries) {
    final room = maxPerDay - (used[entry.key] ?? 0);
    if (room <= 0) continue;
    final list = [...entry.value]
      ..sort((a, b) {
        final p = b.type.priority.compareTo(a.type.priority);
        return p != 0 ? p : a.when.compareTo(b.when);
      });
    kept.addAll(list.take(room));
  }
  kept.sort((a, b) => a.when.compareTo(b.when));
  return kept;
}

/// Whether this device holds a signed-in session (a stored access token).
/// Without one nothing may be armed: every notification is the previous
/// reader's plan, study and streak. A function so tests can stand in.
final notificationSessionProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    if (PreviewConfig.enabled) return true;
    try {
      final token = await ref.read(authStorageProvider).getToken();
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  };
});

/// "Please re-derive the notifications", callable from anywhere:
///
/// ```dart
/// ref.read(notificationReschedulerProvider).requestReschedule();
/// ```
///
/// Works from a widget's `WidgetRef` and from a provider's `Ref` alike.
/// Requests made in the same turn of the event loop fold into one run, and
/// runs are serialized by [NotificationScheduler.recompute] (a request that
/// arrives mid-run becomes one more run afterwards). No timers: a pending
/// debounce timer would outlive every widget test that touches a trigger.
final notificationReschedulerProvider = Provider<NotificationRescheduler>((ref) {
  return NotificationRescheduler(ref);
});

class NotificationRescheduler {
  NotificationRescheduler(this._ref);

  final Ref _ref;
  bool _pending = false;
  bool _refresh = false;

  /// A throttled content change that was not fetched yet; the next request
  /// of any kind fetches.
  bool _dirty = false;
  DateTime? _lastRefresh;

  /// How long a throttled request (a finished step) reuses the last fetch.
  static const throttleWindow = Duration(minutes: 2);

  /// [contentChanged]: progress moved (a lesson finished, a chapter read, a
  /// Bijbel-in-een-jaar portion marked, a plan started or stopped), so the
  /// schedule's words are refetched instead of reused from the cache. Pass
  /// false for a settings change or a resume - the cached words are still
  /// right (or are refetched once they are stale anyway).
  ///
  /// [throttle]: for frequent small changes (each finished step). Within
  /// [throttleWindow] of the last fetch the change is only remembered, and
  /// the next request - the lesson's end, a resume - fetches it.
  void requestReschedule({bool contentChanged = true, bool throttle = false}) {
    if (kIsWeb) return;
    var force = contentChanged || _dirty;
    final last = _lastRefresh;
    if (force &&
        throttle &&
        last != null &&
        DateTime.now().difference(last) < throttleWindow) {
      force = false;
      _dirty = true;
    } else if (force) {
      _dirty = false;
    }
    _refresh = _refresh || force;
    if (_pending) return;
    _pending = true;
    // A microtask, not a zero timer: every request of this turn still lands
    // first, and it never shows up as a pending timer in a widget test.
    scheduleMicrotask(() {
      _pending = false;
      final refresh = _refresh;
      _refresh = false;
      if (refresh) _lastRefresh = DateTime.now();
      NotificationScheduler.recompute(_ref, refreshContent: refresh).catchError(
          (Object e, StackTrace st) =>
              debugPrint('[Notifications] reschedule failed: $e\n$st'));
    });
  }
}

/// What the scheduler reads from the network-backed providers, resolved (not
/// peeked at) before anything is cancelled.
class SchedulerInputs {
  const SchedulerInputs({
    required this.enrollments,
    required this.plans,
    required this.curated,
    required this.dashboard,
  });

  final Map<String, StudyEnrollment> enrollments;
  final Map<String, StudyPlan> plans;
  final List<CuratedStudy> curated;
  final DashboardData? dashboard;
}

/// The single brain (§4.1). A pure function of cached enrollments + study plans
/// + [RetentionStore] + [NotificationPrefs] + last [DashboardData]; produces a
/// candidate list, applies the ladder, then cancel-then-schedules per type.
class NotificationScheduler {
  static bool _running = false;
  static Ref? _queued;
  static bool _queuedRefresh = false;

  /// When an empty enrollment list was last confirmed with the server; see
  /// [loadInputs].
  static DateTime? _emptyConfirmedAt;

  static const _loadBudget = Duration(seconds: 10);

  /// Runs one recompute at a time. Launch, resume, the dashboard and every
  /// completion all ask for one, often together; overlapping runs would
  /// interleave their cancel-then-schedule passes. A request that arrives
  /// mid-run is folded into one more run afterwards, with the newest ref.
  ///
  /// [refreshContent] refetches `/notifications/schedule` even when the cached
  /// copy is fresh; a queued request keeps the flag if any caller set it.
  static Future<void> recompute(Ref ref, {bool refreshContent = false}) async {
    if (kIsWeb) return;
    if (_running) {
      _queued = ref;
      _queuedRefresh = _queuedRefresh || refreshContent;
      return;
    }
    _running = true;
    try {
      Ref? next = ref;
      var refresh = refreshContent;
      while (next != null) {
        _queued = null;
        _queuedRefresh = false;
        try {
          await _recomputeOnce(next, refreshContent: refresh);
        } catch (e, st) {
          if (_queued == null) rethrow;
          debugPrint('[Notifications] recompute failed, rerunning: $e\n$st');
        }
        next = _queued;
        refresh = _queuedRefresh;
      }
    } finally {
      _running = false;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _running = false;
    _queued = null;
    _queuedRefresh = false;
    _emptyConfirmedAt = null;
  }

  /// Cancels today's evening slot: the app is open, so the "not opened today"
  /// nudge is moot. Called on launch and resume, before (and independent of)
  /// the recompute, which then leaves today's evening out. Never throws.
  static Future<void> cancelTodayEvening(Ref ref) async {
    if (kIsWeb) return;
    final now = DateTime.now();
    try {
      await ref.read(notificationServiceProvider).cancelEveningOn(now);
    } catch (e) {
      debugPrint('[Notifications] cancelling the evening slot failed: $e');
    }
    try {
      await ref
          .read(retentionStoreProvider.notifier)
          .dropArmed(NotifType.evening, retentionDayKey(now), now: now);
    } catch (_) {}
  }

  /// The two daily slots for the next 14 local days (DAILY_HABIT_PLAN.md §1):
  /// the morning at [NotificationPrefs.morningMinutes], the evening at
  /// [NotificationPrefs.eveningMinutes] from tomorrow on (today the app is
  /// open, which is exactly when the evening is not wanted). Both are kept out
  /// of quiet hours on their own date, and an evening that would not come
  /// after the morning is left out. Pure: no plugin, no network.
  @visibleForTesting
  static List<Candidate> dailyCandidates({
    required NotificationPrefs prefs,
    required NotificationSchedule? schedule,
    required LocalDailyFallback fallback,
    Map<String, ScheduleVerse> localVerses = const {},
    required tz.TZDateTime now,
  }) {
    if (!prefs.masterEnabled) return const [];
    final quiet = prefs.quietHours;
    final morningMin = clampDailyMinutes(prefs.morningMinutes, quiet);
    final eveningMin = clampDailyMinutes(prefs.eveningMinutes, quiet);
    final snoozedUntil = prefs.snoozedUntilEpochMs;
    bool open(tz.TZDateTime t) =>
        t.isAfter(now) &&
        (snoozedUntil == null || t.millisecondsSinceEpoch >= snoozedUntil);

    final out = <Candidate>[];
    for (var offset = 0; offset < 14; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset);
      final key = retentionDayKey(date);
      final lines = dailyLinesFor(
        day: schedule?.dayFor(key),
        content: prefs.content,
        fallback: fallback,
        fallbackVerse: localVerses[key],
        rotation: epochDayOf(date),
      );
      final slot = dailySlotFor(date);
      tz.TZDateTime at(int minutes) => tz.TZDateTime(
          now.location, date.year, date.month, date.day, minutes ~/ 60, minutes % 60);

      final morning = at(morningMin);
      if (open(morning)) {
        out.add(Candidate(
          type: NotifType.morning,
          when: morning,
          slot: slot,
          variant: lines.morning.variant,
          deepLink: lines.morning.route,
        ));
      }
      if (offset > 0 && prefs.eveningEnabled && eveningMin > morningMin) {
        final evening = at(eveningMin);
        if (open(evening)) {
          out.add(Candidate(
            type: NotifType.evening,
            when: evening,
            slot: slot,
            variant: lines.evening.variant,
            deepLink: lines.evening.route,
          ));
        }
      }
    }
    return out;
  }

  /// Verses the device holds for a given date (the dashboard's daily-verse
  /// archive), for days the schedule does not cover.
  static Map<String, ScheduleVerse> _localVerses(Ref ref) {
    final out = <String, ScheduleVerse>{};
    try {
      for (final e in ref.read(dailyVerseStoreProvider).history) {
        if (e.text.trim().isEmpty || e.reference.trim().isEmpty) continue;
        out.putIfAbsent(e.date, () => ScheduleVerse(text: e.text, reference: e.reference));
      }
    } catch (_) {}
    return out;
  }

  static Future<NotificationSchedule?> _loadSchedule(
    Ref ref,
    String? zone, {
    required bool force,
    required String exclude,
  }) async {
    try {
      return await ref
          .read(notificationScheduleRepositoryProvider)
          .load(timeZone: zone, force: force, exclude: exclude)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[Notifications] schedule unavailable: $e');
      return null;
    }
  }

  static const _dailyTypes = {
    NotifType.morning,
    NotifType.evening,
    // Retired; cancelled alongside so an upgrade never leaves one armed.
    NotifType.studyReminder,
    NotifType.dailyVerse,
  };

  /// Offline (enrollments unknown) but with a cached schedule: rewrites only
  /// the daily slots and leaves every other one-shot as it is. Those still
  /// count towards each day's total, so the cap holds. Only ever reached with
  /// a session ([_recomputeOnce] checks first): signed out, the cached words
  /// are someone else's.
  static Future<void> _rewriteDailyOnly(
    Ref ref,
    NotificationService service,
    NotificationPrefs prefs,
    NotificationSchedule schedule,
    tz.TZDateTime now,
  ) async {
    final store = ref.read(retentionStoreProvider.notifier);
    final candidates = dailyCandidates(
      prefs: prefs,
      schedule: schedule,
      fallback: LocalDailyFallback.none,
      localVerses: _localVerses(ref),
      now: now,
    );
    final others = NotifType.values.toSet().difference(_dailyTypes);
    final kept = applyDailyCap(candidates,
        used: await _withSnooze(store.usedByDay(now, stillArmed: others)));
    for (final type in _dailyTypes) {
      await service.cancelType(type);
    }
    final art = NotificationArt.of(ref, now: now);
    final armed = <({NotifType type, DateTime firesAt})>[];
    for (final c in kept) {
      if (await _write(service, art, c)) armed.add((type: c.type, firesAt: c.when));
    }
    await store.replaceArmed(armed, now: now, onlyTypes: _dailyTypes);
  }

  /// Awaits [future] with a subscription held open, so an auto-dispose
  /// provider nobody is watching is not torn down mid-load.
  static Future<T> _hold<T>(Ref ref, ProviderListenable<Future<T>> future) async {
    final sub = ref.listen<Future<T>>(future, (_, _) {});
    try {
      return await sub.read().timeout(_loadBudget);
    } finally {
      sub.close();
    }
  }

  /// Resolves everything the ladder needs, or null when it cannot be known.
  ///
  /// Null means "keep what is scheduled": the previous batch was built from
  /// real data and stays right for up to two weeks, while cancelling on a
  /// failed or slow load is what used to wipe every study reminder on a
  /// launch without network.
  @visibleForTesting
  static Future<SchedulerInputs?> loadInputs(Ref ref) async {
    try {
      final plansCtl = ref.read(studyPlansProvider.notifier);
      await plansCtl.loaded.timeout(_loadBudget);
      final plans = ref.read(studyPlansProvider);

      var enrollments = await _hold(ref, studyEnrollmentsProvider.future);
      if (enrollments.isEmpty) {
        // The provider maps a failed request to an empty map, which would read
        // as "no study". Confirm with the repository, which throws instead;
        // once per few minutes is plenty.
        final confirmed = _emptyConfirmedAt;
        if (confirmed == null ||
            DateTime.now().difference(confirmed) > const Duration(minutes: 5)) {
          final list = await ref
              .read(enrollmentRepositoryProvider)
              .list()
              .timeout(_loadBudget);
          enrollments = {for (final e in list) e.studyId: e};
          if (list.isEmpty) _emptyConfirmedAt = DateTime.now();
        }
      } else {
        _emptyConfirmedAt = null;
      }

      final curated = await _hold(ref, curatedStudiesProvider.future);

      // Only the reader's first name comes from here: read it if a screen has
      // it loaded, never start a request for it.
      final dashboard =
          ref.exists(dashboardProvider) ? ref.read(dashboardProvider).value : null;

      return SchedulerInputs(
        enrollments: enrollments,
        plans: plans,
        curated: curated,
        dashboard: dashboard,
      );
    } catch (e) {
      debugPrint('[Notifications] inputs unavailable, keeping schedule: $e');
      return null;
    }
  }

  /// Waits (briefly) for the verse archive's first read from disk, so the
  /// daily-verse copy is not rendered from an empty history.
  static Future<void> _verseLoaded(Ref ref) async {
    if (ref.read(dailyVerseStoreProvider).loaded) return;
    final done = Completer<void>();
    final sub = ref.listen<bool>(
      dailyVerseStoreProvider.select((m) => m.loaded),
      (_, loaded) {
        if (loaded && !done.isCompleted) done.complete();
      },
    );
    try {
      await done.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Render from whatever is there.
    } finally {
      sub.close();
    }
  }

  static Future<void> _recomputeOnce(Ref ref, {bool refreshContent = false}) async {
    final prefsCtl = ref.read(notificationPrefsProvider.notifier);
    await prefsCtl.loaded;
    final prefs = ref.read(notificationPrefsProvider);

    final service = ref.read(notificationServiceProvider);
    await service.initialise();

    if (!prefs.masterEnabled) {
      await service.cancelAllManaged();
      return;
    }
    if (!await ref.read(notificationSessionProvider)()) {
      // Signed out (or the session expired): nothing of the previous
      // reader's may stay armed, and nothing is written from the cache.
      await service.cancelAllManaged();
      return;
    }
    if (!await service.hasPermission()) {
      // Nothing scheduled without permission; the settings hint covers it.
      return;
    }

    final store = ref.read(retentionStoreProvider.notifier);
    await store.loaded;
    // A recompute only ever runs with the app in the foreground, so today
    // counts as opened: today's evening slot is not armed again.
    await store.markOpened();

    final inputs = await loadInputs(ref);
    final schedule = await _loadSchedule(
      ref,
      service.localZoneName,
      force: refreshContent && inputs != null,
      exclude: prefs.content.excludeParam,
    );
    await _verseLoaded(ref);
    if (inputs == null) {
      // Nothing known about the reader's studies: keep what is scheduled -
      // unless the cached schedule lets the daily slots be rewritten (a
      // settings change made offline, say).
      if (schedule != null) {
        await _rewriteDailyOnly(
            ref, service, prefs, schedule, tz.TZDateTime.now(tz.local));
      }
      return;
    }

    // Timezone change -> wipe and re-derive everything against the new zone.
    final zone = service.localZoneName ?? DateTime.now().timeZoneName;
    if (ref.read(retentionStoreProvider).tzName != zone) {
      await service.cancelAllManaged();
      await store.noteTimezone(zone);
    }

    final now = tz.TZDateTime.now(tz.local);

    // ── Resolve the study we nudge for: most recently active enrollment ──
    final enrollments = inputs.enrollments;
    final plans = inputs.plans;
    final curated = inputs.curated;
    final dashboard = inputs.dashboard;

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

    // No study running: the daily reminder is a reading reminder instead of
    // nothing, on a plain daily cadence.
    final reading = studyId == null;
    final cadence = reading
        ? const CadenceInfo(model: RetentionModel.dailyStreak)
        : cadenceFrom(
            rhythm: enrollment?.rhythm,
            reminderDays: enrollment?.reminderDays ?? const [],
            localCadence: plan?.cadence,
            startedAt: enrollment?.startedAt ?? plan?.startedAt,
          );

    final resumeDay = enrollment?.currentLessonDay ??
        _firstUndoneDay(study, plan) ??
        1;
    final deepLink = studyId == null
        ? '/read'
        : studyDeepLink(studyId, resumeDay, enrollment?.resumeStep);

    final lessonTitle = study?.lessonForDay(resumeDay)?.title ??
        (study != null ? 'les $resumeDay' : null);
    final streak = ref.read(retentionStoreProvider).localStreak;
    final tokens = <String, String?>{
      'study': study?.title,
      'lesson': lessonTitle,
      'streak': streak > 0 ? '$streak' : null,
      'name': dashboard == null
          ? null
          : displayFirstName(dashboard.name, dashboard.email),
    };

    final quiet = prefs.quietHours;
    final candidates = <Candidate>[];
    String? weekGoalCelebration;

    // ── morning + evening (the two daily slots) ─────────────────────────
    candidates.addAll(dailyCandidates(
      prefs: prefs,
      schedule: schedule,
      fallback: studyId == null
          ? LocalDailyFallback.none
          : LocalDailyFallback(
              studyTitle: study?.title,
              lessonLabel: lessonTitle,
              studyRoute: deepLink,
            ),
      localVerses: _localVerses(ref),
      now: now,
    ));

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
            // The hours are burned into the picture too; a template that wants
            // them and cannot have them falls through to the next in the pool.
            variant: pickVariant(NotifType.streakAtRisk,
                rotation: now.day,
                tokens: {
                  ...tokens,
                  'hours': NotificationArt.hoursToMidnight(fire)?.toString(),
                }),
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
          !store.sentTypeOn(NotifType.streakLost, now)) {
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
          weekGoalCelebration = celebrateId;
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

    // ── dormant (3 / 7 / 14 / 30 days after the last open) ──────────────
    //
    // The next unreached threshold is armed; inside the 14-day daily-slot
    // window it only survives the cap on a day with a slot switched off. So
    // every threshold beyond that window is armed as well: a reader who stops
    // opening the app runs out of daily slots after day 13, and these are the
    // win-back that is left. All of it still goes through [applyDailyCap].
    if (prefs.enabledFor('dormant')) {
      final lastOpen = ref.read(retentionStoreProvider).lastOpenDay;
      if (lastOpen != null && lastOpen.isNotEmpty) {
        candidates.addAll(dormantCandidates(
          lastOpenDay: lastOpen,
          sinceOpen: retentionDayGap(lastOpen, retentionDayKey(now)),
          now: now,
          fireAt: (base) => service.clampToWaking(
            tz.TZDateTime(tz.local, base.year, base.month, base.day, 10, 0),
            quiet,
            NotifType.dormant,
          ),
          deepLink: enrollment != null ? deepLink : '/dashboard',
          tokens: tokens,
        ));
      }
    }

    // ── treeWilting (TREE_FEATURE_PLAN.md §5.6) ──────────────────────────
    //
    // Exactly two days away, and only then: the Levensboom drops to 0.75 health
    // on day two and only *looks* wilted from day three, so this arrives while
    // there is still nothing to feel bad about. The server's own
    // `daysSinceActive` is used when the tree happens to be loaded; otherwise
    // the local completion log stands in, so the nudge still works offline and
    // without waking a provider nobody is watching.
    if (prefs.enabledFor('treeWilting') && !prefs.snoozedNow) {
      final tree = ref.exists(treeStateProvider)
          ? ref.read(treeStateProvider).value
          : null;
      final lastDone = ref.read(retentionStoreProvider).lastCompletionDay;
      final daysAway = tree?.daysSinceActive ??
          (lastDone == null
              ? null
              : retentionDayGap(lastDone, retentionDayKey(now)));

      if (daysAway == 2 &&
          !(tree?.disabled ?? false) &&
          !store.sentTypeOn(NotifType.treeWilting, now)) {
        final fire = service.clampToWaking(
          service.nextInstanceOf(10, 30),
          quiet,
          NotifType.treeWilting,
        );
        candidates.add(Candidate(
          type: NotifType.treeWilting,
          when: fire,
          deepLink: '/profile/boom',
          variant: pickVariant(NotifType.treeWilting,
              rotation: now.day, tokens: tokens),
          // The picture is the nudge: the tree as it will look tomorrow, so the
          // reader sees what one short read keeps. Drawn by [NotificationArt]
          // in the write loop, so a candidate the ladder drops costs no render.
        ));
      }
    }

    // ── Daily total + write ─────────────────────────────────────────────
    // A "Later vandaag" re-post is moot once the day's study is done; one
    // that stays counts towards its day.
    if (store.studiedToday) await service.cancelSnooze();
    final kept = applyDailyCap(candidates, used: await _withSnooze(store.usedByDay(now)));
    if (weekGoalCelebration != null &&
        kept.any((c) => c.type == NotifType.weeklyGoal && c.immediate)) {
      await store.markMilestone(weekGoalCelebration);
    }

    for (final type in NotifType.values) {
      if (type == NotifType.milestone) continue;
      await service.cancelType(type);
    }

    // One art run per recompute: renders lazily, memoises by name, and stops
    // when its budget is spent (`AVATAR_NOTIFICATIONS_PLAN.md` §3).
    final art = NotificationArt.of(ref, now: now);
    unawaited(NotificationArt.sweep(now: now));

    final armed = <({NotifType type, DateTime firesAt})>[];
    for (final c in kept) {
      // One failed write (a missing attachment, a plugin error) must not cost
      // the rest of the batch; it is retried once without its picture.
      final ok = await _write(service, art, c);
      if (!ok) continue;
      armed.add((type: c.type, firesAt: c.immediate ? now : c.when));
    }
    // The ledger records the instant each one-shot fires; it only counts as
    // "sent" once that instant has passed, so re-running before then keeps it
    // instead of dropping it (`sentTagFired`).
    await store.replaceArmed(armed, now: now);
  }

  /// [used] plus the pending "Later vandaag" re-post, on its own day.
  static Future<Map<String, int>> _withSnooze(Map<String, int> used) async {
    final at = await NotificationService.snoozeRepostAt();
    if (at == null) return used;
    final key = retentionDayKey(at);
    return {...used, key: (used[key] ?? 0) + 1};
  }

  /// The win-back thresholds, in days after the last open.
  static const dormantThresholds = [3, 7, 14, 30];

  /// The dormant candidates for a reader last seen on [lastOpenDay]: the next
  /// unreached threshold, plus every later one that falls after the daily
  /// slots' 14-day window (whose last slot is on `now + 13 days`).
  @visibleForTesting
  static List<Candidate> dormantCandidates({
    required String lastOpenDay,
    required int sinceOpen,
    required DateTime now,
    required DateTime Function(DateTime base) fireAt,
    required String deepLink,
    Map<String, String?> tokens = const {},
  }) {
    final horizon = retentionDayKey(DateTime(now.year, now.month, now.day + 13));
    final lastOpen = DateTime.parse(lastOpenDay);
    final out = <Candidate>[];
    for (var i = 0; i < dormantThresholds.length; i++) {
      final t = dormantThresholds[i];
      if (t <= sinceOpen) continue; // already passed without opening
      final fire = fireAt(DateTime(lastOpen.year, lastOpen.month, lastOpen.day + t));
      final beyond = retentionDayKey(fire).compareTo(horizon) > 0;
      if (out.isNotEmpty && !beyond) continue;
      out.add(Candidate(
        type: NotifType.dormant,
        when: fire,
        slot: i,
        deepLink: deepLink,
        variant: pickVariant(NotifType.dormant, rotation: t, tokens: tokens),
      ));
    }
    return out;
  }

  /// Writes [c]; true when the OS accepted it.
  static Future<bool> _write(
    NotificationService service,
    NotificationArt art,
    Candidate c,
  ) async {
    TreeImageFiles? images;
    try {
      images = c.images ??
          await art.forCandidate(c.type, c.when, celebrate: c.immediate);
    } catch (e) {
      debugPrint('[Notifications] art for ${c.type.id} failed: $e');
    }
    for (final withImages in [if (images != null) true, false]) {
      try {
        final pic = withImages ? images : null;
        if (c.immediate) {
          await service.showNow(c.type, c.variant,
              deepLink: c.deepLink, slot: c.slot, images: pic);
        } else {
          final tzWhen = c.when is tz.TZDateTime
              ? c.when as tz.TZDateTime
              : tz.TZDateTime.from(c.when, tz.local);
          await service.scheduleOneShot(c.type, tzWhen, c.variant,
              deepLink: c.deepLink, slot: c.slot, images: pic);
        }
        return true;
      } catch (e, st) {
        debugPrint('[Notifications] ${c.type.id} slot ${c.slot} '
            '${withImages ? 'with' : 'without'} art failed: $e\n$st');
      }
    }
    return false;
  }

  /// The lesson a study notification opens: the resume day, on the step the
  /// reader left off on when the server knows it.
  static String studyDeepLink(String studyId, int day, StudyStep? step) {
    final query = step == null || step == StudyStep.done ? '' : '?stap=${step.id}';
    // Encoded: the router decodes path parameters and the tap whitelist
    // accepts the escapes.
    return '/studie/${Uri.encodeComponent(studyId)}/$day$query';
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

  /// The copy that actually matches [id] (`streak-<n>` or `badge-<id>`).
  ///
  /// Unlike [pickVariant] - built to rotate through *interchangeable* lines so
  /// a recurring reminder never repeats two days running - the milestone pool
  /// is not interchangeable: `ms2`/`ms3`/`ms4`/`ms7` hard-code "7 dagen" / "14
  /// dagen" / "30 dagen" / "100 dagen" as plain text for that exact streak
  /// length, not as a rotation slot. Selecting a slot with `n % pool.length`
  /// (the old approach) put the reader's real milestone through someone
  /// else's copy whenever the arithmetic lined up - a 14- or a 30-day streak
  /// both landed on index 6, `ms7`'s "100 dagen", because
  /// `14 % 8 == 30 % 8 == 6`. This maps each known id to its own template
  /// instead, so "100 dagen" only ever renders for `streak-100`.
  static RenderedVariant milestoneVariant(
    String id, {
    required Map<String, String?> tokens,
  }) {
    final pool = notificationCopy[NotifType.milestone] ?? const [];
    VariantTemplate byId(String templateId) => pool.firstWhere(
          (t) => t.id == templateId,
          orElse: () => pool.first,
        );

    final templateId = switch (id) {
      'streak-7' => 'ms2',
      'streak-14' => 'ms3',
      'streak-30' => 'ms4',
      'streak-100' => 'ms7',
      // 3, 50, or any other threshold with no dedicated line: the generic
      // "{streak} dagen op rij" line, filled with the real count.
      _ when id.startsWith('streak-') => 'ms1',
      // badge-<id>: no per-badge copy exists, so a neutral "new badge" line.
      _ => 'ms8',
    };
    return renderVariant(NotifType.milestone, byId(templateId), tokens);
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
    final variant = milestoneVariant(id, tokens: {
      'streak': '${data?.streak ?? 0}',
      'name': data == null ? null : displayFirstName(data.name, data.email),
    });
    await store.markMilestone(id);

    // A streak milestone is the clearest "this app is working for me" moment
    // there is, so it counts towards the rating gate. Recorded only - the
    // native review sheet is never fired from here; `ReviewPromptHost` picks
    // it up on the next calm screen. Badges are left out: several are handed
    // out for one-off actions rather than for sticking with it.
    if (id.startsWith('streak-')) {
      unawaited(
        ref
            .read(reviewPromptProvider.notifier)
            .recordSuccess(ReviewSignal.streakMilestone),
      );
    }

    if (!foregrounded) {
      // Counts towards the daily total like everything else: every
      // notification today, fired or still to come.
      final now = DateTime.now();
      final today = store.usedByDay(now,
              stillArmed: NotifType.values.toSet())[retentionDayKey(now)] ??
          0;
      if (today >= kMaxNotificationsPerDay) return variant;
      final service = ref.read(notificationServiceProvider);
      // A milestone carries the grown tree - the thing the streak or badge
      // just did something for.
      final images = await NotificationArt.ofWidget(ref)
          .forCandidate(NotifType.milestone, DateTime.now());
      await service.showNow(NotifType.milestone, variant, deepLink: '/dashboard', images: images);
      await store.recordNotificationSent(NotifType.milestone, now: now);
    }
    return variant;
  }
}
