import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/present/auth_controller.dart';
import '../config/preview_config.dart';
import 'notification_service.dart' show isAllowedNotificationRoute;

/// What a daily notification is about. Mirrors `NotificationKind` in the
/// website's `lib/notificationScheduleTypes.ts`, in its priority order:
/// Bijbel in een jaar > study > last chapter read > just the verse. [other]
/// is any kind a newer server sends that this build does not know; it is
/// shown as-is (no content toggle filters it).
enum ScheduleKind { bibleYear, study, chapter, verse, other }

ScheduleKind scheduleKindFrom(Object? raw) => switch (raw) {
      'bibleYear' => ScheduleKind.bibleYear,
      'study' => ScheduleKind.study,
      'chapter' => ScheduleKind.chapter,
      'verse' => ScheduleKind.verse,
      _ => ScheduleKind.other,
    };

String _str(Object? v) => v is String ? v.trim() : '';

/// One notification's words and where a tap goes.
class ScheduleContent {
  const ScheduleContent({
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
  });

  final ScheduleKind kind;
  final String title;
  final String body;

  /// Always a whitelisted app route ([isAllowedNotificationRoute]).
  final String route;

  /// Null when there is nothing to show (no title and no body). A route the
  /// app does not accept falls back to the dashboard rather than dropping the
  /// words.
  static ScheduleContent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final title = _str(raw['title']);
    final body = _str(raw['body']);
    if (title.isEmpty || body.isEmpty) return null;
    final route = _str(raw['route']);
    return ScheduleContent(
      kind: scheduleKindFrom(raw['kind']),
      title: title,
      body: body,
      route: isAllowedNotificationRoute(route) ? route : '/dashboard',
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        'body': body,
        'route': route,
      };
}

class ScheduleVerse {
  const ScheduleVerse({required this.text, required this.reference, this.translation = ''});

  final String text;
  final String reference;
  final String translation;

  static ScheduleVerse? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = _str(raw['text']);
    final reference = _str(raw['reference']);
    if (text.isEmpty || reference.isEmpty) return null;
    return ScheduleVerse(text: text, reference: reference, translation: _str(raw['translation']));
  }

  Map<String, dynamic> toJson() =>
      {'text': text, 'reference': reference, 'translation': translation};
}

final _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// One local calendar day of the schedule.
class ScheduleDay {
  const ScheduleDay({required this.date, this.verse, this.morning, this.evening});

  /// `yyyy-MM-dd` in the zone the schedule was asked for.
  final String date;
  final ScheduleVerse? verse;
  final ScheduleContent? morning;
  final ScheduleContent? evening;

  static ScheduleDay? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final date = _str(raw['date']);
    if (!_dateKey.hasMatch(date)) return null;
    final morning = ScheduleContent.tryParse(raw['morning']);
    final evening = ScheduleContent.tryParse(raw['evening']);
    if (morning == null && evening == null) return null;
    return ScheduleDay(
      date: date,
      verse: ScheduleVerse.tryParse(raw['verse']),
      morning: morning,
      evening: evening,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'verse': verse?.toJson(),
        if (morning != null) 'morning': morning!.toJson(),
        if (evening != null) 'evening': evening!.toJson(),
      };
}

/// `GET /api/v1/notifications/schedule` (contract:
/// `lib/notificationScheduleTypes.ts` in the website repo).
class NotificationSchedule {
  const NotificationSchedule({
    required this.timeZone,
    required this.days,
    this.generatedAt,
    this.fetchedAt,
    this.requestedTimeZone = '',
    this.exclude = '',
  });

  /// The zone the server says it built the days in.
  final String timeZone;
  final List<ScheduleDay> days;
  final DateTime? generatedAt;

  /// When this device last received it (set by the repository, not the server).
  final DateTime? fetchedAt;

  /// The `tz` this device asked for. Freshness compares this, not the
  /// server's echo: a server that normalises or falls back on the zone would
  /// otherwise never match and refetch on every run. Set by the repository.
  final String requestedTimeZone;

  /// The `exclude` this device asked for (switched-off content kinds, see
  /// `DailyContentPrefs.excludeParam`); a toggle change makes the cache stale.
  final String exclude;

  NotificationSchedule withRequest({
    required String timeZone,
    required String exclude,
    DateTime? fetchedAt,
  }) =>
      NotificationSchedule(
        timeZone: this.timeZone,
        days: days,
        generatedAt: generatedAt,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        requestedTimeZone: timeZone,
        exclude: exclude,
      );

  ScheduleDay? dayFor(String dateKey) {
    for (final d in days) {
      if (d.date == dateKey) return d;
    }
    return null;
  }

  /// Tolerant: unknown fields are ignored, a malformed day is dropped, and a
  /// response without a single usable day is null (so the caller falls back
  /// instead of scheduling blanks).
  static NotificationSchedule? tryParse(Object? raw, {DateTime? fetchedAt}) {
    if (raw is! Map) return null;
    final list = raw['days'];
    if (list is! List) return null;
    final days = <ScheduleDay>[];
    final seen = <String>{};
    for (final item in list) {
      final day = ScheduleDay.tryParse(item);
      if (day != null && seen.add(day.date)) days.add(day);
    }
    if (days.isEmpty) return null;
    final fetched = fetchedAt ?? DateTime.tryParse(_str(raw['fetchedAt']));
    return NotificationSchedule(
      timeZone: _str(raw['timeZone']),
      days: days,
      generatedAt: DateTime.tryParse(_str(raw['generatedAt'])),
      fetchedAt: fetched,
      requestedTimeZone: _str(raw['requestedTz']),
      exclude: _str(raw['exclude']),
    );
  }

  Map<String, dynamic> toJson() => {
        'timeZone': timeZone,
        'generatedAt': generatedAt?.toIso8601String(),
        'fetchedAt': fetchedAt?.toIso8601String(),
        'requestedTz': requestedTimeZone,
        'exclude': exclude,
        'days': [for (final d in days) d.toJson()],
      };
}

/// Fetches the schedule and keeps the last good one on the device, so the
/// notifications can be (re)written offline - after a settings change, say.
class NotificationScheduleRepository {
  NotificationScheduleRepository(this._dio);

  final Dio? _dio;

  static const cacheKey = 'notif.schedule.v1';

  /// A fetch younger than this is reused for launch/resume/settings runs; a
  /// progress change forces a new one.
  static const freshFor = Duration(minutes: 20);

  Future<NotificationSchedule?> loadCached() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(cacheKey);
      if (raw == null || raw.isEmpty) return null;
      return NotificationSchedule.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Drops the cached schedule (sign-out: its words are the previous
  /// reader's plan and study).
  static Future<void> clearCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(cacheKey);
    } catch (_) {}
  }

  Future<void> _save(NotificationSchedule schedule) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(cacheKey, jsonEncode(schedule.toJson()));
    } catch (_) {}
  }

  /// The device's IANA zone; Europe/Amsterdam when the plugin cannot tell.
  static Future<String> deviceTimeZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (info.identifier.isNotEmpty) return info.identifier;
    } catch (_) {}
    return 'Europe/Amsterdam';
  }

  /// The freshest schedule available: the cache while it is fresh (and asked
  /// for the same zone and [exclude]), otherwise the network, otherwise the
  /// cache however old. Never throws; null only when nothing was ever fetched.
  ///
  /// [exclude] is the switched-off content kinds (`bibleYear,study,verse`);
  /// the server lets those fall through to the next task and leaves the
  /// verse out, so the words arrive already matching the toggles.
  Future<NotificationSchedule?> load({
    String? timeZone,
    bool force = false,
    int days = 14,
    String exclude = '',
    DateTime? now,
  }) async {
    final cached = await loadCached();
    final zone = timeZone ?? await deviceTimeZone();
    final at = now ?? DateTime.now();
    final fetched = cached?.fetchedAt;
    final fresh = !force &&
        cached != null &&
        fetched != null &&
        cached.requestedTimeZone == zone &&
        cached.exclude == exclude &&
        at.difference(fetched) >= Duration.zero &&
        at.difference(fetched) < freshFor &&
        fetched.day == at.day;
    if (fresh) return cached;

    final dio = _dio;
    if (dio == null || PreviewConfig.enabled) return cached;
    try {
      final response = await dio
          .get<Object?>(
            '/notifications/schedule',
            queryParameters: {
              'days': days,
              'tz': zone,
              if (exclude.isNotEmpty) 'exclude': exclude,
            },
          )
          .timeout(const Duration(seconds: 10));
      final parsed = NotificationSchedule.tryParse(response.data, fetchedAt: at)
          ?.withRequest(timeZone: zone, exclude: exclude, fetchedAt: at);
      if (parsed == null) return cached;
      await _save(parsed);
      return parsed;
    } catch (e) {
      debugPrint('[Notifications] schedule fetch failed, using cache: $e');
      return cached;
    }
  }
}

final notificationScheduleRepositoryProvider = Provider<NotificationScheduleRepository>((ref) {
  return NotificationScheduleRepository(ref.watch(apiClientProvider).dio);
});
