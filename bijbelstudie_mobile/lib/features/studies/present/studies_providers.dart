import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/provider_cache.dart';

import '../data/enrollment_models.dart';
import '../data/enrollment_repository.dart';
import '../data/studies_repository.dart';
import '../data/study_models.dart';
import '../data/study_plan_store.dart';
import '../data/study_progress_repository.dart';

final _rawCuratedStudiesProvider =
    FutureProvider.autoDispose<List<CuratedStudy>>((ref) {
      ref.cacheFor();
      return ref.watch(studiesRepositoryProvider).getCuratedStudies();
    });

/// The curated studies, with finished ones sunk to the bottom so a completed
/// study stops being the first thing shown here and on the dashboard's
/// recommendations, which reads this same provider.
///
/// The fetch itself is delegated to [_rawCuratedStudiesProvider] so marking a
/// lesson done - which changes [studyPlansProvider] and
/// [serverStudyLessonsProvider] - only resorts the cached list instead of
/// hitting the network again.
final curatedStudiesProvider = FutureProvider.autoDispose<List<CuratedStudy>>((
  ref,
) async {
  final list = await ref.watch(_rawCuratedStudiesProvider.future);
  final plans = ref.watch(studyPlansProvider);
  final serverLessons =
      ref.watch(serverStudyLessonsProvider).value ?? const <String, Set<int>>{};
  // Authored studies lead, then the generated book studies in canonical order,
  // then anything finished. The catalogue now carries all seventy-seven, and
  // the first few entries are what the dashboard recommends - left in server
  // order that would be Genesis, Exodus, Leviticus, which is a worse answer to
  // "what should I read" than the eleven written studies.
  final authored = <CuratedStudy>[];
  final books = <CuratedStudy>[];
  final finished = <CuratedStudy>[];
  for (final study in list) {
    if (isStudyFinished(study: study, plans: plans, serverLessons: serverLessons)) {
      finished.add(study);
    } else if (study.type == 'Boek') {
      books.add(study);
    } else {
      authored.add(study);
    }
  }
  return [...authored, ...books, ...finished];
});

/// One study by id, for the detail screen reached through `/studies/:id`.
///
/// Derived from [curatedStudiesProvider] rather than fetched on its own: the
/// list endpoint is the only one there is, and it is already cached by ETag.
final curatedStudyProvider = FutureProvider.autoDispose
    .family<CuratedStudy?, String>((ref, id) async {
      final studies = await ref.watch(curatedStudiesProvider.future);
      for (final study in studies) {
        if (study.id == id) return study;
      }
      return null;
    });

/// The account's completed lessons, per study id.
///
/// Never gated on by the UI: it resolves to an empty map when signed out or
/// offline, and the screens read it through `.value ?? const {}` so a slow or
/// failing request cannot hold up a study that works from the device copy.
final serverStudyLessonsProvider =
    FutureProvider.autoDispose<Map<String, Set<int>>>((ref) {
      ref.cacheFor();
      return ref.watch(studyProgressRepositoryProvider).getCompletedLessons();
    });

/// What the reader has finished, wherever it was recorded.
///
/// The device copy and the account's copy are both partial - one survives being
/// offline, the other survives a reinstall - so a lesson counts as done if
/// either of them says so.
Set<int> mergedCompletedDays({
  required String studyId,
  required Map<String, StudyPlan> plans,
  required Map<String, Set<int>> serverLessons,
}) {
  return {...?plans[studyId]?.completedDays, ...?serverLessons[studyId]};
}

/// Whether every lesson in [study] has been completed, merging the device and
/// account copies the same way [mergedCompletedDays] does.
bool isStudyFinished({
  required CuratedStudy study,
  required Map<String, StudyPlan> plans,
  required Map<String, Set<int>> serverLessons,
}) {
  final total = study.lessonCount;
  if (total == 0) return false;
  final done = mergedCompletedDays(
    studyId: study.id,
    plans: plans,
    serverLessons: serverLessons,
  ).length;
  return done >= total;
}

/// Every study this account has started, keyed by study id.
///
/// Resolves to an empty map when signed out or offline, exactly like
/// [serverStudyLessonsProvider], so the catalogue still renders for a visitor -
/// they simply see no progress and no "Mijn studies".
final studyEnrollmentsProvider =
    FutureProvider.autoDispose<Map<String, StudyEnrollment>>((ref) async {
      ref.cacheFor();
      try {
        final enrollments = await ref.watch(enrollmentRepositoryProvider).list();
        return {for (final enrollment in enrollments) enrollment.studyId: enrollment};
      } on EnrollmentException {
        return const {};
      }
    });

/// The enrollment for one study, or null when it was never started.
final studyEnrollmentProvider = Provider.autoDispose
    .family<StudyEnrollment?, String>((ref, studyId) {
      final enrollments = ref.watch(studyEnrollmentsProvider).value;
      return enrollments?[studyId];
    });

/// Which section of the catalogue is on screen.
/// The one filter row on Studies · Ontdek.
///
/// The redesign collapses what used to be three separate controls — the
/// Ontdek/Mijn/Voltooid tabs, the four topic tiles and the kind pills — into a
/// single scrollable chip row. The four discovery chips come first because
/// they are the ones that fit on a 390px screen without scrolling; the two
/// chips about this reader follow, so nothing that worked before is gone.
enum StudiesFilter {
  forYou('Voor jou'),
  books('Bijbelboeken'),
  people('Personen'),
  themes("Thema's"),
  mine('Mijn studies'),
  completed('Voltooid');

  const StudiesFilter(this.label);

  final String label;
}

final studiesFilterProvider =
    NotifierProvider<StudiesFilterController, StudiesFilter>(
      StudiesFilterController.new,
    );

class StudiesFilterController extends Notifier<StudiesFilter> {
  @override
  StudiesFilter build() => StudiesFilter.forYou;

  void select(StudiesFilter filter) => state = filter;
}

/// What the reader typed into the search field. Filtering happens over the
/// loaded catalogue, so this never triggers a request.
final studiesQueryProvider = NotifierProvider<StudiesQueryController, String>(
  StudiesQueryController.new,
);

class StudiesQueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// How a study looks to the reader right now: how far along it is, and whether
/// it is finished. Merges the enrollment with both completion ledgers.
class StudyStatus {
  const StudyStatus({
    required this.completedDays,
    required this.total,
    required this.completed,
    this.enrollment,
  });

  final Set<int> completedDays;
  final int total;
  final bool completed;
  final StudyEnrollment? enrollment;

  int get done => completedDays.length;

  bool get started => done > 0 || enrollment != null;

  double get progress => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);

  int get progressPercent => (progress * 100).round();

  /// The lesson "ga verder" should open: where the server left the cursor when
  /// there is an enrollment, otherwise the first lesson not yet ticked off.
  int resumeDay(CuratedStudy study) {
    final cursor = enrollment?.currentLessonDay;
    if (cursor != null && study.lessonForDay(cursor) != null) return cursor;
    for (final lesson in study.lessons) {
      if (!completedDays.contains(lesson.day)) return lesson.day;
    }
    return study.firstLesson?.day ?? 1;
  }
}

/// [StudyStatus] for one study, assembled from everything that knows about it.
final studyStatusProvider = Provider.autoDispose.family<StudyStatus, CuratedStudy>((
  ref,
  study,
) {
  final plans = ref.watch(studyPlansProvider);
  final serverLessons =
      ref.watch(serverStudyLessonsProvider).value ?? const <String, Set<int>>{};
  final enrollment = ref.watch(studyEnrollmentProvider(study.id));

  final days = mergedCompletedDays(
    studyId: study.id,
    plans: plans,
    serverLessons: serverLessons,
  );

  return StudyStatus(
    completedDays: days,
    total: study.lessonCount,
    completed:
        enrollment?.isCompleted ??
        isStudyFinished(study: study, plans: plans, serverLessons: serverLessons),
    enrollment: enrollment,
  );
});

/// The study the "verder waar je was" row on Studies · Ontdek offers.
///
/// Derived, not stored: the first study in catalogue order that is started and
/// not finished. The enrollment carries no "last opened" timestamp, so there is
/// nothing more recent to sort on — catalogue order at least keeps the answer
/// stable between builds instead of shuffling under the reader.
final continueStudyProvider = Provider.autoDispose<CuratedStudy?>((ref) {
  final all = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];
  for (final study in all) {
    final status = ref.watch(studyStatusProvider(study));
    if (status.started && !status.completed) return study;
  }
  return null;
});

/// How far along a single bible book is, for the tiles on Alle studies.
enum BookProgress {
  /// Every study that covers this book is finished.
  done,

  /// At least one study covering it has been started.
  started,

  /// Nothing here yet — also the answer for a book no study covers.
  none,
}

/// Book name → [BookProgress], read straight off the study statuses the rest
/// of the app already computes. Nothing is stored and no endpoint is called:
/// this is [studyStatusProvider] regrouped by the books each study covers.
final bookProgressProvider = Provider.autoDispose<Map<String, BookProgress>>((ref) {
  final all = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];
  final result = <String, BookProgress>{};

  for (final study in all) {
    final status = ref.watch(studyStatusProvider(study));
    if (!status.started) continue;
    final progress = status.completed ? BookProgress.done : BookProgress.started;
    for (final book in study.books) {
      // A finished study wins over a merely started one, so a book covered by
      // both does not read as unfinished.
      if (result[book] == BookProgress.done) continue;
      result[book] = progress;
    }
  }

  return result;
});

/// The study a book tile opens: the one that starts in that book, falling back
/// to the first study that covers it at all. Null when the catalogue has none,
/// in which case the tile is not tappable.
final studyForBookProvider = Provider.autoDispose.family<CuratedStudy?, String>((
  ref,
  book,
) {
  final all = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];
  for (final study in all) {
    if (study.startBook == book) return study;
  }
  for (final study in all) {
    if (study.books.contains(book)) return study;
  }
  return null;
});

/// How many studies the reader has begun, for the counts in the two headers.
final startedStudyCountProvider = Provider.autoDispose<int>((ref) {
  final all = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];
  return all.where((study) => ref.watch(studyStatusProvider(study)).started).length;
});
