import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/daily_slots.dart' show DailyContentPrefs;
import '../../../core/notifications/notification_service.dart' show QuietHours;
import 'reading_settings.dart' show kDailyReminderMinutesKey;

/// Default morning slot: 07:30.
const int kDefaultMorningMinutes = 7 * 60 + 30;

/// Default evening slot: 20:00.
const int kDefaultEveningMinutes = 20 * 60;

/// Every notification switch, time and quiet-hours bound. Stored under the
/// `notif.` prefix.
///
/// The daily rhythm (DAILY_HABIT_PLAN.md §1): a morning slot (today's task +
/// the verse) and an evening slot (only if the app was not opened that day),
/// at most two notifications a day in total. The per-type switches for the
/// other nudges stay; those only ever fill a day with room left.
///
/// Kept apart from `RetentionStore` on purpose: this is what the *reader*
/// chose; that is what the app *observed*.
class NotificationPrefs {
  const NotificationPrefs({
    this.loaded = false,
    this.masterEnabled = true,
    this.morningMinutes = kDefaultMorningMinutes,
    this.eveningEnabled = true,
    this.eveningMinutes = kDefaultEveningMinutes,
    this.verseEnabled = true,
    this.planEnabled = true,
    this.studyEnabled = true,
    this.streakAtRiskEnabled = true,
    this.lessonHalfwayEnabled = true,
    this.weeklyGoalEnabled = true,
    this.milestonesEnabled = true,
    this.dormantEnabled = true,
    this.quietStartMinutes = 21 * 60 + 30,
    this.quietEndMinutes = 7 * 60 + 30,
    this.snoozedUntilEpochMs,
    this.pendingPermissionRequest = false,
  });

  final bool loaded;

  /// On by default: nothing is scheduled without OS permission anyway, so the
  /// default only decides what happens the moment permission is granted. A
  /// stored `false` is always the reader's own choice and is never overridden.
  /// Off means no notifications at all - the morning slot has no switch of its
  /// own.
  final bool masterEnabled;

  /// "Ochtend": minutes past local midnight.
  final int morningMinutes;

  /// "Avond herinnering".
  final bool eveningEnabled;
  final int eveningMinutes;

  /// Content switches: "Tekst van de dag", "Leesplan", "Studie".
  final bool verseEnabled;
  final bool planEnabled;
  final bool studyEnabled;

  final bool streakAtRiskEnabled;
  final bool lessonHalfwayEnabled;
  final bool weeklyGoalEnabled;
  final bool milestonesEnabled;
  final bool dormantEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;

  /// "Sla vandaag over" - everything is held until this instant.
  final int? snoozedUntilEpochMs;

  /// Set by the onboarding wizard: it collects the time but no longer asks the
  /// OS. The post-first-lesson sheet reads this.
  final bool pendingPermissionRequest;

  /// Compatibility names from before the two daily slots: the old study
  /// reminder's time is the morning time now, and it is on whenever the
  /// reminders are.
  int get studyReminderMinutes => morningMinutes;
  bool get studyReminderEnabled => masterEnabled;

  DailyContentPrefs get content =>
      DailyContentPrefs(verse: verseEnabled, plan: planEnabled, study: studyEnabled);

  QuietHours get quietHours =>
      QuietHours(startMinutes: quietStartMinutes, endMinutes: quietEndMinutes);

  bool get snoozedNow {
    final until = snoozedUntilEpochMs;
    return until != null && DateTime.now().millisecondsSinceEpoch < until;
  }

  bool enabledFor(String typeId) {
    if (!masterEnabled) return false;
    return switch (typeId) {
      'morning' => true,
      'evening' => eveningEnabled,
      'streakAtRisk' => streakAtRiskEnabled,
      'streakLost' => streakAtRiskEnabled,
      'lessonHalfway' => lessonHalfwayEnabled,
      'weeklyGoal' => weeklyGoalEnabled,
      'milestone' => milestonesEnabled,
      // The Levensboom nudge is a win-back message with a friendlier subject,
      // so it rides the "we hebben je gemist" toggle rather than adding a
      // switch nobody would know to look for.
      'dormant' || 'treeWilting' => dormantEnabled,
      // Retired types (the old study reminder and separate verse): never.
      _ => false,
    };
  }

  NotificationPrefs copyWith({
    bool? loaded,
    bool? masterEnabled,
    int? morningMinutes,
    bool? eveningEnabled,
    int? eveningMinutes,
    bool? verseEnabled,
    bool? planEnabled,
    bool? studyEnabled,
    bool? streakAtRiskEnabled,
    bool? lessonHalfwayEnabled,
    bool? weeklyGoalEnabled,
    bool? milestonesEnabled,
    bool? dormantEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
    int? snoozedUntilEpochMs,
    bool clearSnooze = false,
    bool? pendingPermissionRequest,
  }) {
    return NotificationPrefs(
      loaded: loaded ?? this.loaded,
      masterEnabled: masterEnabled ?? this.masterEnabled,
      morningMinutes: morningMinutes ?? this.morningMinutes,
      eveningEnabled: eveningEnabled ?? this.eveningEnabled,
      eveningMinutes: eveningMinutes ?? this.eveningMinutes,
      verseEnabled: verseEnabled ?? this.verseEnabled,
      planEnabled: planEnabled ?? this.planEnabled,
      studyEnabled: studyEnabled ?? this.studyEnabled,
      streakAtRiskEnabled: streakAtRiskEnabled ?? this.streakAtRiskEnabled,
      lessonHalfwayEnabled: lessonHalfwayEnabled ?? this.lessonHalfwayEnabled,
      weeklyGoalEnabled: weeklyGoalEnabled ?? this.weeklyGoalEnabled,
      milestonesEnabled: milestonesEnabled ?? this.milestonesEnabled,
      dormantEnabled: dormantEnabled ?? this.dormantEnabled,
      quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
      quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
      snoozedUntilEpochMs:
          clearSnooze ? null : (snoozedUntilEpochMs ?? this.snoozedUntilEpochMs),
      pendingPermissionRequest:
          pendingPermissionRequest ?? this.pendingPermissionRequest,
    );
  }
}

const _p = 'notif.';

/// The content switches under Instellingen > Meldingen.
enum DailyContentKind { verse, plan, study }

final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsController, NotificationPrefs>(
        NotificationPrefsController.new);

class NotificationPrefsController extends Notifier<NotificationPrefs> {
  final Completer<void> _loaded = Completer<void>();

  Future<void> get loaded => _loaded.future;

  @override
  NotificationPrefs build() {
    _load();
    return const NotificationPrefs();
  }

  /// One-time move from the single study reminder (+ separate verse
  /// notification) to the two daily slots. Only explicit choices carry over:
  ///
  /// - A time the reader set (`notif.studyReminderMinutes`, or the even older
  ///   `app.dailyReminderMinutes`, or - for a verse-only reader - the verse
  ///   time) becomes the morning time. Untouched stays 07:30.
  /// - "Studieherinnering" switched off with no verse notification either:
  ///   no study in the morning and no evening slot (both stored). Not the
  ///   master switch - that old switch never silenced the milestones, the
  ///   streak nudges or the win-back, and must not start doing so now.
  /// - Verse on, study reminder off: the morning keeps the verse, without the
  ///   study.
  ///
  /// Public for the migration tests.
  static Future<void> migrateToDailySlots(SharedPreferences prefs) async {
    const flag = '${_p}dailySlotsMigrated';
    if (prefs.getBool(flag) ?? false) return;

    final studyMinutes = prefs.getInt('${_p}studyReminderMinutes');
    final studyEnabled = prefs.getBool('${_p}studyReminderEnabled');
    final verseEnabled = prefs.getBool('${_p}dailyVerseEnabled');
    final verseMinutes = prefs.getInt('${_p}dailyVerseMinutes');
    final legacy = prefs.getInt(kDailyReminderMinutesKey);

    if (!prefs.containsKey('${_p}morningMinutes')) {
      final explicit = (studyEnabled != false ? studyMinutes ?? legacy : null) ??
          (verseEnabled == true ? verseMinutes : null);
      if (explicit != null && explicit >= 0 && explicit < 24 * 60) {
        await prefs.setInt('${_p}morningMinutes', explicit);
      }
    }
    if (studyEnabled == false) {
      if (!prefs.containsKey('${_p}studyEnabled')) {
        await prefs.setBool('${_p}studyEnabled', false);
      }
      if (verseEnabled != true && !prefs.containsKey('${_p}eveningEnabled')) {
        await prefs.setBool('${_p}eveningEnabled', false);
      }
    }
    await prefs.setBool(flag, true);
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await migrateToDailySlots(prefs);
      } catch (_) {
        // Defaults are safe; the migration retries next launch.
      }

      // The container can be gone by now (a test, a sign-out rebuild).
      if (!ref.mounted) return;
      state = NotificationPrefs(
        loaded: true,
        masterEnabled: prefs.getBool('${_p}masterEnabled') ?? true,
        morningMinutes: prefs.getInt('${_p}morningMinutes') ?? kDefaultMorningMinutes,
        eveningEnabled: prefs.getBool('${_p}eveningEnabled') ?? true,
        eveningMinutes: prefs.getInt('${_p}eveningMinutes') ?? kDefaultEveningMinutes,
        verseEnabled: prefs.getBool('${_p}verseEnabled') ?? true,
        planEnabled: prefs.getBool('${_p}planEnabled') ?? true,
        studyEnabled: prefs.getBool('${_p}studyEnabled') ?? true,
        streakAtRiskEnabled: prefs.getBool('${_p}streakAtRiskEnabled') ?? true,
        lessonHalfwayEnabled: prefs.getBool('${_p}lessonHalfwayEnabled') ?? true,
        weeklyGoalEnabled: prefs.getBool('${_p}weeklyGoalEnabled') ?? true,
        milestonesEnabled: prefs.getBool('${_p}milestonesEnabled') ?? true,
        dormantEnabled: prefs.getBool('${_p}dormantEnabled') ?? true,
        quietStartMinutes: prefs.getInt('${_p}quietStartMinutes') ?? 21 * 60 + 30,
        quietEndMinutes: prefs.getInt('${_p}quietEndMinutes') ?? 7 * 60 + 30,
        snoozedUntilEpochMs: prefs.getInt('${_p}snoozedUntilEpochMs'),
        pendingPermissionRequest:
            prefs.getBool('${_p}pendingPermissionRequest') ?? false,
      );
    } catch (_) {
      if (ref.mounted) state = const NotificationPrefs(loaded: true);
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> _write(void Function(SharedPreferences p) fn, NotificationPrefs next) async {
    state = next;
    try {
      fn(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  Future<void> setMasterEnabled(bool value) => _write(
        (p) => p.setBool('${_p}masterEnabled', value),
        state.copyWith(masterEnabled: value),
      );

  /// Persists the default-on master switch unless the reader already chose.
  /// Used where permission is known to be granted, so the choice is explicit
  /// from then on.
  Future<void> enableIfUnset() async {
    await loaded;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.containsKey('${_p}masterEnabled')) return;
    } catch (_) {
      return;
    }
    await setMasterEnabled(true);
  }

  /// "Ochtend".
  Future<void> setMorningMinutes(int minutes) => _write(
        (p) => p.setInt('${_p}morningMinutes', minutes),
        state.copyWith(morningMinutes: minutes),
      );

  /// "Avond herinnering".
  Future<void> setEvening({bool? enabled, int? minutes}) async {
    final next = state.copyWith(eveningEnabled: enabled, eveningMinutes: minutes);
    await _write((p) {
      if (enabled != null) p.setBool('${_p}eveningEnabled', enabled);
      if (minutes != null) p.setInt('${_p}eveningMinutes', minutes);
    }, next);
  }

  /// "Tekst van de dag" / "Leesplan" / "Studie".
  Future<void> setContent(DailyContentKind kind, bool value) {
    final (key, next) = switch (kind) {
      DailyContentKind.verse => ('${_p}verseEnabled', state.copyWith(verseEnabled: value)),
      DailyContentKind.plan => ('${_p}planEnabled', state.copyWith(planEnabled: value)),
      DailyContentKind.study => ('${_p}studyEnabled', state.copyWith(studyEnabled: value)),
    };
    return _write((p) => p.setBool(key, value), next);
  }

  /// Compatibility for callers from before the two daily slots (onboarding,
  /// the Bijbel-in-een-jaar start flow, the permission sheet): a reminder
  /// time is the morning time; switching the reminder off is switching the
  /// reminders off. `enabled: true` changes nothing on its own - the master
  /// switch (and [enableIfUnset]) decide that.
  Future<void> setStudyReminder({bool? enabled, int? minutes}) async {
    if (minutes != null) await setMorningMinutes(minutes);
    if (enabled == false) await setMasterEnabled(false);
  }

  Future<void> setType(String typeId, bool value) async {
    final next = switch (typeId) {
      'streakAtRisk' => state.copyWith(streakAtRiskEnabled: value),
      'lessonHalfway' => state.copyWith(lessonHalfwayEnabled: value),
      'weeklyGoal' => state.copyWith(weeklyGoalEnabled: value),
      'milestone' => state.copyWith(milestonesEnabled: value),
      'dormant' => state.copyWith(dormantEnabled: value),
      _ => state,
    };
    final key = switch (typeId) {
      'streakAtRisk' => '${_p}streakAtRiskEnabled',
      'lessonHalfway' => '${_p}lessonHalfwayEnabled',
      'weeklyGoal' => '${_p}weeklyGoalEnabled',
      'milestone' => '${_p}milestonesEnabled',
      'dormant' => '${_p}dormantEnabled',
      _ => null,
    };
    if (key == null) return;
    await _write((p) => p.setBool(key, value), next);
  }

  Future<void> setQuietHours({int? startMinutes, int? endMinutes}) async {
    final next = state.copyWith(
      quietStartMinutes: startMinutes,
      quietEndMinutes: endMinutes,
    );
    await _write((p) {
      if (startMinutes != null) p.setInt('${_p}quietStartMinutes', startMinutes);
      if (endMinutes != null) p.setInt('${_p}quietEndMinutes', endMinutes);
    }, next);
  }

  /// "Sla vandaag over" -> snooze until tomorrow 05:00 local.
  Future<void> snoozeToday() async {
    final now = DateTime.now();
    final tomorrow5 = DateTime(now.year, now.month, now.day + 1, 5);
    await _write(
      (p) => p.setInt('${_p}snoozedUntilEpochMs', tomorrow5.millisecondsSinceEpoch),
      state.copyWith(snoozedUntilEpochMs: tomorrow5.millisecondsSinceEpoch),
    );
  }

  /// Snooze from a delivered notification's "Later vandaag" -> +3h.
  Future<void> snoozeHours(int hours) async {
    final until = DateTime.now().add(Duration(hours: hours));
    await _write(
      (p) => p.setInt('${_p}snoozedUntilEpochMs', until.millisecondsSinceEpoch),
      state.copyWith(snoozedUntilEpochMs: until.millisecondsSinceEpoch),
    );
  }

  Future<void> clearSnooze() => _write(
        (p) => p.remove('${_p}snoozedUntilEpochMs'),
        state.copyWith(clearSnooze: true),
      );

  Future<void> setPendingPermissionRequest(bool value) => _write(
        (p) => p.setBool('${_p}pendingPermissionRequest', value),
        state.copyWith(pendingPermissionRequest: value),
      );
}
