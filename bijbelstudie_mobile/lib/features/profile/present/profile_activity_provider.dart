import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notes/domain/note_models.dart';
import '../../notes/present/notes_providers.dart';
import '../../studies/data/study_models.dart';
import '../../studies/data/study_plan_store.dart';
import '../../studies/present/studies_providers.dart';
import '../domain/profile_activity.dart';
import 'profile_stats_provider.dart';

/// Which pill in the filter bar is selected.
final profileActivityFilterProvider =
    NotifierProvider<ProfileActivityFilterController, ProfileActivityFilter>(
      ProfileActivityFilterController.new,
    );

class ProfileActivityFilterController extends Notifier<ProfileActivityFilter> {
  @override
  ProfileActivityFilter build() => ProfileActivityFilter.all;

  void select(ProfileActivityFilter filter) => state = filter;
}

/// How many entries the feed shows before it stops. The sources are unbounded
/// - a heavy user has hundreds of highlights - and the profile screen is not a
/// notes browser.
const int _kFeedLimit = 24;

/// The activity feed, assembled on the device.
///
/// There is no `/activity` endpoint, so this folds together the records the app
/// already has: highlights, notes, the study plans in shared_preferences plus
/// the lessons the account has completed, and the badges that are unlocked.
/// Entries without a timestamp (badges, a study only the server knows about)
/// sink below the dated ones rather than being given an invented date.
final profileActivityProvider = Provider.autoDispose<List<ProfileActivity>>((
  ref,
) {
  final highlights =
      ref.watch(highlightsListProvider).value ?? const <StudyNote>[];
  final notes = ref.watch(notesListProvider).value ?? const <StudyNote>[];
  final plans = ref.watch(studyPlansProvider);
  final studies =
      ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];
  final serverLessons =
      ref.watch(serverStudyLessonsProvider).value ?? const <String, Set<int>>{};
  final badges = ref.watch(profileBadgesProvider);

  final entries = <ProfileActivity>[];

  for (final highlight in highlights) {
    entries.add(
      ProfileActivity(
        id: 'highlight-${highlight.id}',
        kind: ProfileActivityKind.highlight,
        actionLabel: 'markeerde een vers',
        at: highlight.updatedAt,
        note: highlight,
      ),
    );
  }

  for (final note in notes) {
    entries.add(
      ProfileActivity(
        id: 'note-${note.id}',
        kind: ProfileActivityKind.note,
        actionLabel: 'schreef een notitie',
        at: note.updatedAt,
        note: note,
      ),
    );
  }

  // A study is "touched" if there is a device plan for it or the account has
  // completed a lesson in it. Both copies are partial, exactly as
  // [mergedCompletedDays] documents, so both are consulted.
  final touched = {...plans.keys, ...serverLessons.keys};
  for (final study in studies) {
    if (!touched.contains(study.id)) continue;
    final done = mergedCompletedDays(
      studyId: study.id,
      plans: plans,
      serverLessons: serverLessons,
    ).length;
    final total = study.lessonCount;
    entries.add(
      ProfileActivity(
        id: 'study-${study.id}',
        kind: ProfileActivityKind.study,
        actionLabel: total > 0 && done >= total
            ? 'rondde een bijbelstudie af'
            : 'volgt een bijbelstudie',
        // Only the device plan records a date; a study known solely from the
        // account's completed lessons has none.
        at: plans[study.id]?.startedAt,
        study: study,
        lessonsDone: done,
        lessonsTotal: total,
      ),
    );
  }

  for (final badge in badges) {
    if (!badge.unlocked) continue;
    entries.add(
      ProfileActivity(
        id: 'badge-${badge.definition.id}',
        kind: ProfileActivityKind.badge,
        actionLabel: 'behaalde een badge',
        badge: badge,
      ),
    );
  }

  entries.sort((a, b) {
    final left = a.at;
    final right = b.at;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });

  return entries.length <= _kFeedLimit
      ? entries
      : entries.sublist(0, _kFeedLimit);
});
