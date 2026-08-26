import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/studies_repository.dart';
import '../data/study_models.dart';
import '../data/study_plan_store.dart';
import '../data/study_progress_repository.dart';

final curatedStudiesProvider = FutureProvider.autoDispose<List<CuratedStudy>>((
  ref,
) {
  return ref.watch(studiesRepositoryProvider).getCuratedStudies();
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
