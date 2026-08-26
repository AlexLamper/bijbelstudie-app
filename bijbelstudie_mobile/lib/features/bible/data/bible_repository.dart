import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/data/bible_books.dart';
import '../../../core/db/content_cache.dart';
import '../../auth/present/auth_controller.dart';
import '../domain/bible_models.dart';

final bibleRepositoryProvider = Provider((ref) {
  return BibleRepository(ref.watch(apiClientProvider), ref.watch(contentCacheProvider));
});

/// Reads scripture, cache first.
///
/// Every chapter fetch is a conditional request: if the device already holds
/// the chapter, its ETag goes out as `If-None-Match` and the usual answer is a
/// 304 with no body. That is what makes re-reading a chapter almost free and
/// what lets the reader work with no network at all.
class BibleRepository {
  BibleRepository(this._apiClient, this._cache);

  final ApiClient _apiClient;
  final ContentCache? _cache;

  static const _kind = 'bible';

  Future<List<BibleSource>> getVersions() async {
    final response = await _apiClient.dio.get('/bibles');
    final data = response.data as Map<String, dynamic>;
    return (data['bibles'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(BibleSource.fromJson)
        .toList();
  }

  /// The books of a translation, falling back to what is on the device.
  ///
  /// Without this fallback a downloaded book was unreachable the moment the
  /// network went away: the picker could not list a single book, so there was
  /// no way to get to text that was sitting on disk the whole time. The
  /// offline answer lists only books that genuinely have chapters cached, in
  /// canon order, so nothing is offered that cannot actually be opened.
  Future<List<String>> getBooks(String versionId) async {
    try {
      final response = await _apiClient.dio.get('/bibles/$versionId/books');
      final data = response.data as Map<String, dynamic>;
      return (data['books'] as List<dynamic>).map((e) => e.toString()).toList();
    } on DioException catch (e) {
      final cached = await _cachedBooks(versionId);
      if (cached.isNotEmpty) return cached;
      throw _mapError(e, versionId);
    }
  }

  /// The chapters of a book, falling back to the ones stored on the device.
  ///
  /// The reader's Vorige/Volgende buttons and the picker's chapter grid are
  /// both driven by this list. Offline it used to come back empty, which
  /// disabled both buttons and stranded the reader on whichever chapter
  /// happened to be open - a downloaded book you could not page through. The
  /// cached list is the truthful one here: every number in it opens.
  Future<List<int>> getChapters(String versionId, String book) async {
    try {
      final response = await _apiClient.dio.get(
        '/bibles/$versionId/${Uri.encodeComponent(book)}/chapters',
      );
      final data = response.data as Map<String, dynamic>;
      return (data['chapters'] as List<dynamic>).map((e) => (e as num).toInt()).toList();
    } on DioException catch (e) {
      final cached = await _cache?.cachedChaptersForBook(
        kind: _kind,
        sourceId: versionId,
        book: book,
      );
      if (cached != null && cached.isNotEmpty) return cached;
      throw _mapError(e, versionId);
    }
  }

  Future<List<String>> _cachedBooks(String versionId) async {
    final books = await _cache?.cachedBooks(kind: _kind, sourceId: versionId);
    if (books == null || books.isEmpty) return const [];

    // Canon order for the ones we recognise, then anything else alphabetically
    // so a translation with its own book naming still lists sensibly.
    final known = <String>[
      for (final book in BibleBooks.all)
        if (books.contains(book)) book,
    ];
    final rest = books.where((b) => !BibleBooks.chapterCounts.containsKey(b)).toList()..sort();
    return [...known, ...rest];
  }

  Future<ChapterContent> getChapter(String versionId, String book, int chapter) {
    return _fetchChapter(
      kind: _kind,
      path: '/bibles/$versionId/${Uri.encodeComponent(book)}/$chapter',
      sourceId: versionId,
      book: book,
      chapter: chapter,
    );
  }

  Future<OriginalChapter> getOriginal(String book, int chapter) async {
    final payload = await _fetchRaw(
      kind: 'original',
      path: '/original/${Uri.encodeComponent(book)}/$chapter',
      sourceId: 'stepbible',
      book: book,
      chapter: chapter,
    );
    return OriginalChapter.fromJson(payload.data);
  }

  Future<SearchResults> search({
    required String query,
    required String versionId,
    String? book,
    int limit = 50,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/search',
        queryParameters: {
          'q': query,
          'version': versionId,
          if (book != null) 'book': book,
          'limit': limit,
        },
      );
      return SearchResults.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapError(e, versionId);
    }
  }

  /// Downloads every chapter of one book so it can be read offline.
  ///
  /// Per book, never per version: a whole translation is tens of megabytes and
  /// hundreds of requests, and nobody reads a whole translation on a phone.
  Stream<BookDownloadProgress> downloadBook({
    required String versionId,
    required String book,
    required List<int> chapters,
  }) async* {
    var done = 0;
    var failed = 0;
    for (final chapter in chapters) {
      try {
        await _fetchChapter(
          kind: _kind,
          path: '/bibles/$versionId/${Uri.encodeComponent(book)}/$chapter',
          sourceId: versionId,
          book: book,
          chapter: chapter,
          pinned: true,
        );
      } catch (_) {
        // One bad chapter must not abandon the rest of the book, but it is
        // counted: a book that lost chapters is not a downloaded book and the
        // UI has to be able to say so.
        failed += 1;
      }
      done += 1;
      yield BookDownloadProgress(done: done, total: chapters.length, failed: failed);
    }
    await _cache?.setPinnedForBook(
      kind: _kind,
      sourceId: versionId,
      book: book,
      pinned: true,
    );
  }

  /// What of [book] is readable with no network right now.
  ///
  /// Read back out of the cache rather than remembered from the download, so
  /// eviction, a failed chapter or a half-finished download all show up as the
  /// smaller number instead of a stale "opgeslagen" label.
  Future<List<int>> offlineChapters(String versionId, String book) async {
    final cached = await _cache?.cachedChaptersForBook(
      kind: _kind,
      sourceId: versionId,
      book: book,
    );
    return cached ?? const [];
  }

  Future<List<OfflineBook>> offlineBooks() async {
    final books = await _cache?.downloadedBooks(kind: _kind);
    return books ?? const [];
  }

  Future<void> removeOfflineBook(String versionId, String book) async {
    await _cache?.removeBook(kind: _kind, sourceId: versionId, book: book);
  }

  Future<ChapterContent> _fetchChapter({
    required String kind,
    required String path,
    required String sourceId,
    required String book,
    required int chapter,
    bool pinned = false,
  }) async {
    final payload = await _fetchRaw(
      kind: kind,
      path: path,
      sourceId: sourceId,
      book: book,
      chapter: chapter,
      pinned: pinned,
    );
    return ChapterContent.fromJson(payload.data, fromCache: payload.fromCache);
  }

  Future<_RawChapter> _fetchRaw({
    required String kind,
    required String path,
    required String sourceId,
    required String book,
    required int chapter,
    bool pinned = false,
  }) async {
    final cached = await _cache?.read(
      kind: kind,
      sourceId: sourceId,
      book: book,
      chapter: chapter,
    );

    try {
      final response = await _apiClient.dio.get(
        path,
        options: Options(
          headers: cached?.etag == null ? null : {'If-None-Match': cached!.etag},
          // 304 is a success here, not an error.
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (response.statusCode == 304 && cached != null) {
        await _cache?.touchFetchedAt(
          kind: kind,
          sourceId: sourceId,
          book: book,
          chapter: chapter,
        );
        // `fromCache: false` on purpose. The bytes came off disk, but the
        // server was just asked and answered - the reader is online and the
        // text is current. Reporting cache here made the reader show "Offline
        // gelezen" on a live connection, which is the cheap re-read working
        // exactly as designed being labelled as a degraded one.
        return _RawChapter(cached.payload, fromCache: false);
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        // A 304 with nothing cached, or a body that is not a chapter. Neither
        // is worth crashing the reader over when disk may still have an answer.
        if (cached != null) return _RawChapter(cached.payload, fromCache: true);
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Unexpected chapter payload',
        );
      }
      await _cache?.write(
        kind: kind,
        sourceId: sourceId,
        book: book,
        chapter: chapter,
        payload: data,
        etag: response.headers.value('etag'),
        pinned: pinned,
      );
      return _RawChapter(data, fromCache: false);
    } on DioException catch (e) {
      // Offline or server trouble: cached text beats an error screen.
      if (cached != null) return _RawChapter(cached.payload, fromCache: true);
      throw _mapError(e, sourceId);
    }
  }

  Object _mapError(DioException e, String sourceId) {
    if (e.response?.statusCode == 451) {
      return ContentNotLicensedException(sourceId);
    }
    return e;
  }
}

class _RawChapter {
  const _RawChapter(this.data, {required this.fromCache});

  final Map<String, dynamic> data;
  final bool fromCache;
}

class BookDownloadProgress {
  const BookDownloadProgress({
    required this.done,
    required this.total,
    this.failed = 0,
  });

  final int done;
  final int total;

  /// Chapters that could not be fetched. They are skipped, not retried, so
  /// they are the difference between a book that is stored and one that only
  /// looks stored.
  final int failed;

  double get fraction => total == 0 ? 1 : done / total;
  bool get isComplete => done >= total;
  int get stored => done - failed;
}
