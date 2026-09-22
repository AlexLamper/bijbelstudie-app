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

  /// Addresses are matched as stored, so a stray capital from the keyboard or
  /// a paste with trailing whitespace is a failed login on an account that
  /// exists. Normalising here means register and login always agree.
  static String _normaliseEmail(String email) => email.trim().toLowerCase();

  Future<User?> login(String email, String password) async {
    return _post('/auth/login', {
      'email': _normaliseEmail(email),
      'password': password,
      ..._deviceInfo(),
    }, 'Inloggen mislukt');
  }

  Future<User?> register(String name, String email, String password) async {
    return _post('/auth/register', {
      'name': name.trim(),
      'email': _normaliseEmail(email),
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

  /// Signs in with Google **and registers a first-time user in the same call**.
  ///
  /// `/api/v1/auth/google` is a find-link-or-create endpoint (website repo,
  /// `lib/oauthUsers.ts` → `provisionOAuthUser`): it matches on `googleId`,
  /// then case-insensitively on the verified e-mail address, and otherwise
  /// creates the account with one atomic upsert. That is the same "find or
  /// create" the website's NextAuth `signIn` callback does, so there is no
  /// separate mobile "registreren met Google" route and `/auth/register` must
  /// not be called first — it wants a password this user does not have.
  ///
  /// [email] and [name] are what Google handed the *client*. The server
  /// derives both from the verified ID token and ignores what we send; they
  /// ride along so a token minted without the `email`/`profile` claims can
  /// still be turned into an account server-side (see the note in the report)
  /// rather than dead-ending on `NO_EMAIL`.
  Future<User?> loginWithGoogle({
    required String idToken,
    String? email,
    String? name,
  }) async {
    return _post('/auth/google', {
      'idToken': idToken,
      if (email != null && email.trim().isNotEmpty) 'email': _normaliseEmail(email),
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      ..._deviceInfo(),
    }, 'Inloggen met Google mislukt');
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

  /// Turns a failed auth call into something a reader can act on.
  ///
  /// `errorV1` defaults `message` to the error code, so a route that passes no
  /// copy answers `{"error":"INTERNAL_ERROR","message":"INTERNAL_ERROR"}` — and
  /// that raw code was shown verbatim on the login screen. It is not Dutch, it
  /// is not a sentence, and it tells the user nothing about whether to retry.
  /// A message equal to the code is therefore dropped in favour of our own
  /// wording; a real Dutch message from the server still wins.
  static String authErrorMessage(
    Map<dynamic, dynamic> body,
    String fallbackMessage,
  ) {
    final code = body['error'] is String ? body['error'] as String : null;
    final raw = body['message'] is String ? body['message'] as String : null;
    if (raw != null && raw.isNotEmpty && raw != code) return raw;

    switch (code) {
      case 'INTERNAL_ERROR':
        return '$fallbackMessage door een storing. Probeer het zo opnieuw.';
      case 'UNAUTHORIZED':
        return '$fallbackMessage: de inloggegevens werden niet geaccepteerd.';
      // The OAuth routes answer this when the ID token's signature, issuer or
      // audience does not check out. "Inloggegevens" is the wrong word for it:
      // the user typed nothing, so telling them their gegevens are wrong sends
      // them looking for a mistake they did not make.
      case 'INVALID_TOKEN':
        return '$fallbackMessage: de aanmelding werd niet geaccepteerd. '
            'Probeer het opnieuw.';
      case 'MISSING_FIELDS':
        return '$fallbackMessage: er zijn niet genoeg gegevens meegestuurd. '
            'Probeer het opnieuw.';
      // `/auth/google` cannot create an account without a verified address.
      case 'NO_EMAIL':
        return 'Google deelde geen e-mailadres. Geef toestemming voor je '
            'e-mailadres of maak een account met je e-mailadres en wachtwoord.';
      case 'EMAIL_TAKEN':
        return 'Er bestaat al een account met dit e-mailadres. Log in met je '
            'wachtwoord; Google wordt daarna vanzelf aan dat account gekoppeld.';
      case 'RATE_LIMITED':
        return 'Te veel pogingen. Wacht even en probeer het opnieuw.';
      case null:
        return fallbackMessage;
      default:
        return fallbackMessage;
    }
  }

  Future<User?> _post(String path, Map<String, dynamic> data, String fallbackMessage) async {
    try {
      final response = await _apiClient.dio.post(path, data: data);
      return _processAuthResponse(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map) {
        throw Exception(authErrorMessage(body, fallbackMessage));
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
