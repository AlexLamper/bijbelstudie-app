import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/present/dashboard_providers.dart';
import '../../levensboom/present/levensboom_providers.dart';
import '../../notes/present/notes_providers.dart';
import '../domain/profile_stats.dart';

/// The profile's headline numbers.
///
/// Gates on `/dashboard`, which is the only source for the reading history.
/// The streak, the freezes and the awarded badge ids come from
/// `/gamification` instead — it is the endpoint that owns the XP system, it
/// returns the badge ids the server actually granted, and it is what the
/// Levensboom already reads, so the two cannot disagree about the same account.
/// While that request is in flight the dashboard's own figures stand in, so the
/// card never renders empty.
///
/// The notes and highlight lists are read opportunistically: they are separate
/// requests, and a slow one must not hold up the streak card.
final profileStatsProvider = Provider.autoDispose<AsyncValue<ProfileStats>>((
  ref,
) {
  final dashboard = ref.watch(dashboardProvider);
  final tree = ref.watch(treeStateProvider).value;
  final notes = ref.watch(notesListProvider).value;
  final highlights = ref.watch(highlightsListProvider).value;

  return dashboard.whenData((data) {
    final chapters = data.readChapters.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    return ProfileStats(
      streak: tree?.streak ?? data.streak,
      freezes: tree?.freezes ?? data.freezes,
      booksRead: data.booksStarted,
      chaptersRead: chapters,
      // The Start tab no longer carries a notes section, so the count is taken
      // from the notes list itself and only falls back to the dashboard's own
      // figure while that request is still in flight.
      notesCount: notes?.length ?? data.notesCount,
      // No dashboard field mirrors this one, so an unloaded list reads as zero
      // rather than as a guess.
      highlightsCount: highlights?.length ?? 0,
      serverBadgeIds: tree?.badges ?? data.badges,
    );
  });
});

/// Every badge with the reader's real standing against it. Empty until the
/// stats land - the catalog has nothing to measure before then.
final profileBadgesProvider = Provider.autoDispose<List<BadgeProgress>>((ref) {
  final stats = ref.watch(profileStatsProvider).value;
  if (stats == null) return const <BadgeProgress>[];
  return BadgeCatalog.resolve(stats);
});
