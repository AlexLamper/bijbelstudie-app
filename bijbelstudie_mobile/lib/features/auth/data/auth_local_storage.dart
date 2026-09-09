import 'package:flutter/foundation.dart';
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

  /// The access token, remembered after the first read.
  ///
  /// Every request goes through the bearer interceptor, and every one of those
  /// used to cost a Keychain/KeyStore round trip - a platform-channel call that
  /// is serialised with every other one. Opening the Start tab fires eight or
  /// nine requests at once, so the reads alone delayed the *start* of every
  /// request behind the platform thread. The token is already held in memory by
  /// Dio for the duration of each request; keeping one copy here changes what
  /// it costs, not who can reach it.
  ///
  /// Writes and deletions go through this class, so the copy cannot go stale:
  /// [_tokenLoaded] is only true while [_token] is known to match storage.
  String? _token;
  bool _tokenLoaded = false;

  Future<void> saveToken(String token) async {
    _token = token;
    _tokenLoaded = true;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    if (_tokenLoaded) return _token;
    final value = await _read(_tokenKey);
    _token = value;
    _tokenLoaded = true;
    return value;
  }

  Future<void> deleteToken() async {
    _token = null;
    _tokenLoaded = true;
    await _storage.delete(key: _tokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshKey, value: token);
  }

  Future<String?> getRefreshToken() => _read(_refreshKey);

  /// A read that can only answer "a token" or "no token", never hang and never
  /// throw.
  ///
  /// The Keychain/KeyStore is not a plain file. A restored Android backup, a
  /// rotated or reset KeyStore, a device still locked after boot, or a missing
  /// plugin all make `read` throw a `PlatformException` — and the splash screen
  /// awaits this before it can route anywhere, so an unhandled throw here is
  /// the whole app never getting past its loading bar. An entry we cannot
  /// decrypt is worth exactly as much as no entry: the user signs in again.
  ///
  /// The deadline covers the other half of the same failure: a platform channel
  /// that never answers is indistinguishable from one that answers slowly, and
  /// only one of the two is survivable without a timeout.
  Future<String?> _read(String key) async {
    try {
      return await _storage
          .read(key: key)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AuthLocalStorage] read of $key failed: $e');
      // Drop the unreadable entry so the next launch does not pay for it
      // again. Best-effort: a keystore that cannot read may not delete either.
      try {
        await _storage.delete(key: key).timeout(const Duration(seconds: 5));
      } catch (_) {}
      return null;
    }
  }

  Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _refreshKey);
  }

  Future<void> clear() async {
    await deleteToken();
    await deleteRefreshToken();
  }
}
