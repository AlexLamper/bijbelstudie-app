import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';

final studyProgressRepositoryProvider = Provider((ref) {
  return StudyProgressRepository(ref.watch(apiClientProvider));
});

/// `GET`/`POST /api/v1/study-progress` - the account's record of which curated
/// lessons are finished.
///
/// The endpoint already existed for `/studie` on the website; nothing new was
/// added for the app. `POST` is idempotent per (study, lesson) and awards XP
/// server-side, so a lesson ticked twice costs nothing.
///
/// Every call here is best effort. The reader may be signed out or offline and
/// the study still has to work, so a failure resolves to "the server knows
/// nothing" rather than an error the screen has to render.
class StudyProgressRepository {
  StudyProgressRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Completed lesson days per study id, from the endpoint's `lessonsByStudy`.
  Future<Map<String, Set<int>>> getCompletedLessons() async {
    // Preview runs on canned data and must never touch a real account.
    if (PreviewConfig.enabled) return const {};

    try {
      final response = await _apiClient.dio.get('/study-progress');
      final data = response.data as Map<String, dynamic>;
      final byStudy =
          data['lessonsByStudy'] as Map<String, dynamic>? ?? const {};
      return {
        for (final entry in byStudy.entries)
          entry.key: (entry.value as List? ?? const [])
              .whereType<num>()
              .map((d) => d.toInt())
              .toSet(),
      };
    } on DioException {
      return const {};
    } catch (_) {
      return const {};
    }
  }

  /// Records one curated lesson as studied. Returns true when the server took
  /// it, false when it could not be reached - the device copy stands either
  /// way.
  Future<bool> recordLesson({
    required String studyId,
    required int lessonDay,
    required String book,
    required int chapter,
    int? verseStart,
    int? verseEnd,
  }) async {
    if (PreviewConfig.enabled) return false;

    try {
      await _apiClient.dio.post(
        '/study-progress',
        data: {
          'source': 'curated',
          'studyId': studyId,
          'lessonDay': lessonDay,
          'book': book,
          'chapter': chapter,
          if (verseStart != null) 'verseStart': verseStart,
          if (verseEnd != null) 'verseEnd': verseEnd,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
