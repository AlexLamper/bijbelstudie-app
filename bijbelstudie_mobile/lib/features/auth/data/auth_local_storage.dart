import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token storage. On iOS this is the Keychain, which is what App Review
/// expects for anything that grants account access.
///
/// Two tokens, not one: a 15-minute access token that is sent with every
/// request, and a 90-day opaque refresh token that is sent to exactly one
/// endpoint. A single long-lived token would be a password that never expires
/// and cannot be revoked from the server.
class AuthLocalStorage {
  final FlutterSecureStorage _storage;

  AuthLocalStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'jwt_token';
  static const _refreshKey = 'refresh_token';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshKey);
  }

  Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _refreshKey);
  }

  Future<void> clear() async {
    await deleteToken();
    await deleteRefreshToken();
  }
}
