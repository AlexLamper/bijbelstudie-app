import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
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

  Future<List<String>> getBooks(String versionId) async {
    try {
      final response = await _apiClient.dio.get('/bibles/$versionId/books');
      final data = response.data as Map<String, dynamic>;
      return (data['books'] as List<dynamic>).map((e) => e.toString()).toList();
    } on DioException catch (e) {
      throw _mapError(e, versionId);
    }
  }

  Future<List<int>> getChapters(String versionId, String book) async {
    try {
      final response = await _apiClient.dio.get(
        '/bibles/$versionId/${Uri.encodeComponent(book)}/chapters',
      );
      final data = response.data as Map<String, dynamic>;
      return (data['chapters'] as List<dynamic>).map((e) => (e as num).toInt()).toList();
    } on DioException catch (e) {
      throw _mapError(e, versionId);
    }
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
        // One bad chapter must not abandon the rest of the book.
      }
      done += 1;
      yield BookDownloadProgress(done: done, total: chapters.length);
    }
    await _cache?.setPinnedForBook(
      kind: _kind,
      sourceId: versionId,
      book: book,
      pinned: true,
    );
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
        return _RawChapter(cached.payload, fromCache: true);
      }

      final data = response.data as Map<String, dynamic>;
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
  const BookDownloadProgress({required this.done, required this.total});

  final int done;
  final int total;

  double get fraction => total == 0 ? 1 : done / total;
  bool get isComplete => done >= total;
}
