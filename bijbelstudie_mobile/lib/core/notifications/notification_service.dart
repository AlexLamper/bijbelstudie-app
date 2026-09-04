import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_service.dart' show ReminderStatus;

export 'reminder_service.dart' show ReminderStatus;

/// Every kind of local notification the app can raise.
///
/// The retention plan (`RETENTION_PLAN.md` §4) turns the single "daily reading
/// reminder" into a small ladder of nudges. Each type owns a stable id range so
/// [NotificationService] can cancel and re-schedule one kind without touching
/// the others - the whole scheduler is cancel-then-set, on every foreground.
enum NotifType {
  studyReminder,
  streakAtRisk,
  streakLost,
  lessonHalfway,
  weeklyGoal,
  milestone,
  dormant,
  dailyVerse,
}

extension NotifTypeX on NotifType {
  /// Wire/analytics id, and the tag written into [RetentionStore.sentLog].
  String get id => switch (this) {
    NotifType.studyReminder => 'studyReminder',
    NotifType.streakAtRisk => 'streakAtRisk',
    NotifType.streakLost => 'streakLost',
    NotifType.lessonHalfway => 'lessonHalfway',
    NotifType.weeklyGoal => 'weeklyGoal',
    NotifType.milestone => 'milestone',
    NotifType.dormant => 'dormant',
    NotifType.dailyVerse => 'dailyVerse',
  };

  /// Android channel this type is delivered on (§4.2).
  String get channelId => switch (this) {
    NotifType.studyReminder => 'study_reminders',
    NotifType.streakAtRisk ||
    NotifType.streakLost ||
    NotifType.weeklyGoal => 'streak',
    NotifType.lessonHalfway => 'progress',
    NotifType.milestone => 'milestones',
    NotifType.dailyVerse => 'daily_verse',
    NotifType.dormant => 'winback',
  };

  /// Types that count against the "≤ 1 engagement notification per day" cap
  /// (§4.4). `dailyVerse` and `milestone` are exempt.
  bool get isCapped => switch (this) {
    NotifType.dailyVerse || NotifType.milestone => false,
    _ => true,
  };

  /// Higher wins when two candidates want the same day (§4.4).
  int get priority => switch (this) {
    NotifType.milestone => 100,
    NotifType.streakLost => 90,
    NotifType.lessonHalfway => 80,
    NotifType.streakAtRisk => 70,
    NotifType.studyReminder => 60,
    NotifType.weeklyGoal => 50,
    NotifType.dormant => 40,
    NotifType.dailyVerse => 10,
  };

  /// Morning types clamp *later* out of quiet hours; evening types clamp
  /// *earlier* (§4.5).
  bool get isEvening =>
      this == NotifType.streakAtRisk || this == NotifType.weeklyGoal;

  /// The id block reserved for this type. One-shot types that fan out over a
  /// 14-day window (studyReminder, dailyVerse) own a range; the rest own a
  /// single id (dormant owns four - one per threshold).
  List<int> get idRange => switch (this) {
    NotifType.studyReminder => List.generate(14, (i) => 1001 + i),
    NotifType.dailyVerse => List.generate(14, (i) => 1100 + i),
    NotifType.streakAtRisk => const [1200],
    NotifType.streakLost => const [1201],
    NotifType.lessonHalfway => const [1202],
    NotifType.weeklyGoal => const [1203],
    NotifType.dormant => const [1210, 1211, 1212, 1213],
    NotifType.milestone => const [1300],
  };
}

/// Quiet-hours window, minutes past local midnight. Wraps across midnight when
/// [startMinutes] > [endMinutes] (the default 21:30 -> 07:30 does).
class QuietHours {
  const QuietHours({required this.startMinutes, required this.endMinutes});

  static const defaults = QuietHours(startMinutes: 21 * 60 + 30, endMinutes: 7 * 60 + 30);

  final int startMinutes;
  final int endMinutes;

  bool contains(int minutesOfDay) {
    if (startMinutes == endMinutes) return false;
    if (startMinutes < endMinutes) {
      return minutesOfDay >= startMinutes && minutesOfDay < endMinutes;
    }
    // Wraps midnight.
    return minutesOfDay >= startMinutes || minutesOfDay < endMinutes;
  }
}

/// One notification's rendered words. The scheduler fills the tokens; the
/// service only ever sees final strings.
class RenderedVariant {
  const RenderedVariant({
    required this.variantId,
    required this.title,
    required this.body,
  });

  final String variantId;
  final String title;
  final String body;
}

/// Fired from a background isolate when a notification action button is tapped
/// with the app not running. It cannot touch the widget tree; the pending route
/// is stashed and consumed on next launch by [NotificationService.attachRouter].
@pragma('vm:entry-point')
void notificationBackgroundTap(NotificationResponse response) {
  // No-op body: the OS still delivers the tap to the foreground handler when
  // the app is resumed, and cold starts read getNotificationAppLaunchDetails().
}

/// The one place local notifications are scheduled, cancelled and routed.
///
/// Generalises the old `ReminderService` (one repeating "read your chapter"
/// reminder) into the typed ladder from `RETENTION_PLAN.md`. It owns:
/// - `tz.setLocalLocation` from the real IANA zone (fixes the UTC-drift bug:
///   the old code initialised the zone database but never set `tz.local`, so a
///   reminder for 08:00 fired at 08:00 UTC).
/// - Android channel registration + one-time deletion of the legacy
///   `daily_reading` channel.
/// - The notification-tap handler, wired to `GoRouter` so a tapped reminder
///   deep-links instead of just foregrounding the app.
class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialised = false;
  bool _tzReady = false;

  static GoRouter? _router;
  static String? _pendingRoute;
  static void Function(String actionId)? onAction;

  /// Called from `routerProvider` once the router exists. Flushes any route a
  /// cold-start tap left pending.
  static void attachRouter(GoRouter router) {
    _router = router;
    final pending = _pendingRoute;
    if (pending != null) {
      _pendingRoute = null;
      // After the first frame so the navigator is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) => router.go(pending));
    }
  }

  static void _route(String? payload) {
    final target = (payload == null || payload.isEmpty) ? '/dashboard' : payload;
    final router = _router;
    if (router != null) {
      router.go(target);
    } else {
      _pendingRoute = target;
    }
  }

  /// The IANA zone name last applied, e.g. `Europe/Amsterdam`. Null until
  /// [initialise] has run on a mobile platform.
  String? localZoneName;

  Future<void> initialise() async {
    if (_initialised || kIsWeb) return;
    await _ensureTimezone();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _engagementCategory,
          actions: [
            DarwinNotificationAction.plain('LATER', 'Later vandaag'),
            DarwinNotificationAction.plain('OPEN', 'Openen'),
          ],
          options: const {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onForegroundTap,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundTap,
    );

    await _registerAndroidChannels();
    _initialised = true;

    // A cold start from a notification tap: route as soon as the tree is ready.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _route(launch!.notificationResponse?.payload);
    }
  }

  Future<void> _ensureTimezone() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final name = info.identifier;
      tz.setLocalLocation(tz.getLocation(name));
      localZoneName = name;
    } catch (_) {
      // Keep whatever `timezone` defaults to (UTC). Better a slightly wrong
      // fire time than a crash at startup.
      localZoneName = tz.local.name;
    }
    _tzReady = true;
  }

  void _onForegroundTap(NotificationResponse response) {
    final action = response.actionId;
    if (action != null && action.isNotEmpty && action != 'OPEN') {
      onAction?.call(action);
      if (action == 'LATER') return;
    }
    _route(response.payload);
  }

  static const _engagementCategory = 'engagement';

  static final _channels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      'study_reminders',
      'Studieherinnering',
      description: 'Een rustig zetje op je studiedag',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      'streak',
      'Je reeks',
      description: 'Herinneringen rond je reeks en je weekdoel',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      'progress',
      'Voortgang & lessen',
      description: 'Een onafgemaakte les die klaarligt',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      'milestones',
      'Mijlpalen',
      description: 'Kleine vieringen bij een mijlpaal',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'daily_verse',
      'Vers van de dag',
      description: 'Het vers van vandaag',
      importance: Importance.low,
    ),
    AndroidNotificationChannel(
      'winback',
      'Weer welkom',
      description: 'Een zachte groet na een tijd afwezig',
      importance: Importance.low,
    ),
  ];

  Future<void> _registerAndroidChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final channel in _channels) {
      await android.createNotificationChannel(channel);
    }
    // The old single channel (`RETENTION_PLAN.md` §4.2). Android ignores
    // importance changes to a live channel, so the id is retired rather than
    // reused.
    try {
      await android.deleteNotificationChannel('daily_reading');
    } catch (_) {
      // Never existed on this install - fine.
    }
  }

  Future<bool> requestPermission() async {
    await initialise();
    if (kIsWeb) return false;

    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  Future<bool> hasPermission() async {
    if (kIsWeb) return false;
    try {
      await initialise();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return (await ios.checkPermissions())?.isEnabled ?? false;
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
    } catch (_) {}
    return false;
  }

  /// The next wall-clock occurrence of [hour]:[minute] in the device zone,
  /// [dayOffset] days out. Passing a time already gone today rolls to tomorrow
  /// when [dayOffset] is 0.
  tz.TZDateTime nextInstanceOf(int hour, int minute, {int dayOffset = 0}) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute)
        .add(Duration(days: dayOffset));
    if (dayOffset == 0 && !when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    return when;
  }

  /// Moves [desired] out of the quiet-hours window (§4.5). Morning types land
  /// at [quiet.endMinutes]; evening types land 30 min before [quiet.startMinutes]
  /// on the same evening. Nothing is ever scheduled inside the window.
  tz.TZDateTime clampToWaking(tz.TZDateTime desired, QuietHours quiet, NotifType type) {
    final minutesOfDay = desired.hour * 60 + desired.minute;
    if (!quiet.contains(minutesOfDay)) return desired;

    final midnight = tz.TZDateTime(tz.local, desired.year, desired.month, desired.day);
    if (type.isEvening) {
      final target = quiet.startMinutes - 30;
      final clamped = midnight.add(Duration(minutes: target < 0 ? 0 : target));
      // If the evening slot already passed, don't fire tonight at all - push to
      // the morning slot of the next day.
      final now = tz.TZDateTime.now(tz.local);
      if (clamped.isAfter(now)) return clamped;
      return midnight.add(Duration(days: 1, minutes: quiet.endMinutes));
    }
    // Morning type inside the window: the window ends this morning if
    // desired < endMinutes, otherwise it ends tomorrow morning.
    if (minutesOfDay < quiet.endMinutes) {
      return midnight.add(Duration(minutes: quiet.endMinutes));
    }
    return midnight.add(Duration(days: 1, minutes: quiet.endMinutes));
  }

  NotificationDetails _detailsFor(NotifType type, {bool withActions = true}) {
    final android = AndroidNotificationDetails(
      type.channelId,
      _channels
          .firstWhere((c) => c.id == type.channelId, orElse: () => _channels.first)
          .name,
      importance:
          type == NotifType.milestone ? Importance.high : Importance.defaultImportance,
      priority:
          type == NotifType.milestone ? Priority.high : Priority.defaultPriority,
      actions: withActions && type.isCapped
          ? const [
              AndroidNotificationAction('LATER', 'Later vandaag'),
              AndroidNotificationAction('OPEN', 'Openen'),
            ]
          : null,
    );
    final ios = DarwinNotificationDetails(
      categoryIdentifier: type.isCapped ? _engagementCategory : null,
    );
    return NotificationDetails(android: android, iOS: ios);
  }

  /// Schedules one one-shot for [type] at [when] carrying [variant] and a tap
  /// [deepLink]. [slot] disambiguates types whose id range holds several ids
  /// (studyReminder, dailyVerse, dormant); it indexes into [NotifTypeX.idRange].
  Future<void> scheduleOneShot(
    NotifType type,
    tz.TZDateTime when,
    RenderedVariant variant, {
    required String deepLink,
    int slot = 0,
  }) async {
    await initialise();
    if (kIsWeb) return;
    final ids = type.idRange;
    final id = ids[slot.clamp(0, ids.length - 1)];
    await _plugin.zonedSchedule(
      id,
      variant.title,
      variant.body,
      when,
      _detailsFor(type),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: deepLink,
    );
  }

  /// Fires [type] right now (milestone celebration when backgrounded, the
  /// "weekdoel gehaald" ping the moment the goal is met).
  Future<void> showNow(
    NotifType type,
    RenderedVariant variant, {
    required String deepLink,
    int slot = 0,
  }) async {
    await initialise();
    if (kIsWeb) return;
    final ids = type.idRange;
    final id = ids[slot.clamp(0, ids.length - 1)];
    await _plugin.show(
      id,
      variant.title,
      variant.body,
      _detailsFor(type, withActions: false),
      payload: deepLink,
    );
  }

  Future<void> cancelType(NotifType type) async {
    await initialise();
    if (kIsWeb) return;
    for (final id in type.idRange) {
      await _plugin.cancel(id);
    }
  }

  /// Every id this service can own. `cancelAllManaged` is the master-switch
  /// "off" and the timezone-change reset (§2, §6).
  static Iterable<int> get managedIds =>
      NotifType.values.expand((t) => t.idRange);

  Future<void> cancelAllManaged() async {
    await initialise();
    if (kIsWeb) return;
    for (final id in managedIds) {
      await _plugin.cancel(id);
    }
  }

  Future<Set<int>> pendingIds() async {
    if (kIsWeb) return {};
    try {
      await initialise();
      final pending = await _plugin.pendingNotificationRequests();
      return pending.map((r) => r.id).toSet();
    } catch (_) {
      return {};
    }
  }

  /// OS-truth reminder state for the settings master row (§6). "Pending" means
  /// any managed id is genuinely queued, not just the old 1001..1014 block.
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
        return const ReminderStatus(
            available: false, permitted: false, pending: false);
      }
      final permitted = ios != null
          ? (await ios.checkPermissions())?.isEnabled ?? false
          : (await android!.areNotificationsEnabled() ?? false);
      final scheduled = (await _plugin.pendingNotificationRequests())
          .map((r) => r.id)
          .toSet();
      final pending = managedIds.any(scheduled.contains);
      return ReminderStatus(available: true, permitted: permitted, pending: pending);
    } catch (_) {
      return const ReminderStatus(available: false, permitted: false, pending: false);
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(FlutterLocalNotificationsPlugin());
});
