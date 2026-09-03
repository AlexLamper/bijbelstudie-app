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
    Options? options,
  }) async {
    try {
      final response = await _apiClient.dio.patch(
        '/study-lesson-state',
        options: options,
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

  /// The completing write, with the retries the plain [patch] does not do.
  ///
  /// `complete: true` is by far the heaviest request this app makes: on the
  /// server it claims the ledger row, grants XP, counts every completed lesson
  /// in the study, copies the reflection into a real note - reading the passage
  /// text to do it - and rolls the enrollment on. On a cold serverless start
  /// that comfortably outruns the client's 15s receive timeout, and the reader
  /// then sees "Je voortgang kon niet worden opgeslagen." for a lesson the
  /// server did in fact record. The same is true of any 5xx thrown *after* the
  /// ledger row was claimed.
  ///
  /// So this branch does three things the others do not:
  ///
  /// 1. Allows the request 60s rather than 15.
  /// 2. Retries once on a transient failure. Safe because the server dedupes:
  ///    `recordLessonCompletion` claims the row with an upsert and answers a
  ///    second attempt with `recorded: false, reason: ALREADY_RECORDED`.
  /// 3. If it still fails, re-reads the lesson state. `completedAt` set there
  ///    means the work landed and only the response was lost, which is a
  ///    success the reader must not be shown an error for.
  ///
  /// Only when all three come up empty does this throw.
  Future<LessonPatchResult> complete(
    String studyId,
    int day, {
    required StudyStep completeStep,
    String? reflectionText,
  }) async {
    LessonException? failure;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await patch(
          studyId,
          day,
          completeStep: completeStep,
          // The reflection travels with the completing write rather than being
          // assumed to have landed already. Its autosave is debounced and
          // fire-and-forget, and the flush the step does on its way out races
          // the step transition that disposes it - so a reader who types and
          // taps straight on can reach here with nothing saved. The server
          // promotes whatever text this document holds, so sending it here is
          // what decides whether the note carries their words or is skipped.
          reflectionText: reflectionText,
          complete: true,
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
      } on LessonException catch (e) {
        // A dead session or a study this account never started will not fix
        // itself on a second try, and the screen has a real answer for both.
        if (e.isUnauthorized || e.needsEnrollment) rethrow;
        failure = e;
      }
    }

    // Last word: did it land anyway?
    try {
      final state = await getState(studyId, day);
      if (state.isCompleted) {
        return LessonPatchResult(
          state: state,
          // Nothing to celebrate with - the response that carried the XP is
          // the one that was lost - but the lesson is finished, which is what
          // the summary card needs to know.
          completion: const CompletionSummary(
            recorded: false,
            studyCompleted: false,
            reason: 'ALREADY_RECORDED',
          ),
        );
      }
    } on LessonException {
      // The verification read failed too; fall through to the original error.
    }

    throw failure ?? const LessonException('Je voortgang kon niet worden opgeslagen.');
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
      return QuizResult.fromJson(
        response.data as Map<String, dynamic>,
        fallbackTotal: answers.length,
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

/// How one question was marked, as `POST /study-quiz` reports it.
///
/// The correct answer only ever travels back *after* the reader has answered -
/// grading happens on bijbelquiz and this app never holds the key beforehand -
/// so this is the only place the review screen can learn what was right.
class QuizGrade {
  const QuizGrade({
    required this.questionId,
    required this.correct,
    this.known = true,
    this.correctAnswerId,
    this.explanation,
    this.bibleReference,
  });

  final String questionId;
  final bool correct;

  /// False when the grader did not recognise the question, in which case
  /// [correct] means nothing and the review must stay silent about it.
  final bool known;

  /// The answer that was right. Null for an unknown question, and sometimes
  /// simply absent - the review then says right or wrong and no more.
  final String? correctAnswerId;

  /// The grader's own note on the question. Never written here: an invented
  /// explanation is worse than none.
  final String? explanation;

  final String? bibleReference;

  static QuizGrade? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return QuizGrade(
      questionId: id,
      correct: json['correct'] as bool? ?? false,
      known: json['known'] as bool? ?? true,
      correctAnswerId: _text(json['correctAnswerId']),
      explanation: _text(json['explanation']),
      bibleReference: _text(json['bibleReference']),
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class QuizResult {
  const QuizResult({
    required this.score,
    required this.total,
    this.grades = const [],
  });

  final int score;
  final int total;

  /// Per question, in the order the server marked them.
  final List<QuizGrade> grades;

  /// Question id to whether the reader got it right.
  Map<String, bool> get correctAnswers => {
    for (final grade in grades) grade.questionId: grade.correct,
  };

  QuizGrade? gradeFor(String questionId) {
    for (final grade in grades) {
      if (grade.questionId == questionId) return grade;
    }
    return null;
  }

  /// True when the server sent enough to show the reader what they got wrong.
  bool get hasReview => grades.any((grade) => grade.known);

  factory QuizResult.fromJson(
    Map<String, dynamic> json, {
    int fallbackTotal = 0,
  }) {
    final grades = (json['results'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(QuizGrade.fromJson)
        .whereType<QuizGrade>()
        .toList(growable: false);
    return QuizResult(
      score: (json['score'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? fallbackTotal,
      grades: grades,
    );
  }
}
