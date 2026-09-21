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
final lessonProvider = FutureProvider.autoDispose
    .family<LessonPayload, LessonRef>((ref, lesson) {
      return ref
          .watch(lessonRepositoryProvider)
          .getLesson(lesson.studyId, lesson.day);
    });

/// The reader's saved position in this lesson, loaded once when it opens.
///
/// After that the shell owns the live copy: every write returns the updated
/// state, so re-reading this provider mid-lesson would only race the writes.
final lessonStateProvider = FutureProvider.autoDispose
    .family<LessonState, LessonRef>((ref, lesson) {
      return ref
          .watch(lessonRepositoryProvider)
          .getState(lesson.studyId, lesson.day);
    });

/// The quiz for this lesson, or the reason there is none.
final lessonQuizProvider = FutureProvider.autoDispose
    .family<LessonQuiz, LessonRef>((ref, lesson) {
      return ref
          .watch(lessonRepositoryProvider)
          .getQuiz(lesson.studyId, lesson.day);
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
    this.practicesDone = const {},
    this.previouslyCompleted = false,
    this.summary,
  });

  /// Where a lesson opens, seeded from what the server saved about it.
  ///
  /// A lesson still in progress resumes where it was left: on the step `?stap=`
  /// names, else on the saved cursor, else on the first step - with the steps
  /// the server has as done lit in the rail.
  ///
  /// A lesson the server has on record as *finished* opens as a new run: from
  /// the first step (or the one asked for), with nothing lit. Its saved
  /// `stepsCompleted` describe the previous run, and painting them over a rail
  /// whose reader is on step 1 says "you are starting" and "you are done" at
  /// once. The rail then shows this run only; [previouslyCompleted] keeps every
  /// step open to jump to, because the reading is not being skipped, it was
  /// done.
  factory LessonCursor.seed({
    required LessonPayload lesson,
    required LessonState state,
    String? initialStep,
  }) {
    final steps = lesson.steps;
    final redo = state.isCompleted;
    final fromUrl = StudyStep.tryFromId(initialStep);
    final saved = state.currentStep;
    final start =
        [
          if (fromUrl != null && steps.contains(fromUrl)) fromUrl,
          if (!redo && saved != null && steps.contains(saved)) saved,
          if (steps.isNotEmpty) steps.first,
        ].firstOrNull ??
        StudyStep.word;

    return LessonCursor(
      step: start,
      completed: redo
          ? const {}
          : state.stepsCompleted.where(steps.contains).toSet(),
      previouslyCompleted: redo,
      viewTranslation: state.viewTranslation ?? lesson.translation,
      depthPanel: state.depthPanel ?? 'media',
      reflectionText: state.reflectionText,
      // Ticks survive a redo: they record what the reader did with the
      // passage, not how far they got through the lesson.
      practicesDone: state.practicesDone.toSet(),
    );
  }

  final StudyStep step;

  /// The steps walked in *this* run. Never seeded from a finished lesson.
  final Set<StudyStep> completed;

  /// The server already had this lesson as finished when it was opened: the
  /// reader is going through it again. Every step is fair to jump to, and the
  /// completing write will come back as already recorded.
  final bool previouslyCompleted;

  /// The translation being read right now - the lesson's own, until switched.
  final String viewTranslation;

  /// Which pane Verdieping is showing: `original` for the grondtekst, anything
  /// else for the uitleg. The server's older values (`media`, `notes`) name
  /// panels that no longer live there and simply read as the uitleg.
  final String depthPanel;

  final String reflectionText;

  /// The practices ticked on Toepassing, by their exact text. Held here rather
  /// than in the step so a tick survives walking away and back.
  final Set<String> practicesDone;

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
    Set<String>? practicesDone,
    CompletionSummary? summary,
  }) {
    return LessonCursor(
      step: step ?? this.step,
      completed: completed ?? this.completed,
      previouslyCompleted: previouslyCompleted,
      viewTranslation: viewTranslation ?? this.viewTranslation,
      depthPanel: depthPanel ?? this.depthPanel,
      reflectionText: reflectionText ?? this.reflectionText,
      practicesDone: practicesDone ?? this.practicesDone,
      summary: summary ?? this.summary,
    );
  }
}
