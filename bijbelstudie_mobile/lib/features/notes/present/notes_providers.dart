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

/// Identifies a chapter for [chapterNoteMarkersProvider]. Value equality
/// matters: it is a family key.
class ChapterKey {
  const ChapterKey(this.book, this.chapter);

  final String book;
  final int chapter;

  @override
  bool operator ==(Object other) =>
      other is ChapterKey && other.book == book && other.chapter == chapter;

  @override
  int get hashCode => Object.hash(book, chapter);
}

/// Verse numbers with a note in one chapter, so the reader can mark them
/// without a lookup through the whole notes list on every row build.
///
/// Derived from [notesListProvider] - the same `/notes` list the Notities tab
/// uses - rather than a dedicated endpoint. Highlights are a different kind
/// server-side ([highlightsListProvider]), so a highlight-only verse never
/// shows up here. Because this only watches [notesListProvider], it picks up
/// a save or delete automatically wherever that provider is already
/// invalidated (`verse_action_sheet.dart`, `notes_screen.dart`) - nothing
/// extra to invalidate for the reader to stay in sync.
final chapterNoteMarkersProvider =
    Provider.autoDispose.family<Set<int>, ChapterKey>((ref, key) {
  final notes = ref.watch(notesListProvider).value ?? const <StudyNote>[];
  return {
    for (final n in notes)
      if (n.book == key.book && n.chapter == key.chapter && n.verse != null) n.verse!,
  };
});

/// Most recent reading position, for "verder lezen" on the home tab.
final continueReadingProvider = Provider.autoDispose<ReadingPosition?>((ref) {
  final history = ref.watch(readingHistoryProvider).value;
  if (history == null || history.isEmpty) return null;
  final sorted = [...history]..sort((a, b) => b.readAt.compareTo(a.readAt));
  return sorted.first;
});
