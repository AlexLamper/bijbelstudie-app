import 'dart:convert';
import 'dart:io' show File;
import 'dart:ui' show Color, DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/levensboom/data/tree_image.dart';
import 'daily_slots.dart' show kMaxNotificationsPerDay;
import 'retention_store.dart' show parseSentTag, retentionDayKey;

/// OS-truth state of the local reminders, for the settings master row.
class ReminderStatus {
  const ReminderStatus({
    required this.available,
    required this.permitted,
    required this.pending,
  });

  /// No notifications implementation exists on this platform at all (web,
  /// desktop, or a plugin that failed to register).
  final bool available;

  /// Whether the OS currently permits this app to show notifications.
  final bool permitted;

  /// Whether any managed id is genuinely scheduled with the OS right now,
  /// independent of what preferences say.
  final bool pending;

  /// True only when a reminder will actually fire.
  bool get isActive => available && permitted && pending;
}

/// Every kind of local notification the app can raise.
///
/// The retention plan (`RETENTION_PLAN.md` §4) turns the single "daily reading
/// reminder" into a small ladder of nudges. Each type owns a stable id range so
/// [NotificationService] can cancel and re-schedule one kind without touching
/// the others - the whole scheduler is cancel-then-set, on every foreground.
enum NotifType {
  /// Legacy: the per-cadence daily reminder of builds before the two daily
  /// slots. Never scheduled any more; kept so its ids are still cancelled on
  /// upgrade (a stale 08:00 one-shot would otherwise be a third notification).
  studyReminder,
  streakAtRisk,
  streakLost,
  lessonHalfway,
  weeklyGoal,
  milestone,
  dormant,
  /// Legacy, like [studyReminder]: the verse now rides in the morning slot.
  dailyVerse,
  /// "Je boom mist wat licht" — fired at exactly two days away, before the
  /// Levensboom visibly wilts (TREE_FEATURE_PLAN.md §5.6). No channel of its
  /// own and no toggle of its own: it is a win-back nudge and rides the ones
  /// `dormant` already has.
  treeWilting,
  /// The morning slot (DAILY_HABIT_PLAN.md §1): today's task as the title, the
  /// day's verse as the body. One one-shot per date, 14 days ahead.
  morning,
  /// The evening slot: only on a day the app was not opened. Today's is
  /// cancelled the moment the app opens; tomorrow's and later stay armed.
  evening,
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
    NotifType.treeWilting => 'treeWilting',
    NotifType.morning => 'morning',
    NotifType.evening => 'evening',
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
    NotifType.dormant || NotifType.treeWilting => 'winback',
    NotifType.morning || NotifType.evening => 'daily',
  };

  /// The engagement nudges (§4.4): the ones that carry "Later vandaag" and
  /// that [RetentionStore.cappedSentOn] counts. Every type, these included,
  /// also counts towards the hard daily total in `applyDailyCap`.
  bool get isCapped => switch (this) {
    NotifType.dailyVerse ||
    NotifType.milestone ||
    NotifType.morning ||
    NotifType.evening => false,
    _ => true,
  };

  /// Higher wins when two candidates want the same day (§4.4).
  ///
  /// The two daily slots outrank every other scheduled type: the others only
  /// ever fill a day that still has room under the daily total.
  int get priority => switch (this) {
    NotifType.milestone => 100,
    NotifType.morning => 99,
    NotifType.evening => 98,
    NotifType.streakLost => 90,
    NotifType.lessonHalfway => 80,
    NotifType.streakAtRisk => 70,
    NotifType.studyReminder => 60,
    NotifType.weeklyGoal => 50,
    NotifType.dormant => 40,
    // Below dormant: if the reader is far enough gone for the win-back ladder,
    // that is the message to send, not a note about their tree.
    NotifType.treeWilting => 30,
    NotifType.dailyVerse => 10,
  };

  /// Morning types clamp *later* out of quiet hours; evening types clamp
  /// *earlier* (§4.5).
  bool get isEvening =>
      this == NotifType.streakAtRisk ||
      this == NotifType.weeklyGoal ||
      this == NotifType.evening;

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
    NotifType.treeWilting => const [1220],
    // Slot = the date's epoch day % 14 (`dailySlotFor`), so the id of any
    // date's slot is known without a lookup.
    NotifType.morning => List.generate(14, (i) => 1500 + i),
    NotifType.evening => List.generate(14, (i) => 1520 + i),
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

/// Action ids on the capped (engagement) notifications.
const String kActionLater = 'LATER';
const String kActionOpen = 'OPEN';

/// The one id a "Later vandaag" re-post lives on. Outside every type's range,
/// so a recompute's per-type cancel leaves it alone; the master switch and a
/// finished study day still clear it.
const int kSnoozeNotificationId = 1400;

/// What a notification carries to its tap handler.
///
/// Written as JSON so "Later vandaag" can re-post the same words from a
/// background isolate that has no access to the scheduler. Notifications
/// scheduled by older builds carry the bare route string; [parse] reads both.
class NotificationPayload {
  const NotificationPayload({
    required this.route,
    this.title,
    this.body,
    this.typeId,
  });

  final String route;
  final String? title;
  final String? body;
  final String? typeId;

  static const _home = '/dashboard';

  /// Anything not on the whitelist opens the dashboard.
  static String _safe(String r) => isAllowedNotificationRoute(r) ? r : _home;

  String encode() => jsonEncode({
        'r': route,
        if (title != null) 't': title,
        if (body != null) 'b': body,
        if (typeId != null) 'k': typeId,
      });

  static NotificationPayload parse(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return const NotificationPayload(route: _home);
    if (s.startsWith('{')) {
      try {
        final m = jsonDecode(s);
        if (m is Map) {
          final r = m['r'];
          String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
          return NotificationPayload(
            route: r is String ? _safe(r) : _home,
            title: str(m['t']),
            body: str(m['b']),
            typeId: str(m['k']),
          );
        }
      } catch (_) {}
      return const NotificationPayload(route: _home);
    }
    return NotificationPayload(route: _safe(s));
  }
}

final _allowedRoutes = <RegExp>[
  RegExp(r'^/dashboard$'),
  RegExp(r'^/read$'),
  RegExp(r'^/studies/bijbel-in-een-jaar$'),
  RegExp(r'^/profile/boom$'),
  // A lesson, optionally on a step (the keys are frozen, see StudyStep).
  RegExp(r'^/studie/[A-Za-z0-9%._~-]+/\d+(\?stap=(intro|context|word|depth|quiz|reflection))?$'),
];

/// The routes a notification may open. Server-sent routes
/// (`/notifications/schedule`) are checked against it too, so a bad payload
/// can never deep-link somewhere unexpected; the website mirrors this list in
/// `lib/notificationSchedule.ts` `isWhitelistedRoute`.
bool isAllowedNotificationRoute(String route) =>
    _allowedRoutes.any((re) => re.hasMatch(route));

/// When a "Later vandaag" re-post fires: three hours on, but not past 21:00
/// local nor past half an hour before [quiet] starts, and never sooner than
/// half an hour after the tap. Null when no such moment is left today (or it
/// would land inside quiet hours): the snooze is skipped rather than pushed
/// into the evening or the next day.
DateTime? laterTodayInstant(DateTime now, {QuietHours quiet = QuietHours.defaults}) {
  var cutoffMinutes = 21 * 60;
  // An evening window (it wraps midnight, the default 21:30 -> 07:30 does).
  if (quiet.startMinutes > quiet.endMinutes && quiet.startMinutes - 30 < cutoffMinutes) {
    cutoffMinutes = quiet.startMinutes - 30;
  }
  var fire = now.add(const Duration(hours: 3));
  final cutoff = DateTime(now.year, now.month, now.day, cutoffMinutes ~/ 60, cutoffMinutes % 60);
  if (fire.isAfter(cutoff)) fire = cutoff;
  final soonest = now.add(const Duration(minutes: 30));
  if (fire.isBefore(soonest)) return null;
  if (quiet.contains(fire.hour * 60 + fire.minute)) return null;
  return fire;
}

/// Where the last "Later vandaag" re-post was set to fire (epoch ms). A key
/// of its own rather than a ledger tag: the re-post can be written from the
/// background isolate, which must not rewrite the ledger under the main
/// isolate's `RetentionStore`. The scheduler counts it towards that day.
const String kSnoozeRepostAtKey = 'notif.snoozeRepostAt';

/// Whether a re-post on [fire]'s date stays within the daily total, from the
/// persisted ledger ([rawLog], `retention.sentLog`). The re-post takes the
/// tapped notification's place - it is the same message, moved - so the
/// tapped one ([tappedTypeId]) is not counted twice; everything else that
/// day, fired or armed, is.
@visibleForTesting
bool snoozeFitsDailyCap(
  String? rawLog, {
  required DateTime fire,
  required String tappedTypeId,
  int maxPerDay = kMaxNotificationsPerDay,
}) {
  var tags = const <String>[];
  try {
    final decoded = rawLog == null || rawLog.isEmpty ? null : jsonDecode(rawLog);
    final day = decoded is Map ? decoded[retentionDayKey(fire)] : null;
    if (day is List) tags = day.whereType<String>().toList();
  } catch (_) {}
  var count = tags.length;
  if (tags.any((t) => parseSentTag(t).typeId == tappedTypeId)) count -= 1;
  return count < maxPerDay;
}

/// Re-posts the tapped notification's words at [laterTodayInstant]. Shared by
/// the main isolate and [notificationBackgroundTap] ([reloadPrefs]: a
/// background engine can outlive writes the main isolate made since); never
/// throws. Skipped when no moment is left today outside quiet hours, or
/// when the day is already at its total.
Future<void> snoozeFromResponse(
  FlutterLocalNotificationsPlugin plugin,
  NotificationResponse response, {
  DateTime? now,
  bool reloadPrefs = false,
}) async {
  try {
    final payload = NotificationPayload.parse(response.payload);
    final type =
        NotifType.values.where((t) => t.id == payload.typeId).firstOrNull ??
            NotifType.studyReminder;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (reloadPrefs) await prefs.reload();
    } catch (_) {}
    final quiet = QuietHours(
      startMinutes: prefs?.getInt('notif.quietStartMinutes') ?? QuietHours.defaults.startMinutes,
      endMinutes: prefs?.getInt('notif.quietEndMinutes') ?? QuietHours.defaults.endMinutes,
    );
    final fire = laterTodayInstant(now ?? DateTime.now(), quiet: quiet);
    if (fire == null) return;
    if (!snoozeFitsDailyCap(prefs?.getString('retention.sentLog'),
        fire: fire, tappedTypeId: type.id)) {
      return;
    }
    // An absolute instant in UTC: the background isolate never learns the
    // device zone, and absoluteTime makes the zone irrelevant anyway.
    tzdata.initializeTimeZones();
    await plugin.zonedSchedule(
      kSnoozeNotificationId,
      payload.title ?? 'Even tijd voor het Woord',
      payload.body ?? 'Een paar minuten is genoeg.',
      tz.TZDateTime.from(fire, tz.UTC),
      NotificationService.detailsFor(type, withActions: false),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: NotificationPayload(
        route: payload.route,
        title: payload.title,
        body: payload.body,
        typeId: type.id,
      ).encode(),
    );
    await prefs?.setInt(kSnoozeRepostAtKey, fire.millisecondsSinceEpoch);
  } catch (e, st) {
    debugPrint('[Notifications] snooze failed: $e\n$st');
  }
}

/// Runs in a separate background engine when an action that does not open
/// the app ("Later vandaag") is tapped. Taps that open the app arrive on
/// [NotificationService]'s foreground handler or as launch details instead.
@pragma('vm:entry-point')
Future<void> notificationBackgroundTap(NotificationResponse response) async {
  if (response.actionId != kActionLater) return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await snoozeFromResponse(FlutterLocalNotificationsPlugin(), response, reloadPrefs: true);
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
///
/// One instance per process ([instance]): `main.dart` and every provider read
/// share it, so the plugin is initialised and the launch tap handled once.
class NotificationService {
  @visibleForTesting
  NotificationService(this._plugin);

  static final NotificationService instance =
      NotificationService(FlutterLocalNotificationsPlugin());

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void>? _init;
  bool _tzReady = false;

  static GoRouter? _router;
  static String? _pendingRoute;

  /// Set once the splash has taken (or declined) the cold-start route. Until
  /// then a tap is held for the splash, so it passes the auth check first.
  static bool _launchHandled = false;

  /// Called from `routerProvider` once the router exists.
  static void attachRouter(GoRouter router) {
    _router = router;
  }

  /// The route a notification tap left while the app was starting, if any.
  /// The splash calls this once it has resolved where the reader goes; from
  /// then on taps navigate directly.
  static String? takeLaunchRoute() {
    _launchHandled = true;
    final pending = _pendingRoute;
    _pendingRoute = null;
    return pending;
  }

  static void _route(String? payload) {
    final target = NotificationPayload.parse(payload).route;
    final router = _router;
    if (router != null && _launchHandled) {
      router.go(target);
    } else {
      _pendingRoute = target;
    }
  }

  /// The IANA zone name last applied, e.g. `Europe/Amsterdam`. Null until
  /// [initialise] has run on a mobile platform.
  String? localZoneName;

  /// Idempotent and safe to call concurrently: every caller awaits the same
  /// run. A failed run is forgotten so the next call retries.
  Future<void> initialise() {
    if (kIsWeb) return Future.value();
    return _init ??= _initialise().catchError((Object e, StackTrace st) {
      _init = null;
      debugPrint('[Notifications] initialise failed: $e\n$st');
      throw e;
    });
  }

  Future<void> _initialise() async {
    await _ensureTimezone();

    const androidInit = AndroidInitializationSettings(kSmallIcon);
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _engagementCategory,
          actions: [
            DarwinNotificationAction.plain(kActionLater, 'Later vandaag'),
            DarwinNotificationAction.plain(
              kActionOpen,
              'Openen',
              options: const {DarwinNotificationActionOption.foreground},
            ),
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

    // A cold start from a notification tap: held for the splash (see
    // [takeLaunchRoute]).
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response?.actionId == kActionLater) {
        await snoozeFromResponse(_plugin, response!);
      } else {
        _route(response?.payload);
      }
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
    } catch (e) {
      // Keep whatever `timezone` defaults to (UTC). Better a slightly wrong
      // fire time than a crash at startup.
      debugPrint('[Notifications] timezone lookup failed: $e');
      localZoneName = tz.local.name;
    }
    _tzReady = true;
  }

  void _onForegroundTap(NotificationResponse response) {
    if (response.actionId == kActionLater) {
      snoozeFromResponse(_plugin, response);
      return;
    }
    _route(response.payload);
  }

  /// Monochrome status-bar glyph (`res/drawable/ic_stat_notification.xml`).
  /// Android masks the small icon to its alpha, so the full-colour launcher
  /// icon rendered as a grey blob.
  static const kSmallIcon = 'ic_stat_notification';
  static const _brandTeal = Color(0xFF0D9488);

  static const _engagementCategory = 'engagement';

  static final _channels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      'daily',
      'Ochtend en avond',
      description: 'Je taak van vandaag en de tekst van de dag',
      importance: Importance.defaultImportance,
    ),
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
    } catch (e) {
      debugPrint('[Notifications] permission check failed: $e');
    }
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

  /// [images], when given, put the reader's Levensboom on the notification:
  /// the scene as Android's big picture and the iOS attachment, the portrait as
  /// Android's large icon. Rendered on-device by `tree_image.dart`.
  ///
  /// [iosAttachmentPath] must be a file used by this one notification only:
  /// iOS moves an attachment into its own store when it is scheduled.
  static NotificationDetails detailsFor(
    NotifType type, {
    bool withActions = true,
    TreeImageFiles? images,
    String? iosAttachmentPath,
  }) {
    final android = AndroidNotificationDetails(
      type.channelId,
      _channels
          .firstWhere((c) => c.id == type.channelId, orElse: () => _channels.first)
          .name,
      icon: kSmallIcon,
      color: _brandTeal,
      importance:
          type == NotifType.milestone ? Importance.high : Importance.defaultImportance,
      priority:
          type == NotifType.milestone ? Priority.high : Priority.defaultPriority,
      largeIcon: images == null ? null : FilePathAndroidBitmap(images.iconPath),
      styleInformation: images == null
          ? null
          : BigPictureStyleInformation(
              FilePathAndroidBitmap(images.scenePath),
              hideExpandedLargeIcon: true,
            ),
      actions: withActions && type.isCapped
          ? const [
              AndroidNotificationAction(kActionLater, 'Later vandaag'),
              // Without showsUserInterface the tap goes to a background
              // isolate and the app never opens.
              AndroidNotificationAction(kActionOpen, 'Openen',
                  showsUserInterface: true),
            ]
          : null,
    );
    final ios = DarwinNotificationDetails(
      categoryIdentifier: withActions && type.isCapped ? _engagementCategory : null,
      attachments: iosAttachmentPath == null
          ? null
          : [DarwinNotificationAttachment(iosAttachmentPath)],
    );
    return NotificationDetails(android: android, iOS: ios);
  }

  /// A private copy of [images]' scene for one iOS notification, or null (not
  /// iOS, no image, or the copy failed - the notification then goes without).
  String? _iosAttachmentCopy(TreeImageFiles? images, int id) {
    if (images == null || defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final src = File(images.scenePath);
      if (!src.existsSync()) return null;
      final name = src.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final ext = dot > 0 ? name.substring(dot) : '.png';
      // Same folder as the art, so `NotificationArt.sweep` clears leftovers.
      final dest =
          '${src.parent.path}/att-$id-${DateTime.now().microsecondsSinceEpoch}$ext';
      src.copySync(dest);
      return dest;
    } catch (e) {
      debugPrint('[Notifications] attachment copy failed: $e');
      return null;
    }
  }

  String _payload(NotifType type, RenderedVariant variant, String deepLink) =>
      NotificationPayload(
        route: deepLink,
        title: variant.title,
        body: variant.body,
        typeId: type.id,
      ).encode();

  /// Schedules one one-shot for [type] at [when] carrying [variant] and a tap
  /// [deepLink]. [slot] disambiguates types whose id range holds several ids
  /// (studyReminder, dailyVerse, dormant); it indexes into [NotifTypeX.idRange].
  Future<void> scheduleOneShot(
    NotifType type,
    tz.TZDateTime when,
    RenderedVariant variant, {
    required String deepLink,
    int slot = 0,
    TreeImageFiles? images,
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
      detailsFor(type,
          images: images, iosAttachmentPath: _iosAttachmentCopy(images, id)),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _payload(type, variant, deepLink),
    );
  }

  /// Fires [type] right now (milestone celebration when backgrounded, the
  /// "weekdoel gehaald" ping the moment the goal is met).
  Future<void> showNow(
    NotifType type,
    RenderedVariant variant, {
    required String deepLink,
    int slot = 0,
    TreeImageFiles? images,
  }) async {
    await initialise();
    if (kIsWeb) return;
    final ids = type.idRange;
    final id = ids[slot.clamp(0, ids.length - 1)];
    await _plugin.show(
      id,
      variant.title,
      variant.body,
      detailsFor(type,
          withActions: false,
          images: images,
          iosAttachmentPath: _iosAttachmentCopy(images, id)),
      payload: _payload(type, variant, deepLink),
    );
  }

  /// Drops one date's evening slot (the app was opened that day). Cheap and
  /// independent of the scheduler, so it runs the moment the app comes up.
  Future<void> cancelEveningOn(DateTime localDate) async {
    await initialise();
    if (kIsWeb) return;
    final ids = NotifType.evening.idRange;
    final epochDay = DateTime.utc(localDate.year, localDate.month, localDate.day)
            .millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    await _plugin.cancel(ids[epochDay % ids.length]);
  }

  Future<void> cancelType(NotifType type) async {
    await initialise();
    if (kIsWeb) return;
    for (final id in type.idRange) {
      await _plugin.cancel(id);
    }
  }

  /// Drops a pending "Later vandaag" re-post (the day's study is done).
  Future<void> cancelSnooze() async {
    await initialise();
    if (kIsWeb) return;
    await _plugin.cancel(kSnoozeNotificationId);
    await _forgetSnooze();
  }

  /// Where the pending (or last) "Later vandaag" re-post fires, if any.
  static Future<DateTime?> snoozeRepostAt() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(kSnoozeRepostAtKey);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _forgetSnooze() async {
    try {
      await (await SharedPreferences.getInstance()).remove(kSnoozeRepostAtKey);
    } catch (_) {}
  }

  /// Every id this service can own. `cancelAllManaged` is the master-switch
  /// "off" and the timezone-change reset (§2, §6).
  static Iterable<int> get managedIds => [
        ...NotifType.values.expand((t) => t.idRange),
        kSnoozeNotificationId,
      ];

  Future<void> cancelAllManaged() async {
    await initialise();
    if (kIsWeb) return;
    for (final id in managedIds) {
      await _plugin.cancel(id);
    }
    await _forgetSnooze();
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
  return NotificationService.instance;
});
