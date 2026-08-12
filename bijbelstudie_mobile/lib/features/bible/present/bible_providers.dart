import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../commentary/data/commentary_repository.dart';
import '../../settings/data/reading_settings.dart';
import '../data/bible_repository.dart';
import '../domain/bible_models.dart';

/// Same Riverpod vocabulary as the reference app: a `Repository` that takes the
/// `ApiClient`, exposed through `FutureProvider.autoDispose.family`.

final bibleVersionsProvider = FutureProvider.autoDispose<List<BibleSource>>((ref) {
  return ref.watch(bibleRepositoryProvider).getVersions();
});

final commentarySourcesProvider = FutureProvider.autoDispose<List<BibleSource>>((ref) {
  return ref.watch(commentaryRepositoryProvider).getCommentaries();
});

final bibleBooksProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, versionId) {
      return ref.watch(bibleRepositoryProvider).getBooks(versionId);
    });

/// (versionId, book) — records carrying two values need a value type with
/// proper equality or the family caches per instance and refetches forever.
class BookRef {
  const BookRef(this.sourceId, this.book);

  final String sourceId;
  final String book;

  @override
  bool operator ==(Object other) =>
      other is BookRef && other.sourceId == sourceId && other.book == book;

  @override
  int get hashCode => Object.hash(sourceId, book);
}

class ChapterRef {
  const ChapterRef(this.sourceId, this.book, this.chapter);

  final String sourceId;
  final String book;
  final int chapter;

  @override
  bool operator ==(Object other) =>
      other is ChapterRef &&
      other.sourceId == sourceId &&
      other.book == book &&
      other.chapter == chapter;

  @override
  int get hashCode => Object.hash(sourceId, book, chapter);
}

final bibleChaptersProvider =
    FutureProvider.autoDispose.family<List<int>, BookRef>((ref, bookRef) {
      return ref.watch(bibleRepositoryProvider).getChapters(bookRef.sourceId, bookRef.book);
    });

final chapterContentProvider =
    FutureProvider.autoDispose.family<ChapterContent, ChapterRef>((ref, chapterRef) {
      return ref
          .watch(bibleRepositoryProvider)
          .getChapter(chapterRef.sourceId, chapterRef.book, chapterRef.chapter);
    });

final commentaryChapterProvider =
    FutureProvider.autoDispose.family<ChapterContent, ChapterRef>((ref, chapterRef) {
      return ref
          .watch(commentaryRepositoryProvider)
          .getChapter(chapterRef.sourceId, chapterRef.book, chapterRef.chapter);
    });

final originalChapterProvider =
    FutureProvider.autoDispose.family<OriginalChapter, ChapterRef>((ref, chapterRef) {
      return ref
          .watch(bibleRepositoryProvider)
          .getOriginal(chapterRef.book, chapterRef.chapter);
    });

/// What the reader is currently showing. Persisted through
/// [ReadingSettingsController] so the app reopens where it was left.
class ReaderLocation {
  const ReaderLocation({
    required this.versionId,
    required this.book,
    required this.chapter,
  });

  final String versionId;
  final String book;
  final int chapter;

  ChapterRef get ref => ChapterRef(versionId, book, chapter);

  ReaderLocation copyWith({String? versionId, String? book, int? chapter}) {
    return ReaderLocation(
      versionId: versionId ?? this.versionId,
      book: book ?? this.book,
      chapter: chapter ?? this.chapter,
    );
  }
}

final readerLocationProvider =
    NotifierProvider<ReaderLocationController, ReaderLocation>(
      ReaderLocationController.new,
    );

class ReaderLocationController extends Notifier<ReaderLocation> {
  @override
  ReaderLocation build() {
    final settings = ref.watch(readingSettingsProvider);
    return ReaderLocation(
      versionId: settings.lastVersionId,
      book: 'Genesis',
      chapter: 1,
    );
  }

  void openChapter({String? versionId, String? book, int? chapter}) {
    state = state.copyWith(versionId: versionId, book: book, chapter: chapter);
    if (versionId != null) {
      ref.read(readingSettingsProvider.notifier).setLastVersion(versionId);
    }
  }

  void nextChapter(List<int> chapters) {
    final index = chapters.indexOf(state.chapter);
    if (index >= 0 && index + 1 < chapters.length) {
      state = state.copyWith(chapter: chapters[index + 1]);
    }
  }

  void previousChapter(List<int> chapters) {
    final index = chapters.indexOf(state.chapter);
    if (index > 0) {
      state = state.copyWith(chapter: chapters[index - 1]);
    }
  }
}
