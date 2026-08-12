import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/db/content_cache.dart';
import '../../auth/present/auth_controller.dart';
import '../../bible/domain/bible_models.dart';

final commentaryRepositoryProvider = Provider((ref) {
  return CommentaryRepository(ref.watch(apiClientProvider), ref.watch(contentCacheProvider));
});

class CommentaryRepository {
  CommentaryRepository(this._apiClient, this._cache);

  final ApiClient _apiClient;
  final ContentCache? _cache;

  static const _kind = 'commentary';

  Future<List<BibleSource>> getCommentaries() async {
    final response = await _apiClient.dio.get('/commentaries');
    final data = response.data as Map<String, dynamic>;
    return (data['commentaries'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(BibleSource.fromJson)
        .toList();
  }

  Future<List<String>> getBooks(String commentaryId) async {
    try {
      final response = await _apiClient.dio.get('/commentaries/$commentaryId/books');
      final data = response.data as Map<String, dynamic>;
      return (data['books'] as List<dynamic>).map((e) => e.toString()).toList();
    } on DioException catch (e) {
      throw _mapError(e, commentaryId);
    }
  }

  /// One commentary chapter.
  ///
  /// Two shapes come back from the corpus and both are normal:
  ///  - Matthew Henry keys its chapter introduction as verse **0**;
  ///  - Dachsel's entries are HTML fragments (`<ol><li><div class="s9">...`).
  /// The renderer handles both; see `commentary_html.dart`.
  Future<ChapterContent> getChapter(String commentaryId, String book, int chapter) async {
    final path = '/commentaries/$commentaryId/${Uri.encodeComponent(book)}/$chapter';

    final cached = await _cache?.read(
      kind: _kind,
      sourceId: commentaryId,
      book: book,
      chapter: chapter,
    );

    try {
      final response = await _apiClient.dio.get(
        path,
        options: Options(
          headers: cached?.etag == null ? null : {'If-None-Match': cached!.etag},
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (response.statusCode == 304 && cached != null) {
        await _cache?.touchFetchedAt(
          kind: _kind,
          sourceId: commentaryId,
          book: book,
          chapter: chapter,
        );
        return ChapterContent.fromJson(cached.payload, fromCache: true);
      }

      final data = response.data as Map<String, dynamic>;
      await _cache?.write(
        kind: _kind,
        sourceId: commentaryId,
        book: book,
        chapter: chapter,
        payload: data,
        etag: response.headers.value('etag'),
      );
      return ChapterContent.fromJson(data);
    } on DioException catch (e) {
      if (cached != null) return ChapterContent.fromJson(cached.payload, fromCache: true);
      throw _mapError(e, commentaryId);
    }
  }

  Object _mapError(DioException e, String sourceId) {
    if (e.response?.statusCode == 451) return ContentNotLicensedException(sourceId);
    return e;
  }
}
