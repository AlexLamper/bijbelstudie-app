import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart' show QuietHours;
import 'reading_settings.dart' show kDailyReminderMinutesKey;

/// Every notification toggle, time and quiet-hours bound (`RETENTION_PLAN.md`
/// §6). Stored under the `notif.` prefix, same load/persist shape as
/// `ReadingSettingsController`.
///
/// Kept apart from `RetentionStore` on purpose: this is what the *reader*
/// chose; that is what the app *observed*.
class NotificationPrefs {
  const NotificationPrefs({
    this.loaded = false,
    this.masterEnabled = false,
    this.studyReminderMinutes = 8 * 60,
    this.studyReminderEnabled = false,
    this.streakAtRiskEnabled = true,
    this.lessonHalfwayEnabled = true,
    this.weeklyGoalEnabled = true,
    this.milestonesEnabled = true,
    this.dormantEnabled = true,
    this.dailyVerseEnabled = false,
    this.dailyVerseMinutes = 7 * 60 + 30,
    this.quietStartMinutes = 21 * 60 + 30,
    this.quietEndMinutes = 7 * 60 + 30,
    this.snoozedUntilEpochMs,
    this.pendingPermissionRequest = false,
  });

  final bool loaded;
  final bool masterEnabled;
  final int studyReminderMinutes;
  final bool studyReminderEnabled;
  final bool streakAtRiskEnabled;
  final bool lessonHalfwayEnabled;
  final bool weeklyGoalEnabled;
  final bool milestonesEnabled;
  final bool dormantEnabled;
  final bool dailyVerseEnabled;
  final int dailyVerseMinutes;
  final int quietStartMinutes;
  final int quietEndMinutes;

  /// "Sla vandaag over" - capped types are cancelled until this instant.
  final int? snoozedUntilEpochMs;

  /// Set by the onboarding wizard: it collects the time but no longer asks the
  /// OS. The post-first-lesson sheet reads this.
  final bool pendingPermissionRequest;

  QuietHours get quietHours =>
      QuietHours(startMinutes: quietStartMinutes, endMinutes: quietEndMinutes);

  bool get snoozedNow {
    final until = snoozedUntilEpochMs;
    return until != null && DateTime.now().millisecondsSinceEpoch < until;
  }

  bool enabledFor(String typeId) {
    if (!masterEnabled) return false;
    return switch (typeId) {
      'studyReminder' => studyReminderEnabled,
      'streakAtRisk' => streakAtRiskEnabled,
      'streakLost' => streakAtRiskEnabled,
      'lessonHalfway' => lessonHalfwayEnabled,
      'weeklyGoal' => weeklyGoalEnabled,
      'milestone' => milestonesEnabled,
      'dormant' => dormantEnabled,
      'dailyVerse' => dailyVerseEnabled,
      _ => false,
    };
  }

  NotificationPrefs copyWith({
    bool? loaded,
    bool? masterEnabled,
    int? studyReminderMinutes,
    bool? studyReminderEnabled,
    bool? streakAtRiskEnabled,
    bool? lessonHalfwayEnabled,
    bool? weeklyGoalEnabled,
    bool? milestonesEnabled,
    bool? dormantEnabled,
    bool? dailyVerseEnabled,
    int? dailyVerseMinutes,
    int? quietStartMinutes,
    int? quietEndMinutes,
    int? snoozedUntilEpochMs,
    bool clearSnooze = false,
    bool? pendingPermissionRequest,
  }) {
    return NotificationPrefs(
      loaded: loaded ?? this.loaded,
      masterEnabled: masterEnabled ?? this.masterEnabled,
      studyReminderMinutes: studyReminderMinutes ?? this.studyReminderMinutes,
      studyReminderEnabled: studyReminderEnabled ?? this.studyReminderEnabled,
      streakAtRiskEnabled: streakAtRiskEnabled ?? this.streakAtRiskEnabled,
      lessonHalfwayEnabled: lessonHalfwayEnabled ?? this.lessonHalfwayEnabled,
      weeklyGoalEnabled: weeklyGoalEnabled ?? this.weeklyGoalEnabled,
      milestonesEnabled: milestonesEnabled ?? this.milestonesEnabled,
      dormantEnabled: dormantEnabled ?? this.dormantEnabled,
      dailyVerseEnabled: dailyVerseEnabled ?? this.dailyVerseEnabled,
      dailyVerseMinutes: dailyVerseMinutes ?? this.dailyVerseMinutes,
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

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // One-time migration from the old single reminder pref.
      var studyMinutes = prefs.getInt('${_p}studyReminderMinutes');
      var studyEnabled = prefs.getBool('${_p}studyReminderEnabled');
      var master = prefs.getBool('${_p}masterEnabled');
      final legacy = prefs.getInt(kDailyReminderMinutesKey);
      if (studyMinutes == null && legacy != null) {
        studyMinutes = legacy;
        studyEnabled = true;
        master ??= true;
        await prefs.setInt('${_p}studyReminderMinutes', legacy);
        await prefs.setBool('${_p}studyReminderEnabled', true);
        await prefs.setBool('${_p}masterEnabled', true);
      }

      state = NotificationPrefs(
        loaded: true,
        masterEnabled: master ?? false,
        studyReminderMinutes: studyMinutes ?? 8 * 60,
        studyReminderEnabled: studyEnabled ?? false,
        streakAtRiskEnabled: prefs.getBool('${_p}streakAtRiskEnabled') ?? true,
        lessonHalfwayEnabled: prefs.getBool('${_p}lessonHalfwayEnabled') ?? true,
        weeklyGoalEnabled: prefs.getBool('${_p}weeklyGoalEnabled') ?? true,
        milestonesEnabled: prefs.getBool('${_p}milestonesEnabled') ?? true,
        dormantEnabled: prefs.getBool('${_p}dormantEnabled') ?? true,
        dailyVerseEnabled: prefs.getBool('${_p}dailyVerseEnabled') ?? false,
        dailyVerseMinutes: prefs.getInt('${_p}dailyVerseMinutes') ?? 7 * 60 + 30,
        quietStartMinutes: prefs.getInt('${_p}quietStartMinutes') ?? 21 * 60 + 30,
        quietEndMinutes: prefs.getInt('${_p}quietEndMinutes') ?? 7 * 60 + 30,
        snoozedUntilEpochMs: prefs.getInt('${_p}snoozedUntilEpochMs'),
        pendingPermissionRequest:
            prefs.getBool('${_p}pendingPermissionRequest') ?? false,
      );
    } catch (_) {
      state = const NotificationPrefs(loaded: true);
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

  Future<void> setStudyReminder({bool? enabled, int? minutes}) async {
    final next = state.copyWith(
      studyReminderEnabled: enabled,
      studyReminderMinutes: minutes,
    );
    await _write((p) {
      if (enabled != null) p.setBool('${_p}studyReminderEnabled', enabled);
      if (minutes != null) p.setInt('${_p}studyReminderMinutes', minutes);
    }, next);
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

  Future<void> setDailyVerse({bool? enabled, int? minutes}) async {
    final next = state.copyWith(
      dailyVerseEnabled: enabled,
      dailyVerseMinutes: minutes,
    );
    await _write((p) {
      if (enabled != null) p.setBool('${_p}dailyVerseEnabled', enabled);
      if (minutes != null) p.setInt('${_p}dailyVerseMinutes', minutes);
    }, next);
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
