import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/auth/present/auth_controller.dart';
import 'reminder_copy.dart';

/// Daily reading reminder - a local notification, no server and no push
/// certificate involved. The user picks the time; nothing fires until they do.
///
/// The text is NOT local. It used to be one hardcoded string repeated every
/// day forever, which stops being read after a fortnight. Instead a batch of
/// already-personalised variants is fetched from the server (see
/// [ReminderCopySource]) and scheduled as one one-shot notification per day,
/// so no two consecutive weeks say the same thing and the wording can be
/// improved without an app release.
///
/// That is why this schedules [ReminderCopySource.batchDays] separate
/// notifications instead of a single repeating one: a repeating alarm can only
/// ever carry one piece of text.
class ReminderService {
  ReminderService(this._plugin, this._copySource);

  final FlutterLocalNotificationsPlugin _plugin;
  final ReminderCopySource _copySource;

  /// Day 0 of the batch. Kept at the id the single repeating reminder used, so
  /// [currentStatus] still answers about "the daily reminder" and an install
  /// that predates the batch has its old notification replaced rather than
  /// duplicated.
  static const int _dailyReminderId = 1001;

  /// Days 1..n take the ids after it.
  static int _reminderIdForDay(int dayOffset) => _dailyReminderId + dayOffset;

  static const _androidChannel = AndroidNotificationDetails(
    'daily_reading',
    'Dagelijkse herinnering',
    channelDescription: 'Herinnering om je bijbelgedeelte te lezen',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _details = NotificationDetails(
    android: _androidChannel,
    iOS: DarwinNotificationDetails(),
  );

  bool _initialised = false;

  Future<void> initialise() async {
    if (_initialised || kIsWeb) return;
    tz.initializeTimeZones();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested when the user actually enables the reminder,
        // not on first launch: a permission prompt with no context gets denied.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialised = true;
  }

  Future<bool> requestPermission() async {
    await initialise();
    if (kIsWeb) return false;

    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// Schedules a fortnight of reminders at [hour]:[minute], one per day, each
  /// with its own text.
  ///
  /// Call it again whenever the app opens with the reminder enabled: it is
  /// idempotent, it re-arms the days that have already fired, and it is what
  /// picks up a fresh batch of copy.
  Future<void> scheduleDaily({required int hour, required int minute}) async {
    await initialise();
    if (kIsWeb) return;

    final variants = await _copySource.load();
    await cancelDaily();

    // A batch shorter than the window (the bundled fallback is four) simply
    // repeats itself across the fortnight rather than leaving days unscheduled.
    final firstFireAt = _nextInstanceOf(hour, minute);

    for (var day = 0; day < ReminderCopySource.batchDays; day++) {
      final variant = variants[day % variants.length];
      await _plugin.zonedSchedule(
        _reminderIdForDay(day),
        variant.title,
        variant.body,
        firstFireAt.add(Duration(days: day)),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // Deliberately NOT matchDateTimeComponents: these are one-shot. A
        // repeating schedule would fire the same day's text every day forever,
        // which is the behaviour this replaced.
        payload: variant.deepLink,
      );
    }
  }

  Future<void> cancelDaily() async {
    await initialise();
    if (kIsWeb) return;
    for (var day = 0; day < ReminderCopySource.batchDays; day++) {
      await _plugin.cancel(_reminderIdForDay(day));
    }
  }

  /// Asks the OS - not the stored preference - what state the reminder is
  /// really in, so a UI can never claim it is on when nothing will fire.
  ///
  /// `pendingNotificationRequests()` and the platform permission checks are
  /// confirmed against the flutter_local_notifications 18.0.1 source:
  /// - `pendingNotificationRequests` -
  ///   lib/src/flutter_local_notifications_plugin.dart:448
  /// - `AndroidFlutterLocalNotificationsPlugin.areNotificationsEnabled` -
  ///   lib/src/platform_flutter_local_notifications.dart:559
  /// - `IOSFlutterLocalNotificationsPlugin.checkPermissions` -
  ///   lib/src/platform_flutter_local_notifications.dart:676
  Future<ReminderStatus> currentStatus() async {
    if (kIsWeb) {
      return const ReminderStatus(available: false, permitted: false, pending: false);
    }
    try {
      await initialise();

      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (ios == null && android == null) {
        // Neither platform layer resolved: this build has no notifications
        // implementation to speak of (web is already handled above; this
        // covers desktop, or a plugin that never registered).
        return const ReminderStatus(available: false, permitted: false, pending: false);
      }

      final permitted = ios != null
          ? (await ios.checkPermissions())?.isEnabled ?? false
          : (await android!.areNotificationsEnabled() ?? false);
      // Any day of the batch still queued means the reminder will fire. Only
      // checking day 0 would report "off" the morning after it went off.
      final scheduledIds = (await _plugin.pendingNotificationRequests())
          .map((request) => request.id)
          .toSet();
      final pending = List.generate(
        ReminderCopySource.batchDays,
        _reminderIdForDay,
      ).any(scheduledIds.contains);

      return ReminderStatus(available: true, permitted: permitted, pending: pending);
    } catch (_) {
      // A channel error means the real state cannot be verified - and an
      // unverifiable reminder is exactly what must not be shown as on.
      return const ReminderStatus(available: false, permitted: false, pending: false);
    }
  }

  /// The next occurrence of this wall-clock time in the device's zone. Passing
  /// a time that has already gone by today would fire immediately.
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

final reminderServiceProvider = Provider<ReminderService>((ref) {
  return ReminderService(
    FlutterLocalNotificationsPlugin(),
    ReminderCopySource(ref.watch(apiClientProvider).dio),
  );
});

/// The reminder's real-world state, as reported by the OS rather than the
/// stored preference. See [ReminderService.currentStatus].
class ReminderStatus {
  const ReminderStatus({
    required this.available,
    required this.permitted,
    required this.pending,
  });

  /// No notifications implementation exists on this platform at all (web,
  /// desktop, or a plugin that failed to register). The feature cannot work
  /// here regardless of anything else.
  final bool available;

  /// Whether the OS currently permits this app to show notifications.
  final bool permitted;

  /// Whether any day of the reminder batch (ids 1001..) is genuinely
  /// scheduled with the OS right now, independent of what preferences say.
  final bool pending;

  /// True only when the reminder will actually fire.
  bool get isActive => available && permitted && pending;
}
