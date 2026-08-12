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
          final token = await _storage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode != 401 || _isRefreshCall(e.requestOptions)) {
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

  bool _isRefreshCall(RequestOptions options) => options.path.contains('/auth/refresh');

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
