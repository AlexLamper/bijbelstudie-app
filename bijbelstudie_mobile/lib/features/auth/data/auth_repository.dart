import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../domain/user.dart';
import 'auth_local_storage.dart';
import '../../../core/api/api_client.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final AuthLocalStorage _localStorage;

  AuthRepository(this._apiClient, this._localStorage);

  Future<User?> login(String email, String password) async {
    return _post('/auth/login', {
      'email': email,
      'password': password,
      ..._deviceInfo(),
    }, 'Inloggen mislukt');
  }

  Future<User?> register(String name, String email, String password) async {
    return _post('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
      ..._deviceInfo(),
    }, 'Registreren mislukt');
  }

  Future<User?> loginWithApple({
    required String identityToken,
    required String authorizationCode,
    String? givenName,
    String? familyName,
    String? email,
  }) async {
    return _post('/auth/apple', {
      'identityToken': identityToken,
      'authorizationCode': authorizationCode,
      if (givenName != null) 'givenName': givenName,
      if (familyName != null) 'familyName': familyName,
      if (email != null) 'email': email,
      ..._deviceInfo(),
    }, 'Apple-login mislukt');
  }

  Future<User?> loginWithGoogle(String idToken) async {
    return _post('/auth/google', {
      'idToken': idToken,
      ..._deviceInfo(),
    }, 'Google-login mislukt');
  }

  /// Revokes the refresh token server-side, then clears local storage.
  ///
  /// The local clear happens even if the network call fails — a logout that
  /// leaves a usable token on the device is worse than an orphaned row on the
  /// server, which expires on its own.
  Future<void> logout() async {
    final refreshToken = await _localStorage.getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _apiClient.dio.post('/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {
        // Offline logout still has to work.
      }
    }
    await _localStorage.clear();
  }

  Future<User?> _post(String path, Map<String, dynamic> data, String fallbackMessage) async {
    try {
      final response = await _apiClient.dio.post(path, data: data);
      return _processAuthResponse(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['message'] is String) {
        throw Exception(body['message']);
      }
      if (body is Map && body['error'] is String) {
        throw Exception(body['error']);
      }
      throw Exception('$fallbackMessage: ${e.message}');
    }
  }

  Future<User?> _processAuthResponse(Map<String, dynamic> data) async {
    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;

    if (accessToken != null && accessToken.isNotEmpty) {
      await _localStorage.saveToken(accessToken);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _localStorage.saveRefreshToken(refreshToken);
    }

    final userData = data['user'];
    if (userData is Map<String, dynamic>) {
      return User.fromJson(userData);
    }
    return null;
  }

  Map<String, dynamic> _deviceInfo() {
    if (kIsWeb) return {'platform': 'web'};
    if (Platform.isIOS) return {'platform': 'ios'};
    if (Platform.isAndroid) return {'platform': 'android'};
    return {'platform': 'unknown'};
  }
}
