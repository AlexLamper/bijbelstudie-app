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

/// The tab [NotesScreen] should open on, set just before navigating there -
/// the reader's "Bladwijzers" entry sets [NotesTab.bookmarks]. Consumed (reset
/// to null) by the screen, so the Notities tab in the bar still opens on notes.
enum NotesTab { notes, highlights, bookmarks }

class PendingNotesTab extends Notifier<NotesTab?> {
  @override
  NotesTab? build() => null;

  void set(NotesTab? tab) => state = tab;
}

final pendingNotesTabProvider = NotifierProvider<PendingNotesTab, NotesTab?>(
  PendingNotesTab.new,
);

/// The one-shot bus for a write the server refused outside anyone's `await`.
///
/// A queued offline write is replayed by [NotesRepository.unawaitedFlush],
/// which is fire-and-forget by design: there is no `try`/`catch` around it and
/// no screen context to raise a SnackBar from. The repository pushes the
/// refusal here instead, and whichever screen is up shows it through
/// `listenForSyncRejections` (see `sync_rejection_notice.dart`).
///
/// Nothing is persisted. A refusal missed because no screen was listening is
/// not worth waking the app for; the row is gone from the queue either way, so
/// it cannot come back and vanish a second time.
class SyncRejectionBus extends Notifier<SyncRejectedException?> {
  @override
  SyncRejectedException? build() => null;

  void push(SyncRejectedException rejection) => state = rejection;

  /// Consumed by whichever screen showed it, so it is shown exactly once.
  void clear() => state = null;
}

final syncRejectionProvider =
    NotifierProvider<SyncRejectionBus, SyncRejectedException?>(SyncRejectionBus.new);

final readingHistoryProvider =FutureProvider.autoDispose<List<ReadingPosition>>((ref) {
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

/// How many notes and highlights the open chapter carries, for the status line
/// in the reader header.
class ChapterMarkCounts {
  const ChapterMarkCounts({required this.notes, required this.highlights});

  final int notes;
  final int highlights;

  bool get isEmpty => notes == 0 && highlights == 0;
}

/// Counts for one chapter, derived from the two lists the Notities tab already
/// loads. No endpoint and no new model: the reader header is a second view of
/// rows that are on the device anyway, and it stays in sync for free wherever
/// those providers are invalidated after a save or delete.
final chapterMarkCountsProvider =
    Provider.autoDispose.family<ChapterMarkCounts, ChapterKey>((ref, key) {
  bool here(StudyNote n) => n.book == key.book && n.chapter == key.chapter;

  final notes = ref.watch(notesListProvider).value ?? const <StudyNote>[];
  final highlights = ref.watch(highlightsListProvider).value ?? const <StudyNote>[];

  return ChapterMarkCounts(
    notes: notes.where(here).length,
    highlights: highlights.where(here).length,
  );
});
