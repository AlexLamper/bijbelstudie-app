import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/db/content_cache.dart';
import '../../bible/domain/bible_models.dart';
import '../domain/crossref_models.dart';

/// Reads `/api/v1/crossrefs/:book/:chapter`, cache first.
///
/// The rows live in the existing `chapters` table under `kind: 'crossref'` —
/// no migration, no schema version bump. The table is keyed
/// `(kind, source_id, book, chapter)`, which is exactly the shape of a
/// cross-reference chapter, and it brings the ETag column, the LRU and the
/// pinning that a downloaded book already relies on.
///
/// [sourceIdFor] carries the translation as well as the dataset because the
/// server resolves the references into *that translation's* numbering: the
/// same chapter of the same dataset is a different payload per version, and
/// one shared row would hand a Statenvertaling reader NBG51 verse numbers.
class CrossRefRepository {
  CrossRefRepository(this._apiClient, this._cache);

  final ApiClient _apiClient;
  final ContentCache? _cache;

  static const kind = 'crossref';
  static const dataset = 'openbible';

  /// The cache row for one translation, per tier.
  ///
  /// Free readers get the server's gated slice from the public (CDN) URL, Pro
  /// readers the full list from `full=1`. The two are different payloads, so
  /// they live in different rows: a reader who upgrades must not be served
  /// the free slice off disk, and one whose Pro lapses must not keep the full
  /// list. The free row keeps the pre-gate key.
  static String sourceIdFor(String versionId, {bool full = false}) =>
      full ? '$dataset-pro:$versionId' : '$dataset:$versionId';

  /// [full] asks for every reference. The server only honours it for a Pro
  /// account (it resolves the bearer); anyone else still gets the free slice.
  Future<CrossRefChapter> getChapter(
    String versionId,
    String book,
    int chapter, {
    bool full = false,
  }) async {
    final sourceId = sourceIdFor(versionId, full: full);
    final cached = await _readCache(sourceId, book, chapter);

    try {
      final etag = cached?.etag;
      final response = await _apiClient.dio.get(
        '/crossrefs/${Uri.encodeComponent(book)}/$chapter',
        queryParameters: {'version': versionId, if (full) 'full': '1'},
        options: Options(
          headers: etag == null ? null : {'If-None-Match': etag},
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
        // `fromCache: false` on purpose: the bytes came off disk, but the
        // server was asked and answered, so this is the cheap re-read working
        // as designed rather than a degraded offline read.
        return CrossRefChapter.fromJson(cached.payload, fromCache: false);
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        // A 304 with nothing cached, or a body that is not a cross-reference
        // chapter. Disk may still have an answer worth showing.
        if (cached != null) {
          return CrossRefChapter.fromJson(cached.payload, fromCache: true);
        }
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: 'Unexpected cross-reference payload',
        );
      }

      await _cache?.write(
        kind: kind,
        sourceId: sourceId,
        book: book,
        chapter: chapter,
        payload: data,
        etag: response.headers.value('etag'),
      );
      return CrossRefChapter.fromJson(data, fromCache: false);
    } on DioException catch (e) {
      // Offline or server trouble: stored references beat an error row.
      if (cached != null) {
        return CrossRefChapter.fromJson(cached.payload, fromCache: true);
      }
      if (e.response?.statusCode == 451) {
        throw ContentNotLicensedException(versionId);
      }
      rethrow;
    }
  }

  /// What is already on disk for this chapter, and nothing else.
  ///
  /// This is what the long-press row counts with. A long-press is not a
  /// request: firing one per verse tapped would spend the CDN and the CPU
  /// budget on a number nobody asked for, and would stall the action sheet
  /// behind the network on a bad connection. Once the reader has opened the
  /// references for a chapter, the whole chapter's counts are on disk and
  /// every verse in it shows one — offline included.
  Future<CrossRefChapter?> cachedChapter(
    String versionId,
    String book,
    int chapter, {
    bool full = false,
  }) async {
    final cached = await _readCache(
      sourceIdFor(versionId, full: full),
      book,
      chapter,
    );
    if (cached == null) return null;
    return CrossRefChapter.fromJson(cached.payload, fromCache: true);
  }

  /// A cache that cannot be opened is a miss, not a failure: the reader still
  /// gets their references over the network.
  Future<CachedChapter?> _readCache(
    String sourceId,
    String book,
    int chapter,
  ) async {
    try {
      return await _cache?.read(
        kind: kind,
        sourceId: sourceId,
        book: book,
        chapter: chapter,
      );
    } catch (_) {
      return null;
    }
  }
}
