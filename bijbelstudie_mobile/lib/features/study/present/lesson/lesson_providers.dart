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

/// One entry in the lesson's rail.
///
/// Nearly all of them are steps the server defined - [LessonPayload.steps] stays
/// the source of truth for those. [LessonSlot.context] is the exception: the
/// images and the book's background, which the client shows as a screen of its
/// own rather than as panels crammed into Verdieping. The server has no key for
/// it, so [serverStep] is null and no write ever names it.
class LessonSlot {
  const LessonSlot.of(this.serverStep);

  const LessonSlot.context() : serverStep = null;

  /// The step the server knows this slot as, or null for the client-only one.
  final StudyStep? serverStep;

  bool get isServerStep => serverStep != null;

  String get label => serverStep?.label ?? 'Achtergrond';

  @override
  bool operator ==(Object other) =>
      other is LessonSlot && other.serverStep == serverStep;

  @override
  int get hashCode => serverStep.hashCode;

  @override
  String toString() => 'LessonSlot(${serverStep?.id ?? 'context'})';
}

/// The rail the reader walks: the server's steps in the server's order, with
/// the background screen inserted directly *before* Verdieping.
///
/// Background comes first because it is orientation, not exposition: where this
/// happened and what the book is about is what you want in hand *before* the
/// uitleg, not after it. Reading the commentary and only then being shown the
/// place it describes puts the two in the wrong order.
///
/// [withContext] is the shell's answer to "is there anything to put on it" - a
/// photograph or a book introduction. Without one the slot is left out entirely
/// rather than opening onto an empty state.
List<LessonSlot> lessonSlots(
  List<StudyStep> steps, {
  required bool withContext,
}) {
  final slots = <LessonSlot>[];
  for (final step in steps) {
    if (withContext && step == StudyStep.depth) {
      slots.add(const LessonSlot.context());
    }
    slots.add(LessonSlot.of(step));
  }
  return List.unmodifiable(slots);
}

/// Where the reader is inside the lesson, and what they have written so far.
///
/// Held here rather than in the screen's State so the step body, the step rail
/// and the footer all read one truth, and so a rebuild from a translation
/// switch cannot lose the current step.
class LessonCursor {
  const LessonCursor({
    required this.slot,
    required this.completed,
    required this.viewTranslation,
    required this.depthPanel,
    required this.reflectionText,
    this.previouslyCompleted = false,
    this.summary,
  });

  /// Where a lesson opens, seeded from what the server saved about it.
  ///
  /// A lesson still in progress resumes where it was left: on the step `?stap=`
  /// names, else on the saved cursor, else on the first step - with the steps
  /// the server has as done lit in the rail. The background screen has no
  /// server key and is never in that list, so it counts as walked once the
  /// reader is at or past Verdieping, which is the only way to get there.
  ///
  /// A lesson the server has on record as *finished* opens as a new run: from
  /// the first step (or the one asked for), with nothing lit. Its saved
  /// `stepsCompleted` describe the previous run, and painting them over a rail
  /// whose reader is on step 1 says "you are starting" and "you are done" at
  /// once - and lights every step except the client-only one. The rail then
  /// shows this run only; [previouslyCompleted] keeps every step open to jump
  /// to, because the reading is not being skipped, it was done.
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

    final completed = <LessonSlot>{};
    if (!redo) {
      completed.addAll(
        state.stepsCompleted.where(steps.contains).map(LessonSlot.of),
      );
      // Being at or past Verdieping means the background screen before it has
      // been walked, whether or not it turns out to exist in this rail.
      final depth = steps.indexOf(StudyStep.depth);
      if (depth >= 0 &&
          (completed.contains(const LessonSlot.of(StudyStep.depth)) ||
              steps.indexOf(start) >= depth)) {
        completed.add(const LessonSlot.context());
      }
    }

    return LessonCursor(
      slot: LessonSlot.of(start),
      completed: completed,
      previouslyCompleted: redo,
      viewTranslation: state.viewTranslation ?? lesson.translation,
      depthPanel: state.depthPanel ?? 'media',
      reflectionText: state.reflectionText,
    );
  }

  final LessonSlot slot;

  /// The slots walked in *this* run. Never seeded from a finished lesson.
  final Set<LessonSlot> completed;

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

  /// Set once the lesson is finished; the shell then shows the summary card
  /// instead of a step.
  final CompletionSummary? summary;

  bool get isFinished => summary != null;

  LessonCursor copyWith({
    LessonSlot? slot,
    Set<LessonSlot>? completed,
    String? viewTranslation,
    String? depthPanel,
    String? reflectionText,
    CompletionSummary? summary,
  }) {
    return LessonCursor(
      slot: slot ?? this.slot,
      completed: completed ?? this.completed,
      previouslyCompleted: previouslyCompleted,
      viewTranslation: viewTranslation ?? this.viewTranslation,
      depthPanel: depthPanel ?? this.depthPanel,
      reflectionText: reflectionText ?? this.reflectionText,
      summary: summary ?? this.summary,
    );
  }
}
