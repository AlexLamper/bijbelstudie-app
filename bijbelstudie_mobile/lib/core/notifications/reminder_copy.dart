import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One day's reminder text, already personalised by the server.
class ReminderVariant {
  const ReminderVariant({
    required this.variantId,
    required this.title,
    required this.body,
    required this.deepLink,
  });

  final String variantId;
  final String title;
  final String body;

  /// Web-shaped path the notification opens; the router maps it to a screen.
  final String deepLink;

  factory ReminderVariant.fromJson(Map<String, dynamic> json) => ReminderVariant(
    variantId: json['variantId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    deepLink: json['deepLink'] as String? ?? '/dashboard',
  );

  Map<String, dynamic> toJson() => {
    'variantId': variantId,
    'title': title,
    'body': body,
    'deepLink': deepLink,
  };

  bool get isUsable => title.trim().isNotEmpty && body.trim().isNotEmpty;
}

/// Where the daily reminder's words come from.
///
/// The reminder is an OS alarm: it fires with no network and with none of our
/// code running, so every day's text has to be decided in advance. This fetches
/// a batch from `GET /api/v1/notifications/copy`, caches it, and falls back to
/// a bundled set when there has never been a successful fetch.
///
/// Fetching rather than bundling is what lets the wording be improved for
/// everyone without an app release - which matters, because the reminder used
/// to be one hardcoded string repeated forever, and a string seen forty times
/// stops being read.
class ReminderCopySource {
  ReminderCopySource(this._dio);

  /// A source that never touches the network: cache, then bundle.
  ///
  /// Used at cold start, where re-arming the alarm must not wait on a request
  /// - a launch blocked on a slow connection is a worse bug than a reminder
  /// whose wording is a few days old.
  const ReminderCopySource.cacheOnly() : _dio = null;

  final Dio? _dio;

  static const _cacheKey = 'reminder_copy_batch_v1';
  static const _cacheDateKey = 'reminder_copy_fetched_on_v1';

  /// How many days of reminders one batch covers. The pool holds sixteen
  /// variants, so a fortnight never repeats itself.
  static const int batchDays = 14;

  /// Refetch once the batch is down to its last few days, so a reader who
  /// opens the app occasionally never runs off the end of it.
  static const int refetchWhenRemainingBelow = 5;

  /// Used until a fetch has ever succeeded - a first run offline, or a build
  /// talking to an older server. Deliberately token-free: with no reading
  /// history there is no book to name, and a reminder that says "{boek}" is
  /// worse than a plain one.
  static const List<ReminderVariant> bundledFallback = [
    ReminderVariant(
      variantId: 'd03',
      title: 'Even stil bij het Woord',
      body: 'Je vaste moment. Eén hoofdstuk, meer hoeft niet.',
      deepLink: '/dashboard',
    ),
    ReminderVariant(
      variantId: 'd07',
      title: 'Tijd voor een hoofdstuk',
      body: 'Kort lezen telt ook. Begin waar je gebleven was.',
      deepLink: '/dashboard',
    ),
    ReminderVariant(
      variantId: 'd10',
      title: 'Je Bijbel ligt klaar',
      body: 'Geen haast. Lees zo ver als je komt.',
      deepLink: '/dashboard',
    ),
    ReminderVariant(
      variantId: 'd16',
      title: 'Eén hoofdstuk',
      body: 'Meer vraagt vandaag niemand van je.',
      deepLink: '/dashboard',
    ),
  ];

  /// A batch for the next [batchDays] days, from the server when it can be
  /// reached and from cache or the bundle when it cannot.
  ///
  /// Never throws. A reminder that fires with slightly stale words is fine; a
  /// reminder that fails to schedule because the network was down is not.
  Future<List<ReminderVariant>> load({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = _readCache(prefs);
      if (cached != null && !_isStale(prefs)) return cached;
    }

    final dio = _dio;
    if (dio == null) return _readCache(prefs) ?? bundledFallback;

    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/api/v1/notifications/copy',
        queryParameters: {'type': 'daily_reading', 'days': batchDays},
      );

      final raw = (res.data?['variants'] as List?) ?? const [];
      final variants = raw
          .whereType<Map<String, dynamic>>()
          .map(ReminderVariant.fromJson)
          .where((v) => v.isUsable)
          .toList(growable: false);

      if (variants.isNotEmpty) {
        await _writeCache(prefs, variants);
        return variants;
      }
    } catch (_) {
      // Offline, signed out, or an older server. Any cached or bundled copy is
      // a better outcome than no reminder.
    }

    return _readCache(prefs) ?? bundledFallback;
  }

  /// Whether the stored batch is old enough to be worth replacing.
  ///
  /// Exposed so a caller can avoid tearing down and re-arming fourteen OS
  /// notifications on every app open when nothing would change.
  Future<bool> needsRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    return _readCache(prefs) == null || _isStale(prefs);
  }

  List<ReminderVariant>? _readCache(SharedPreferences prefs) {
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as List;
      final variants = decoded
          .whereType<Map<String, dynamic>>()
          .map(ReminderVariant.fromJson)
          .where((v) => v.isUsable)
          .toList(growable: false);
      return variants.isEmpty ? null : variants;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    SharedPreferences prefs,
    List<ReminderVariant> variants,
  ) async {
    await prefs.setString(
      _cacheKey,
      jsonEncode(variants.map((v) => v.toJson()).toList()),
    );
    await prefs.setString(_cacheDateKey, _todayKey());
  }

  /// A batch is stale once enough of it has been used up that the tail is in
  /// sight. Measured in days since it was fetched, because that is exactly how
  /// the scheduler consumes it - one variant per day.
  bool _isStale(SharedPreferences prefs) {
    final fetchedOn = prefs.getString(_cacheDateKey);
    if (fetchedOn == null) return true;
    final fetched = DateTime.tryParse(fetchedOn);
    if (fetched == null) return true;

    final daysUsed = DateTime.now().difference(fetched).inDays;
    return daysUsed >= batchDays - refetchWhenRemainingBelow;
  }

  static String _todayKey() => DateTime.now().toIso8601String().split('T').first;
}
