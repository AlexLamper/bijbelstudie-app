import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/api/api_client.dart';
import 'package:bijbelstudie_mobile/core/db/content_cache.dart';
import 'package:bijbelstudie_mobile/features/auth/data/auth_local_storage.dart';
import 'package:bijbelstudie_mobile/features/bible/data/bible_repository.dart';

/// The offline reading path, exercised without a device.
///
/// `sqflite` needs a real platform, so the cache is stubbed in memory and what
/// is tested here is the half that decides *when* disk answers instead of the
/// network - which is where the bugs were.

/// Token storage that never touches the keychain channel.
class _FakeAuthStorage extends AuthLocalStorage {
  @override
  Future<String?> getToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;
}

class _CacheKey {
  const _CacheKey(this.sourceId, this.book, this.chapter);

  final String sourceId;
  final String book;
  final int chapter;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.sourceId == sourceId &&
      other.book == book &&
      other.chapter == chapter;

  @override
  int get hashCode => Object.hash(sourceId, book, chapter);
}

class _FakeCache extends ContentCache {
  final Map<_CacheKey, CachedChapter> rows = {};
  final Set<_CacheKey> pinned = {};
  int touched = 0;

  void seed(String sourceId, String book, int chapter, {String? etag, bool pinned = false}) {
    rows[_CacheKey(sourceId, book, chapter)] = CachedChapter(
      payload: {
        'id': sourceId,
        'book': book,
        'chapter': chapter,
        'verses': [
          {'n': 1, 't': 'Opgeslagen tekst'},
        ],
        'attribution': 'Statenvertaling',
      },
      etag: etag,
      fetchedAt: DateTime(2026, 1, 1),
    );
    if (pinned) this.pinned.add(_CacheKey(sourceId, book, chapter));
  }

  @override
  Future<CachedChapter?> read({
    required String kind,
    required String sourceId,
    required String book,
    required int chapter,
  }) async {
    return rows[_CacheKey(sourceId, book, chapter)];
  }

  @override
  Future<void> write({
    required String kind,
    required String sourceId,
    required String book,
    required int chapter,
    required Map<String, dynamic> payload,
    String? etag,
    bool pinned = false,
  }) async {
    final key = _CacheKey(sourceId, book, chapter);
    rows[key] = CachedChapter(payload: payload, etag: etag, fetchedAt: DateTime(2026, 1, 1));
    // Mirrors the upsert: a pin is never cleared by an ordinary read.
    if (pinned) this.pinned.add(key);
  }

  @override
  Future<void> touchFetchedAt({
    required String kind,
    required String sourceId,
    required String book,
    required int chapter,
  }) async {
    touched += 1;
  }

  @override
  Future<List<int>> cachedChaptersForBook({
    required String kind,
    required String sourceId,
    required String book,
  }) async {
    final chapters = rows.keys
        .where((k) => k.sourceId == sourceId && k.book == book)
        .map((k) => k.chapter)
        .toList()
      ..sort();
    return chapters;
  }

  @override
  Future<List<String>> cachedBooks({
    required String kind,
    required String sourceId,
  }) async {
    return rows.keys.where((k) => k.sourceId == sourceId).map((k) => k.book).toSet().toList();
  }

  @override
  Future<void> setPinnedForBook({
    required String kind,
    required String sourceId,
    required String book,
    required bool pinned,
  }) async {
    for (final key in rows.keys.where((k) => k.sourceId == sourceId && k.book == book)) {
      if (pinned) {
        this.pinned.add(key);
      } else {
        this.pinned.remove(key);
      }
    }
  }
}

/// Answers requests from a table, or refuses to connect at all.
class _FakeAdapter implements HttpClientAdapter {
  /// Flipped by the tests rather than set at construction, so one adapter can
  /// serve a chapter and then lose the network.
  bool offline = false;
  final Map<String, ResponseBody Function()> routes = {};
  final List<String> requested = [];

  void json(String path, Map<String, dynamic> body, {int statusCode = 200, String? etag}) {
    routes[path] = () => ResponseBody.fromString(
          jsonEncode(body),
          statusCode,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            if (etag != null) 'etag': [etag],
          },
        );
  }

  void notModified(String path) {
    routes[path] = () => ResponseBody.fromString(
          '',
          304,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.path);
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no network',
      );
    }
    final route = routes[options.path];
    if (route == null) {
      return ResponseBody.fromString('{"error":"not found"}', 404);
    }
    return route();
  }

  @override
  void close({bool force = false}) {}
}

({BibleRepository repository, _FakeCache cache, _FakeAdapter adapter}) build() {
  final apiClient = ApiClient(_FakeAuthStorage());
  final adapter = _FakeAdapter();
  apiClient.dio.httpClientAdapter = adapter;
  final cache = _FakeCache();
  return (
    repository: BibleRepository(apiClient, cache),
    cache: cache,
    adapter: adapter,
  );
}

Map<String, dynamic> _chapterBody(String book, int chapter) => {
      'id': 'statenvertaling',
      'book': book,
      'chapter': chapter,
      'verses': [
        {'n': 1, 't': 'Verse van de server'},
      ],
      'attribution': 'Statenvertaling',
    };

void main() {
  group('reading with no network', () {
    test('a cached chapter is served and flagged as offline', () async {
      final env = build();
      env.cache.seed('statenvertaling', 'Genesis', 1);
      env.adapter.offline = true;

      final chapter = await env.repository.getChapter('statenvertaling', 'Genesis', 1);

      expect(chapter.fromCache, isTrue);
      expect(chapter.verses.single.text, 'Opgeslagen tekst');
    });

    test('a chapter that was never cached still fails', () async {
      final env = build();
      env.adapter.offline = true;

      expect(
        () => env.repository.getChapter('statenvertaling', 'Genesis', 1),
        throwsA(isA<DioException>()),
      );
    });

    test('the chapter list falls back to what is on disk', () async {
      final env = build();
      for (final chapter in [3, 1, 2]) {
        env.cache.seed('statenvertaling', 'Genesis', chapter, pinned: true);
      }
      env.adapter.offline = true;

      // Without this the reader's Vorige/Volgende are both disabled offline and
      // a downloaded book cannot be paged through at all.
      expect(await env.repository.getChapters('statenvertaling', 'Genesis'), [1, 2, 3]);
    });

    test('the chapter list still throws when nothing is stored', () async {
      final env = build();
      env.adapter.offline = true;

      expect(
        () => env.repository.getChapters('statenvertaling', 'Genesis'),
        throwsA(isA<DioException>()),
      );
    });

    test('the book list falls back to stored books in canon order', () async {
      final env = build();
      env.cache.seed('statenvertaling', 'Johannes', 1);
      env.cache.seed('statenvertaling', 'Genesis', 1);
      env.cache.seed('statenvertaling', 'Exodus', 1);
      env.adapter.offline = true;

      expect(
        await env.repository.getBooks('statenvertaling'),
        ['Genesis', 'Exodus', 'Johannes'],
      );
    });

    test('only books that really have chapters on disk are offered', () async {
      final env = build();
      env.cache.seed('statenvertaling', 'Genesis', 1);
      env.adapter.offline = true;

      expect(await env.repository.getBooks('statenvertaling'), ['Genesis']);
    });
  });

  group('reading with a network', () {
    test('a 304 is not reported as offline reading', () async {
      final env = build();
      env.cache.seed('statenvertaling', 'Genesis', 1, etag: 'v1');
      env.adapter.notModified('/bibles/statenvertaling/Genesis/1');

      final chapter = await env.repository.getChapter('statenvertaling', 'Genesis', 1);

      // The bytes came off disk, but the server was asked and answered. The
      // reader must not claim "Offline gelezen" on a live connection.
      expect(chapter.fromCache, isFalse);
      expect(chapter.verses.single.text, 'Opgeslagen tekst');
      expect(env.cache.touched, 1);
    });

    test('a fresh chapter is cached and not flagged', () async {
      final env = build();
      env.adapter.json(
        '/bibles/statenvertaling/Genesis/1',
        _chapterBody('Genesis', 1),
        etag: 'v1',
      );

      final chapter = await env.repository.getChapter('statenvertaling', 'Genesis', 1);

      expect(chapter.fromCache, isFalse);
      expect(env.cache.rows.length, 1);
    });
  });

  group('downloading a book', () {
    test('reports the chapters it could not fetch instead of claiming success',
        () async {
      final env = build();
      env.adapter.json(
        '/bibles/statenvertaling/Genesis/1',
        _chapterBody('Genesis', 1),
      );
      // Chapter 2 has no route, so it 404s and is skipped.

      final progress = await env.repository
          .downloadBook(versionId: 'statenvertaling', book: 'Genesis', chapters: [1, 2])
          .toList();

      expect(progress.last.done, 2);
      expect(progress.last.failed, 1);
      expect(progress.last.stored, 1);
      expect(env.cache.rows.length, 1);
    });

    test('downloaded chapters are pinned', () async {
      final env = build();
      env.adapter.json(
        '/bibles/statenvertaling/Genesis/1',
        _chapterBody('Genesis', 1),
      );

      await env.repository
          .downloadBook(versionId: 'statenvertaling', book: 'Genesis', chapters: [1])
          .drain<void>();

      expect(env.cache.pinned, contains(const _CacheKey('statenvertaling', 'Genesis', 1)));
    });

    test('an ordinary re-read does not drop the pin', () async {
      final env = build();
      env.adapter.json(
        '/bibles/statenvertaling/Genesis/1',
        _chapterBody('Genesis', 1),
      );
      await env.repository
          .downloadBook(versionId: 'statenvertaling', book: 'Genesis', chapters: [1])
          .drain<void>();

      // The read path fetches with pinned: false. Before the upsert fix this
      // REPLACE'd the row with pinned = 0 and handed a downloaded chapter back
      // to the LRU.
      await env.repository.getChapter('statenvertaling', 'Genesis', 1);

      expect(env.cache.pinned, contains(const _CacheKey('statenvertaling', 'Genesis', 1)));
    });
  });

  group('what is stored', () {
    test('offlineChapters reads back out of the cache', () async {
      final env = build();
      env.cache.seed('statenvertaling', 'Genesis', 2);
      env.cache.seed('statenvertaling', 'Genesis', 1);

      expect(await env.repository.offlineChapters('statenvertaling', 'Genesis'), [1, 2]);
    });
  });
}
