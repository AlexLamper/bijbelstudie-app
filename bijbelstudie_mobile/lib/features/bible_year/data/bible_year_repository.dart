import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';
import 'bible_year_models.dart';

final bibleYearRepositoryProvider = Provider<BibleYearRepository>((ref) {
  return BibleYearRepository(ref.watch(apiClientProvider));
});

enum BibleYearErrorKind { unauthorized, conflict, notFound, badRequest, server, network }

/// A "Bijbel in een jaar" call that did not land. 401 (signed out) and 409 (a
/// plan already runs) are their own kinds so the UI can handle them gently -
/// the same split the website's `lib/bibleYear/client.ts` makes.
class BibleYearException implements Exception {
  const BibleYearException(this.kind, this.message, {this.status = 0});

  final BibleYearErrorKind kind;
  final String message;
  final int status;

  bool get isUnauthorized => kind == BibleYearErrorKind.unauthorized;
  bool get isConflict => kind == BibleYearErrorKind.conflict;

  @override
  String toString() => message;
}

/// The website's wording (`MESSAGES` in `lib/bibleYear/client.ts`).
const Map<BibleYearErrorKind, String> kBibleYearErrorMessages = {
  BibleYearErrorKind.unauthorized: 'Log in om je leesplan te bewaren.',
  BibleYearErrorKind.conflict: 'Je hebt al een leesplan lopen.',
  BibleYearErrorKind.notFound: 'Er is geen leesplan gevonden.',
  BibleYearErrorKind.badRequest: 'Dat lukte niet. Probeer het zo nog eens.',
  BibleYearErrorKind.server: 'Dat lukte niet. Probeer het zo nog eens.',
  BibleYearErrorKind.network: 'Geen verbinding. Probeer het zo nog eens.',
};

/// Maps a failed request to a [BibleYearException]. Public so the error
/// mapping is unit tested without a server.
BibleYearException bibleYearErrorFor(DioException e) {
  final response = e.response;
  final status = response?.statusCode;
  if (response == null || status == null) {
    return BibleYearException(
      BibleYearErrorKind.network,
      kBibleYearErrorMessages[BibleYearErrorKind.network]!,
    );
  }
  final kind = switch (status) {
    401 || 403 => BibleYearErrorKind.unauthorized,
    409 => BibleYearErrorKind.conflict,
    404 => BibleYearErrorKind.notFound,
    400 => BibleYearErrorKind.badRequest,
    _ => BibleYearErrorKind.server,
  };
  var message = kBibleYearErrorMessages[kind]!;
  // A 400 may carry a Dutch reason worth showing as is ("Kies een geldige datum.").
  if (kind == BibleYearErrorKind.badRequest) {
    final body = response.data;
    if (body is Map) {
      final text = body['message'] ?? body['error'];
      if (text is String && text.trim().isNotEmpty) message = text;
    }
  }
  return BibleYearException(kind, message, status: status);
}

/// Returns the device's IANA zone ("Europe/Amsterdam").
typedef TimeZoneLookup = Future<String?> Function();

Future<String?> _deviceTimeZone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    final name = info.identifier;
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}

/// `/api/v1/bible-year/**`. Every method throws [BibleYearException] on
/// failure; the controller decides what the reader sees.
class BibleYearRepository {
  BibleYearRepository(this._apiClient, {TimeZoneLookup? timeZone})
    : _timeZone = timeZone ?? _deviceTimeZone;

  final ApiClient? _apiClient;
  final TimeZoneLookup _timeZone;

  static const _base = '/bible-year';

  Dio get _dio => _apiClient!.dio;

  /// The device's zone, sent with a start so "vandaag" is the reader's day.
  Future<String> deviceTimeZone() async => (await _timeZone()) ?? 'Europe/Amsterdam';

  /// GET - catalogue, tracks, enrollment and today.
  Future<BibleYearState> fetchState() async {
    // Preview runs on canned data with no account behind it.
    if (PreviewConfig.enabled) return const BibleYearState();
    final data = await _call(() => _dio.get(_base));
    return BibleYearState.fromJson(data);
  }

  /// POST - throws a conflict when a plan is already active.
  Future<Map<String, dynamic>> start(BibleYearStartBody body) =>
      _call(() => _dio.post(_base, data: body.toJson()));

  /// PATCH shift - moves the schedule forward by behindDays.
  Future<Map<String, dynamic>> shift() =>
      _call(() => _dio.patch(_base, data: {'action': 'shift'}));

  /// PATCH stop - status abandoned, document kept.
  Future<Map<String, dynamic>> stop() =>
      _call(() => _dio.patch(_base, data: {'action': 'stop'}));

  /// PATCH restart - abandons the current plan and starts a new one.
  Future<Map<String, dynamic>> restart(BibleYearStartBody body) =>
      _call(() => _dio.patch(_base, data: {'action': 'restart', ...body.toJson()}));

  /// POST mark - chapters read or unread.
  Future<Map<String, dynamic>> markRefs(List<BibleYearChapterKey> refs, bool read) => _call(
    () => _dio.post(
      '$_base/mark',
      data: {
        'refs': [for (final r in refs) r.toJson()],
        'read': read,
      },
    ),
  );

  /// POST mark - a whole day read or unread.
  Future<Map<String, dynamic>> markDay(int day, bool read) =>
      _call(() => _dio.post('$_base/mark', data: {'day': day, 'read': read}));

  /// GET schedule - static and cacheable, no account needed.
  Future<BibleYearSchedule> schedule(
    BibleYearPlanKey plan,
    BibleYearTrackKey track, {
    int? version,
  }) async {
    final data = await _call(
      () => _dio.get(
        '$_base/schedule',
        queryParameters: {
          'plan': plan.id,
          'track': track.id,
          // `v` per the plan, `version` as the website's client sends it.
          if (version != null) 'v': '$version',
          if (version != null) 'version': '$version',
        },
      ),
    );
    return BibleYearSchedule.fromJson(data);
  }

  Future<Map<String, dynamic>> _call(Future<Response<dynamic>> Function() run) async {
    try {
      final response = await run();
      final data = response.data;
      if (data is Map) return data.cast<String, dynamic>();
      throw BibleYearException(
        BibleYearErrorKind.server,
        kBibleYearErrorMessages[BibleYearErrorKind.server]!,
        status: response.statusCode ?? 0,
      );
    } on DioException catch (e) {
      throw bibleYearErrorFor(e);
    }
  }
}
