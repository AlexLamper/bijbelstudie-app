import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/api/api_client.dart';
import 'package:bijbelstudie_mobile/features/auth/data/auth_local_storage.dart';

/// A 401 does not always mean "your session expired".
///
/// The interceptor used to exclude only `/auth/refresh` from its refresh-and-
/// retry path, so a wrong password on the login screen was handled as an
/// expired session: the client spent the device's refresh token, then cleared
/// secure storage and fired `onSessionExpired`, which sends the router to
/// `/login?expired=1`. The screen was rebuilt underneath the user, their typed
/// credentials went with it, and "E-mailadres of wachtwoord klopt niet" was
/// replaced by "Je sessie is verlopen" for someone who had never been signed
/// in. Registration never showed it: `/auth/register` answers 201 or 409.

class _FakeAuthStorage implements AuthLocalStorage {
  _FakeAuthStorage({this.token, this.refreshToken});

  String? token;
  String? refreshToken;
  var cleared = false;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> saveRefreshToken(String value) async => refreshToken = value;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<void> deleteRefreshToken() async => refreshToken = null;

  @override
  Future<void> clear() async {
    cleared = true;
    token = null;
    refreshToken = null;
  }
}

/// Answers every request with one canned status, recording what it was asked.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode);

  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"error":"INVALID_CREDENTIALS","message":"E-mailadres of wachtwoord klopt niet."}',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a 401 from /auth/login is a credential answer, not an expired session', () async {
    final storage = _FakeAuthStorage(token: 'stale-access', refreshToken: 'stale-refresh');
    final client = ApiClient(storage);
    final adapter = _StubAdapter(401);
    client.dio.httpClientAdapter = adapter;

    var expiredFired = false;
    client.onSessionExpired = () => expiredFired = true;

    await expectLater(
      client.dio.post('/auth/login', data: {'email': 'a@b.com', 'password': 'wrong'}),
      throwsA(isA<DioException>()),
    );

    expect(expiredFired, isFalse, reason: 'the user was never signed in');
    expect(storage.cleared, isFalse, reason: 'a typo must not wipe the session');
    // One attempt, not two: the retry used to burn a second slot against the
    // server's 10-per-15-minutes login limit.
    expect(adapter.requests, hasLength(1));
    // And the request carried no stale bearer token.
    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('a 401 from an ordinary endpoint still ends the session', () async {
    // No refresh token, so `_doRefresh` gives up without a network call and
    // the expiry path runs to its end.
    final storage = _FakeAuthStorage(token: 'expired-access');
    final client = ApiClient(storage);
    client.dio.httpClientAdapter = _StubAdapter(401);

    var expiredFired = false;
    client.onSessionExpired = () => expiredFired = true;

    await expectLater(client.dio.get('/notes'), throwsA(isA<DioException>()));

    expect(expiredFired, isTrue);
    expect(storage.cleared, isTrue);
  });

  test('an authenticated request still carries the bearer token', () async {
    final storage = _FakeAuthStorage(token: 'good-access');
    final client = ApiClient(storage);
    final adapter = _StubAdapter(200);
    client.dio.httpClientAdapter = adapter;

    await client.dio.get('/notes');

    expect(adapter.requests.single.headers['Authorization'], 'Bearer good-access');
  });
}
