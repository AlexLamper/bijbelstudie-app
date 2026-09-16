import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/present/auth_controller.dart';
import '../../../core/api/api_client.dart';
import '../domain/chapter_study_models.dart';
import 'lesson_repository.dart';

final chapterStudyRepositoryProvider = Provider((ref) {
  return ChapterStudyRepository(ref.watch(apiClientProvider));
});

/// One chapter as a single-chapter study. Loaded once per open; the lesson
/// state and every write then go through [LessonRepository] with the study id
/// and lesson day this returns.
final chapterStudyProvider = FutureProvider.autoDispose
    .family<ChapterStudy, ChapterStudyKey>((ref, key) {
      return ref.watch(chapterStudyRepositoryProvider).get(key);
    });

class ChapterStudyRepository {
  ChapterStudyRepository(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /chapter-study/:book/:chapter`. `client=app` makes the server filter
  /// the commentary and translation to what the app is licensed to show, also
  /// for a request that happens to carry no token.
  Future<ChapterStudy> get(ChapterStudyKey key) async {
    try {
      final response = await _apiClient.dio.get(
        '/chapter-study/${Uri.encodeComponent(key.book)}/${key.chapter}',
        queryParameters: const {'client': 'app'},
      );
      final study = ChapterStudy.fromJson(response.data as Map<String, dynamic>);
      if (study == null) {
        throw const LessonException('Dit hoofdstuk kon niet worden geladen.');
      }
      return study;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const LessonException('Dit hoofdstuk bestaat niet.');
      }
      throw const LessonException('Dit hoofdstuk kon niet worden geladen.');
    }
  }
}
