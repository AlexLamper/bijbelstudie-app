import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../studies/data/enrollment_models.dart';
import '../../data/lesson_repository.dart';
import '../../domain/lesson_models.dart';

/// Which lesson is on screen. A value type so the providers below can be a
/// family keyed on it and still dedupe correctly.
class LessonRef {
  const LessonRef(this.studyId, this.day);

  final String studyId;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is LessonRef && other.studyId == studyId && other.day == day;

  @override
  int get hashCode => Object.hash(studyId, day);
}

/// The lesson content: steps, passage, prose, commentary id.
final lessonProvider = FutureProvider.autoDispose.family<LessonPayload, LessonRef>((
  ref,
  lesson,
) {
  return ref.watch(lessonRepositoryProvider).getLesson(lesson.studyId, lesson.day);
});

/// The reader's saved position in this lesson, loaded once when it opens.
///
/// After that the shell owns the live copy: every write returns the updated
/// state, so re-reading this provider mid-lesson would only race the writes.
final lessonStateProvider = FutureProvider.autoDispose.family<LessonState, LessonRef>((
  ref,
  lesson,
) {
  return ref.watch(lessonRepositoryProvider).getState(lesson.studyId, lesson.day);
});

/// The quiz for this lesson, or the reason there is none.
final lessonQuizProvider = FutureProvider.autoDispose.family<LessonQuiz, LessonRef>((
  ref,
  lesson,
) {
  return ref.watch(lessonRepositoryProvider).getQuiz(lesson.studyId, lesson.day);
});

/// Where the reader is inside the lesson, and what they have written so far.
///
/// Held here rather than in the screen's State so the step body, the step rail
/// and the footer all read one truth, and so a rebuild from a translation
/// switch cannot lose the current step.
class LessonCursor {
  const LessonCursor({
    required this.step,
    required this.completed,
    required this.viewTranslation,
    required this.depthPanel,
    required this.reflectionText,
    this.summary,
  });

  final StudyStep step;
  final Set<StudyStep> completed;

  /// The translation being read right now - the lesson's own, until switched.
  final String viewTranslation;

  /// `media`, `original` or `notes`.
  final String depthPanel;

  final String reflectionText;

  /// Set once the lesson is finished; the shell then shows the summary card
  /// instead of a step.
  final CompletionSummary? summary;

  bool get isFinished => summary != null;

  LessonCursor copyWith({
    StudyStep? step,
    Set<StudyStep>? completed,
    String? viewTranslation,
    String? depthPanel,
    String? reflectionText,
    CompletionSummary? summary,
  }) {
    return LessonCursor(
      step: step ?? this.step,
      completed: completed ?? this.completed,
      viewTranslation: viewTranslation ?? this.viewTranslation,
      depthPanel: depthPanel ?? this.depthPanel,
      reflectionText: reflectionText ?? this.reflectionText,
      summary: summary ?? this.summary,
    );
  }
}
