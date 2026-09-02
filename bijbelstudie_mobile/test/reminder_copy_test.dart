import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/core/notifications/reminder_copy.dart';

/// A Dio whose adapter answers from a script instead of the network.
Dio _dioReturning({required int status, Object? body, bool fail = false}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.httpClientAdapter = _ScriptedAdapter(status: status, body: body, fail: fail);
  return dio;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({required this.status, this.body, this.fail = false});

  final int status;
  final Object? body;
  final bool fail;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? stream, Future<void>? cancelFuture) async {
    calls++;
    if (fail) throw DioException(requestOptions: options, message: 'offline');
    return ResponseBody.fromString(
      jsonEncode(body ?? const {}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _payload(List<String> ids) => {
  'type': 'daily_reading',
  'days': ids.length,
  'variants': [
    for (var i = 0; i < ids.length; i++)
      {
        'dayOffset': i,
        'variantId': ids[i],
        'title': 'Titel ${ids[i]}',
        'body': 'Tekst ${ids[i]}',
        'deepLink': '/lezen?book=Ruth&chapter=1',
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReminderCopySource.load', () {
    test('returns the server batch and caches it', () async {
      final source = ReminderCopySource(
        _dioReturning(status: 200, body: _payload(['d01', 'd02', 'd03'])),
      );

      final variants = await source.load();
      expect(variants, hasLength(3));
      expect(variants.first.variantId, 'd01');
      expect(variants.first.title, 'Titel d01');
      expect(variants.first.deepLink, '/lezen?book=Ruth&chapter=1');

      // A second source with a dead network still gets the cached batch.
      final offline = ReminderCopySource(_dioReturning(status: 200, fail: true));
      final cached = await offline.load();
      expect(cached.map((v) => v.variantId), ['d01', 'd02', 'd03']);
    });

    test('falls back to the bundle when there is no network and no cache', () async {
      final source = ReminderCopySource(_dioReturning(status: 200, fail: true));
      final variants = await source.load();
      expect(variants, ReminderCopySource.bundledFallback);
    });

    test('falls back to the bundle when the server answers with nothing usable', () async {
      final source = ReminderCopySource(
        _dioReturning(status: 200, body: {'variants': []}),
      );
      expect(await source.load(), ReminderCopySource.bundledFallback);
    });

    test('drops a variant with no text rather than scheduling a blank notification', () async {
      final source = ReminderCopySource(
        _dioReturning(status: 200, body: {
          'variants': [
            {'variantId': 'd01', 'title': '', 'body': 'Tekst', 'deepLink': '/x'},
            {'variantId': 'd02', 'title': 'Titel', 'body': '   ', 'deepLink': '/x'},
            {'variantId': 'd03', 'title': 'Titel', 'body': 'Tekst', 'deepLink': '/x'},
          ],
        }),
      );
      final variants = await source.load();
      expect(variants.map((v) => v.variantId), ['d03']);
    });

    test('never throws, whatever the server sends', () async {
      for (final body in <Object>[
        {'variants': 'not-a-list'},
        {'variants': [1, 2, 3]},
        {},
      ]) {
        final source = ReminderCopySource(_dioReturning(status: 200, body: body));
        expect(await source.load(), isNotEmpty);
      }
    });
  });

  group('cacheOnly', () {
    test('uses the bundle rather than making a request', () async {
      const source = ReminderCopySource.cacheOnly();
      expect(await source.load(), ReminderCopySource.bundledFallback);
    });

    test('prefers a cached batch when one exists', () async {
      await ReminderCopySource(
        _dioReturning(status: 200, body: _payload(['d05', 'd06'])),
      ).load();

      const offline = ReminderCopySource.cacheOnly();
      final variants = await offline.load();
      expect(variants.map((v) => v.variantId), ['d05', 'd06']);
    });
  });

  group('needsRefresh', () {
    test('is true with nothing cached', () async {
      expect(await const ReminderCopySource.cacheOnly().needsRefresh(), isTrue);
    });

    test('is false straight after a successful fetch', () async {
      final source = ReminderCopySource(
        _dioReturning(status: 200, body: _payload(['d01'])),
      );
      await source.load();
      expect(await source.needsRefresh(), isFalse);
    });

    test('is true once the batch is nearly used up', () async {
      final source = ReminderCopySource(
        _dioReturning(status: 200, body: _payload(['d01'])),
      );
      await source.load();

      // Rewind the stored fetch date past the refresh threshold.
      final stale = DateTime.now().subtract(
        Duration(days: ReminderCopySource.batchDays - ReminderCopySource.refetchWhenRemainingBelow),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'reminder_copy_fetched_on_v1',
        stale.toIso8601String().split('T').first,
      );

      expect(await source.needsRefresh(), isTrue);
    });
  });

  group('the bundled fallback', () {
    test('needs no reading history to make sense', () {
      for (final variant in ReminderCopySource.bundledFallback) {
        expect(variant.title, isNot(contains('{')));
        expect(variant.body, isNot(contains('{')));
        expect(variant.isUsable, isTrue);
      }
    });

    test('holds enough variants that a week is not one repeated string', () {
      expect(ReminderCopySource.bundledFallback.length, greaterThanOrEqualTo(3));
    });

    test('follows the house tone rules', () {
      for (final variant in ReminderCopySource.bundledFallback) {
        final text = '${variant.title} ${variant.body}';
        expect(text, isNot(contains('!')));
        expect(text.toLowerCase(), isNot(matches(RegExp(r'\bmoet\b'))));
        expect(variant.title.length, lessThanOrEqualTo(32));
        expect(variant.body.length, lessThanOrEqualTo(110));
      }
    });

    test('no longer contains the string it replaced', () {
      for (final variant in ReminderCopySource.bundledFallback) {
        expect(variant.title, isNot('Tijd om te lezen'));
        expect(variant.body, isNot('Neem even de tijd voor je bijbelgedeelte.'));
      }
    });
  });
}
