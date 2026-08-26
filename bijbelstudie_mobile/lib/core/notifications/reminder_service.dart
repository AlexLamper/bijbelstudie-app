import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Daily reading reminder — a local notification, no server and no push
/// certificate involved. The user picks the time; nothing fires until they do.
class ReminderService {
  ReminderService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const int _dailyReminderId = 1001;

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

  Future<void> scheduleDaily({required int hour, required int minute}) async {
    await initialise();
    if (kIsWeb) return;

    await _plugin.cancel(_dailyReminderId);
    await _plugin.zonedSchedule(
      _dailyReminderId,
      'Tijd om te lezen',
      'Neem even de tijd voor je bijbelgedeelte.',
      _nextInstanceOf(hour, minute),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDaily() async {
    await initialise();
    if (kIsWeb) return;
    await _plugin.cancel(_dailyReminderId);
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
      final pending = (await _plugin.pendingNotificationRequests())
          .any((request) => request.id == _dailyReminderId);

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
  return ReminderService(FlutterLocalNotificationsPlugin());
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

  /// Whether the daily reminder (id 1001) is genuinely scheduled with the OS
  /// right now, independent of what is stored in preferences.
  final bool pending;

  /// True only when the reminder will actually fire.
  bool get isActive => available && permitted && pending;
}
