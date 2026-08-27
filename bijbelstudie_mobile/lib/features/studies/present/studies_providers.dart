import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/studies_repository.dart';
import '../data/study_models.dart';
import '../data/study_plan_store.dart';
import '../data/study_progress_repository.dart';

final _rawCuratedStudiesProvider =
    FutureProvider.autoDispose<List<CuratedStudy>>((ref) {
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
  final active = <CuratedStudy>[];
  final finished = <CuratedStudy>[];
  for (final study in list) {
    (isStudyFinished(study: study, plans: plans, serverLessons: serverLessons)
            ? finished
            : active)
        .add(study);
  }
  return [...active, ...finished];
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
