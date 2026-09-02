import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/present/dashboard_providers.dart';
import '../../notes/present/notes_providers.dart';
import '../domain/profile_stats.dart';

/// The profile's headline numbers.
///
/// Gates on `/dashboard`, which is the only source for the streak, the freezes
/// and the awarded badge ids. The notes and highlight lists are read
/// opportunistically: they are separate requests, and a slow one must not hold
/// up the streak card.
final profileStatsProvider = Provider.autoDispose<AsyncValue<ProfileStats>>((
  ref,
) {
  final dashboard = ref.watch(dashboardProvider);
  final notes = ref.watch(notesListProvider).value;
  final highlights = ref.watch(highlightsListProvider).value;

  return dashboard.whenData((data) {
    final chapters = data.readChapters.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    return ProfileStats(
      streak: data.streak,
      freezes: data.freezes,
      booksRead: data.booksStarted,
      chaptersRead: chapters,
      // The Start tab no longer carries a notes section, so the count is taken
      // from the notes list itself and only falls back to the dashboard's own
      // figure while that request is still in flight.
      notesCount: notes?.length ?? data.notesCount,
      // No dashboard field mirrors this one, so an unloaded list reads as zero
      // rather than as a guess.
      highlightsCount: highlights?.length ?? 0,
      serverBadgeIds: data.badges,
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
