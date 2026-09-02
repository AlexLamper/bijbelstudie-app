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
/// the background screen inserted directly after Verdieping.
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
    slots.add(LessonSlot.of(step));
    if (withContext && step == StudyStep.depth) {
      slots.add(const LessonSlot.context());
    }
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
    this.summary,
  });

  final LessonSlot slot;
  final Set<LessonSlot> completed;

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
      viewTranslation: viewTranslation ?? this.viewTranslation,
      depthPanel: depthPanel ?? this.depthPanel,
      reflectionText: reflectionText ?? this.reflectionText,
      summary: summary ?? this.summary,
    );
  }
}
