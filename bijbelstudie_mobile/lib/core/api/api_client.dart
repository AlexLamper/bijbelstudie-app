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
  Future<RefreshResult>? _refreshInFlight;

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

          RefreshResult result;
          try {
            result = await _refreshAccessToken();
          } on _TransientRefreshFailure {
            // The refresh endpoint itself couldn't be reached, or answered
            // with something other than a definitive rejection (timeout,
            // offline, DNS failure, 5xx). That says nothing about whether the
            // refresh token is still good, so keep the session and just let
            // the original error surface — the next request retries refresh
            // from scratch instead of the device being logged out for being
            // briefly offline.
            return handler.next(e);
          }

          if (result.accessToken == null) {
            await _storage.clear();
            onSessionExpired?.call();
            return handler.next(e);
          }
          final token = result.accessToken!;

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

  Future<RefreshResult> _refreshAccessToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<RefreshResult> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      // Nothing to refresh with — this is a definitive "log in again", not a
      // transient failure.
      return const RefreshResult(null);
    }

    try {
      final response = await _refreshDio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      final access = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (access == null || access.isEmpty) {
        // 2xx with a malformed body isn't a rejection either, but there is
        // nothing usable to retry with, so treat it as transient rather than
        // wiping the session on what is most likely a server bug.
        throw const _TransientRefreshFailure();
      }

      await _storage.saveToken(access);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await _storage.saveRefreshToken(newRefresh);
      }
      return RefreshResult(access);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Only a definitive rejection from the refresh endpoint itself means
      // "this refresh token is dead, log in again". Everything else —
      // timeouts, no connection, DNS failure, 5xx — is transient: the device
      // may simply be offline, and logging the user out for that is the
      // exact bug this guards against.
      if (status == 401 || status == 403) {
        return const RefreshResult(null);
      }
      throw const _TransientRefreshFailure();
    } on _TransientRefreshFailure {
      rethrow;
    } catch (_) {
      // Anything else unexpected (JSON parse failure, etc.) is also treated
      // as transient — never clear credentials on ambiguity.
      throw const _TransientRefreshFailure();
    }
  }
}

/// Outcome of a refresh attempt that reached a definitive answer: either a
/// fresh access token, or `null` meaning the refresh token is confirmed dead
/// (an explicit 401/403 from `/auth/refresh`, or none was stored at all).
class RefreshResult {
  final String? accessToken;
  const RefreshResult(this.accessToken);
}

/// Thrown when refresh could not reach a definitive answer (network error,
/// timeout, 5xx, malformed response). The caller must not treat this as a
/// reason to sign the user out.
class _TransientRefreshFailure implements Exception {
  const _TransientRefreshFailure();
}
