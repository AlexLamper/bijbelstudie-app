import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/api/api_client.dart';
import 'package:bijbelstudie_mobile/features/auth/data/auth_local_storage.dart';
import 'package:bijbelstudie_mobile/features/levensboom/data/levensboom_repository.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/catalog.dart';
import 'package:bijbelstudie_mobile/features/levensboom/present/levensboom_providers.dart';

/// Every studio tap used to end in "Opslaan is niet gelukt", whatever had gone
/// wrong. `patchAvatar` folded any answer without a JSON `error` into
/// `NETWORK`, so a deployment that has no `PATCH /levensboom` yet (the
/// website's HTML not-found page, status 404) read exactly like a dev server
/// that is not running, and the studio could only shrug. The status is the
/// diagnosis; these pin down that it survives, and what each case tells the
/// reader.

class _FakeAuthStorage implements AuthLocalStorage {
  String? token = 'access';
  String? refreshToken;

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
    token = null;
    refreshToken = null;
  }
}

/// Answers every request with one canned reply - or refuses the connection -
/// and records what it was asked.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter.reply(this.statusCode, this.body, {this.contentType = Headers.jsonContentType});

  _StubAdapter.unreachable()
      : statusCode = null,
        body = null,
        contentType = null;

  final int? statusCode;
  final String? body;
  final String? contentType;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final status = statusCode;
    if (status == null) {
      // What the IO adapter throws when nothing listens on the port.
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
        error: const SocketException('Connection refused'),
      );
    }
    return ResponseBody.fromString(
      body ?? '',
      status,
      headers: {
        Headers.contentTypeHeader: [contentType!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

LevensboomRepository _repository(_StubAdapter adapter) {
  final client = ApiClient(_FakeAuthStorage());
  client.dio.httpClientAdapter = adapter;
  return LevensboomRepository(client);
}

const _htmlNotFound = '<!DOCTYPE html><html><body><h1>404</h1></body></html>';

void main() {
  test('a fresh block comes back ok, from a PATCH with the four catalog ids', () async {
    final adapter = _StubAdapter.reply(200, '{"levensboom":{"seed":"s-1","planted":true}}');
    final result = await _repository(adapter).patchAvatar(AvatarChoice.defaults.toJson());

    expect(result.isOk, isTrue);
    expect(result.tree!['seed'], 's-1');

    final request = adapter.requests.single;
    expect(request.method, 'PATCH');
    expect(request.path, '/levensboom');
    // The server reads `body[kind]` for exactly these kinds and answers 400
    // INVALID_ITEM to anything that is not a string id.
    final body = request.data as Map;
    expect(body.keys, unorderedEquals(['species', 'scene', 'animal', 'ring']));
    expect(body.values, everyElement(isA<String>()));
  });

  test('a locked pick is the rule, not an error', () async {
    final adapter = _StubAdapter.reply(
      403,
      '{"error":"ITEM_LOCKED","item":{"kind":"scene","id":"night","name":"Nacht"},'
      '"unlock":{"type":"level","level":8},"label":"Niveau 8"}',
    );
    final result = await _repository(adapter).patchAvatar(AvatarChoice.defaults.toJson());

    expect(result.isOk, isFalse);
    expect(result.error, 'ITEM_LOCKED');
    expect(result.label, 'Niveau 8');

    final outcome = SaveOutcome.failed(result.error, result.label);
    expect(outcome.locked, isTrue);
    expect(outcome.routeMissing, isFalse);
  });

  test('a deployment without the route keeps its status', () async {
    for (final (status, body, type) in [
      (404, _htmlNotFound, 'text/html; charset=utf-8'),
      (405, '', 'text/plain'),
    ]) {
      final adapter = _StubAdapter.reply(status, body, contentType: type);
      final result = await _repository(adapter).patchAvatar(AvatarChoice.defaults.toJson());

      expect(result.isOk, isFalse);
      expect(result.error, 'HTTP_$status', reason: 'a $status is not a network failure');
      expect(result.label, isNull);

      final outcome = SaveOutcome.failed(result.error, result.label);
      expect(outcome.routeMissing, isTrue);
      expect(outcome.offline, isFalse);
      expect(
        outcome.message,
        'De server kent deze functie nog niet. Werk de website bij en probeer het opnieuw.',
      );
    }
  });

  test('an unreachable host is a network failure', () async {
    final result =
        await _repository(_StubAdapter.unreachable()).patchAvatar(AvatarChoice.defaults.toJson());

    expect(result.isOk, isFalse);
    expect(result.error, 'NETWORK');
    expect(result.label, isNull);

    final outcome = SaveOutcome.failed(result.error, result.label);
    expect(outcome.offline, isTrue);
    expect(outcome.routeMissing, isFalse);
    expect(outcome.message, 'Geen verbinding. Probeer het later opnieuw.');
  });

  test('any other refusal keeps the generic message', () {
    expect(
      SaveOutcome.failed('INTERNAL_ERROR', null).message,
      'Opslaan is niet gelukt. Probeer het nog eens.',
    );
  });
}
