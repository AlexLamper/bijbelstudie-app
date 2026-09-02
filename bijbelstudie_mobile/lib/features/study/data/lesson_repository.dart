import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import '../../studies/data/enrollment_models.dart';
import '../domain/lesson_models.dart';

final lessonRepositoryProvider = Provider((ref) {
  return LessonRepository(ref.watch(apiClientProvider));
});

/// A lesson could not be read or written.
class LessonException implements Exception {
  const LessonException(this.message, {this.needsEnrollment = false, this.isUnauthorized = false});

  final String message;

  /// The server refuses a lesson for a study you never started. The fix is to
  /// send the reader back to the detail screen to start it, not to retry.
  final bool needsEnrollment;

  final bool isUnauthorized;

  @override
  String toString() => message;
}

/// Reads lesson content and owns every write to the lesson cursor.
///
/// All mutations funnel through [patch] exactly as the website's
/// `StudyFlowShell` does. One writer means the step cursor, the reflection and
/// the completion flag can never disagree about what the reader last did.
class LessonRepository {
  LessonRepository(this._apiClient);

  final ApiClient _apiClient;

  /// The lesson itself: steps, passage, translation, commentary and prose.
  Future<LessonPayload> getLesson(String studyId, int day) async {
    try {
      final response = await _apiClient.dio.get('/studies/$studyId/lessons/$day');
      return LessonPayload.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _translate(e, 'Deze les kon niet worden geladen.');
    }
  }

  /// The reader's saved position in this lesson. A lesson never opened has no
  /// state yet, which is not an error - it comes back empty.
  Future<LessonState> getState(String studyId, int day) async {
    try {
      final response = await _apiClient.dio.get(
        '/study-lesson-state',
        queryParameters: {'studyId': studyId, 'day': day},
      );
      final data = response.data as Map<String, dynamic>;
      final state = data['state'];
      if (state is! Map<String, dynamic>) return const LessonState();
      return LessonState.fromJson(state);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const LessonState();
      throw _translate(e, 'Je voortgang kon niet worden geladen.');
    }
  }

  /// The single writer.
  ///
  /// [complete] is the only branch that grants XP, promotes the reflection into
  /// a note and rolls the enrollment on to the next lesson, so it must be sent
  /// once per lesson and only from the last step.
  Future<LessonPatchResult> patch(
    String studyId,
    int day, {
    StudyStep? currentStep,
    StudyStep? completeStep,
    String? viewTranslation,
    String? depthPanel,
    String? reflectionText,
    bool? complete,
  }) async {
    try {
      final response = await _apiClient.dio.patch(
        '/study-lesson-state',
        data: {
          'studyId': studyId,
          'lessonDay': day,
          if (currentStep != null) 'currentStep': currentStep.id,
          if (completeStep != null) 'completeStep': completeStep.id,
          if (viewTranslation != null) 'viewTranslation': viewTranslation,
          if (depthPanel != null) 'depthPanel': depthPanel,
          if (reflectionText != null) 'reflectionText': reflectionText,
          if (complete != null) 'complete': complete,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final completion = data['completion'];

      return LessonPatchResult(
        state: data['state'] is Map<String, dynamic>
            ? LessonState.fromJson(data['state'] as Map<String, dynamic>)
            : const LessonState(),
        completion: completion is Map<String, dynamic>
            ? CompletionSummary.fromJson(completion)
            : null,
      );
    } on DioException catch (e) {
      throw _translate(e, 'Je voortgang kon niet worden opgeslagen.');
    }
  }

  /// The five quiz questions for this lesson, or why there are none.
  Future<LessonQuiz> getQuiz(String studyId, int day) async {
    try {
      final response = await _apiClient.dio.get(
        '/study-quiz',
        queryParameters: {'studyId': studyId, 'day': day},
      );
      return LessonQuiz.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      // A quiz that cannot be fetched must never block finishing the lesson,
      // so this degrades to the same empty state the server would have sent.
      if (e.response == null || (e.response?.statusCode ?? 500) >= 500) {
        return const LessonQuiz(
          available: false,
          reason: QuizUnavailableReason.unavailable,
        );
      }
      throw _translate(e, 'De quiz kon niet worden geladen.');
    }
  }

  /// Save the reader's picks without grading them. Called on every tap so a
  /// half-finished quiz survives leaving the lesson.
  Future<void> saveQuizAnswers(
    String studyId,
    int day,
    Map<String, String> answers,
  ) async {
    if (answers.isEmpty) return;
    try {
      await _apiClient.dio.put(
        '/study-quiz',
        data: {
          'studyId': studyId,
          'lessonDay': day,
          'answers': [
            for (final entry in answers.entries)
              {'id': entry.key, 'answerId': entry.value},
          ],
        },
      );
    } on DioException {
      // Best effort: the grading POST sends the full set anyway.
    }
  }

  /// Grade the quiz. Only questions the server served can be graded.
  Future<QuizResult> gradeQuiz(
    String studyId,
    int day,
    Map<String, String> answers,
  ) async {
    try {
      final response = await _apiClient.dio.post(
        '/study-quiz',
        data: {
          'studyId': studyId,
          'lessonDay': day,
          'answers': [
            for (final entry in answers.entries)
              {'id': entry.key, 'answerId': entry.value},
          ],
        },
      );
      final data = response.data as Map<String, dynamic>;
      return QuizResult(
        score: (data['score'] as num?)?.toInt() ?? 0,
        total: (data['total'] as num?)?.toInt() ?? answers.length,
        correctAnswers: {
          for (final entry in (data['results'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
            if (entry['id'] is String)
              entry['id'] as String: entry['correct'] as bool? ?? false,
        },
      );
    } on DioException catch (e) {
      throw _translate(e, 'De quiz kon niet worden nagekeken.');
    }
  }

  LessonException _translate(DioException e, String fallback) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return const LessonException(
        'Meld je aan om deze les te openen.',
        isUnauthorized: true,
      );
    }
    // The lesson endpoint 404s both for an unknown lesson and for a study this
    // account never enrolled in; the detail screen can resolve either.
    if (status == 404) {
      return const LessonException(
        'Start deze studie om de les te openen.',
        needsEnrollment: true,
      );
    }
    return LessonException(fallback);
  }
}

class LessonPatchResult {
  const LessonPatchResult({required this.state, this.completion});

  final LessonState state;
  final CompletionSummary? completion;
}

class QuizResult {
  const QuizResult({
    required this.score,
    required this.total,
    required this.correctAnswers,
  });

  final int score;
  final int total;

  /// Question id to whether the reader got it right.
  final Map<String, bool> correctAnswers;
}
