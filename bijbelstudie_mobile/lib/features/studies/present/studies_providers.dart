import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/studies_repository.dart';
import '../data/study_models.dart';

final curatedStudiesProvider = FutureProvider.autoDispose<List<CuratedStudy>>((ref) {
  return ref.watch(studiesRepositoryProvider).getCuratedStudies();
});

final biblePlansProvider =
    FutureProvider.autoDispose.family<List<BiblePlan>, String?>((ref, type) {
      return ref.watch(studiesRepositoryProvider).getPlans(type: type);
    });
