import 'dart:async';

import 'package:dio/dio.dart';
import '../../features/auth/data/auth_local_storage.dart';
import '../config/app_config.dart';

/// Called when the refresh token is dead and the user has to log in again.
typedef SessionExpiredCallback = void Function();

class ApiClient {
  late final Dio dio;

  /// A second Dio without the auth interceptor. The refresh call must not be
  /// able to trigger its own refresh — that is how you get an infinite loop.
  late final Dio _refreshDio;

  final AuthLocalStorage _storage;

  SessionExpiredCallback? onSessionExpired;

  /// Single-flight guard. A screen that fires five requests at once gets five
  /// 401s; without this they would each start a refresh, and because refresh
  /// tokens rotate, four of those five would present an already-rotated token
  /// and trip the server's replay detection — logging the user out for doing
  /// nothing wrong.
  Future<String?>? _refreshInFlight;

  static String get baseUrl => AppConfig.effectiveApiBaseUrl;

  ApiClient(this._storage) {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    );

    dio = Dio(options);
    _refreshDio = Dio(options);

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Credential endpoints establish a session; they never act on one.
          // Sending a stale bearer token with a login is at best noise, and it
          // is what made the 401 below ambiguous in the first place.
          if (_isPublicAuthCall(options)) return handler.next(options);

          final token = await _storage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode != 401 || _isPublicAuthCall(e.requestOptions)) {
            return handler.next(e);
          }

          final token = await _refreshAccessToken();
          if (token == null) {
            await _storage.clear();
            onSessionExpired?.call();
            return handler.next(e);
          }

          // Retry the original request exactly once with the new token.
          try {
            final retried = await dio.fetch(
              e.requestOptions..headers['Authorization'] = 'Bearer $token',
            );
            return handler.resolve(retried);
          } on DioException catch (retryError) {
            return handler.next(retryError);
          }
        },
      ),
    );
  }

  /// The endpoints that *establish* a session rather than consume one.
  ///
  /// A 401 from any of these means "those credentials are wrong", not "your
  /// session expired", and the difference is not cosmetic. Only `/auth/refresh`
  /// used to be excluded here, so a mistyped password on the login screen fell
  /// straight into the refresh branch below: the client spent the device's
  /// refresh token trying to rescue a session that was never in trouble, and
  /// when that failed — as it does on any device whose last session had already
  /// ended — it wiped secure storage and fired [onSessionExpired], which sends
  /// the router to `/login?expired=1`.
  ///
  /// The visible result was a login that "does nothing": the typed credentials
  /// were discarded along with the screen, and the real message
  /// ("E-mailadres of wachtwoord klopt niet") was replaced by "Je sessie is
  /// verlopen" for a user who had not been signed in at all. It also cost two
  /// requests per attempt, so the server's 10-per-15-minutes login limit was
  /// reached in five tries.
  ///
  /// Registration never showed any of this, which is what made it look like a
  /// login-only bug: `/auth/register` answers 201 or 409, never 401.
  static bool _isPublicAuthCall(RequestOptions options) {
    const publicAuthPaths = [
      '/auth/login',
      '/auth/register',
      '/auth/google',
      '/auth/apple',
      '/auth/refresh',
    ];
    return publicAuthPaths.any(options.path.contains);
  }

  Future<String?> _refreshAccessToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final response = await _refreshDio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      final access = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (access == null || access.isEmpty) return null;

      await _storage.saveToken(access);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await _storage.saveRefreshToken(newRefresh);
      }
      return access;
    } catch (_) {
      // Expired, revoked, or replayed — all mean "log in again".
      return null;
    }
  }
}
