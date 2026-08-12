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
