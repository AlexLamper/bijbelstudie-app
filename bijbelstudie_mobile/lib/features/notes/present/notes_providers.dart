import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/provider_cache.dart';

import '../data/notes_repository.dart';
import '../domain/note_models.dart';

final notesListProvider = FutureProvider.autoDispose<List<StudyNote>>((ref) {
  ref.cacheFor();
  return ref.watch(notesRepositoryProvider).listNotes();
});

final highlightsListProvider = FutureProvider.autoDispose<List<StudyNote>>((ref) {
  ref.cacheFor();
  return ref.watch(notesRepositoryProvider).listHighlights();
});

final bookmarksProvider = FutureProvider.autoDispose<List<Bookmark>>((ref) {
  ref.cacheFor();
  return ref.watch(notesRepositoryProvider).listBookmarks();
});

final readingHistoryProvider = FutureProvider.autoDispose<List<ReadingPosition>>((ref) {
  ref.cacheFor();
  return ref.watch(notesRepositoryProvider).listReadingHistory();
});

/// Identifies a verse across the app. Value equality matters: it is a map key.
class VerseKey {
  const VerseKey(this.book, this.chapter, this.verse);

  final String book;
  final int chapter;
  final int verse;

  @override
  bool operator ==(Object other) =>
      other is VerseKey &&
      other.book == book &&
      other.chapter == chapter &&
      other.verse == verse;

  @override
  int get hashCode => Object.hash(book, chapter, verse);
}

/// Highlight colour per verse, so the reader can paint a verse without a
/// lookup through the whole list on every row build.
final highlightIndexProvider = Provider.autoDispose<Map<VerseKey, HighlightColor>>((ref) {
  final highlights = ref.watch(highlightsListProvider).value ?? const <StudyNote>[];
  return {
    for (final h in highlights)
      if (h.verse != null) VerseKey(h.book, h.chapter, h.verse!): h.color,
  };
});

/// Most recent reading position, for "verder lezen" on the home tab.
final continueReadingProvider = Provider.autoDispose<ReadingPosition?>((ref) {
  final history = ref.watch(readingHistoryProvider).value;
  if (history == null || history.isEmpty) return null;
  final sorted = [...history]..sort((a, b) => b.readAt.compareTo(a.readAt));
  return sorted.first;
});
