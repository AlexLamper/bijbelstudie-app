import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/db/content_cache.dart';
import '../../commentary/data/commentary_repository.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/data/dashboard_repository.dart';
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

/// (versionId, book) - records carrying two values need a value type with
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

/// Books with chapters stored on this device, newest first.
///
/// Not autoDispose: the offline sheet and the settings screen both read it and
/// invalidating it after a download or a delete is what refreshes them.
final offlineBooksProvider = FutureProvider<List<OfflineBook>>((ref) {
  return ref.watch(bibleRepositoryProvider).offlineBooks();
});

/// What is genuinely readable offline for one book.
///
/// [stored] is counted in the cache, never carried over from the download that
/// put it there, so a book that lost chapters to a failed request or to
/// eviction reports the smaller number. [total] is only set when the chapter
/// list is actually known - offline with nothing cached there is no honest
/// denominator, and the UI is expected to leave it out rather than guess.
class BookOfflineStatus {
  const BookOfflineStatus({required this.stored, this.total});

  final List<int> stored;
  final int? total;

  bool get isEmpty => stored.isEmpty;
  bool get isComplete => total != null && stored.length >= total!;
  bool get isPartial => stored.isNotEmpty && !isComplete;
}

final bookOfflineStatusProvider =
    FutureProvider.autoDispose.family<BookOfflineStatus, BookRef>((ref, bookRef) async {
      final stored = await ref
          .watch(bibleRepositoryProvider)
          .offlineChapters(bookRef.sourceId, bookRef.book);
      // The server's chapter list when it is already loaded; otherwise none,
      // because a count borrowed from the canon table can disagree with what a
      // given translation actually publishes.
      final total = ref.watch(bibleChaptersProvider(bookRef)).value?.length;
      return BookOfflineStatus(stored: stored, total: total);
    });

/// What the reader is currently showing. Persisted through
/// [ReadingSettingsController] so the app reopens where it was left.
class ReaderLocation {
  const ReaderLocation({
    required this.versionId,
    required this.book,
    required this.chapter,
    this.restored = false,
  });

  final String versionId;
  final String book;
  final int chapter;

  /// False while [ReaderLocationController] is still working out where the user
  /// was. The chapter carried alongside it is a placeholder, so the reader
  /// waits instead of painting it: showing Genesis 1 and then yanking someone
  /// to Johannes 3 is the reset this provider exists to prevent.
  final bool restored;

  ChapterRef get ref => ChapterRef(versionId, book, chapter);

  ReaderLocation copyWith({
    String? versionId,
    String? book,
    int? chapter,
    bool? restored,
  }) {
    return ReaderLocation(
      versionId: versionId ?? this.versionId,
      book: book ?? this.book,
      chapter: chapter ?? this.chapter,
      restored: restored ?? this.restored,
    );
  }
}

/// The server's copy of where the reader was, or null when it cannot be had.
///
/// Its own provider, and deliberately not autoDispose: the answer is wanted
/// once per app run, and preview mode and the tests override it rather than let
/// it reach for the network.
final remoteReaderLocationProvider = FutureProvider<LastRead?>((ref) async {
  // Preview runs on canned data with no account behind it.
  if (PreviewConfig.enabled) return null;
  return ref.watch(dashboardRepositoryProvider).getLastRead();
});

final readerLocationProvider =
    NotifierProvider<ReaderLocationController, ReaderLocation>(
      ReaderLocationController.new,
    );

class ReaderLocationController extends Notifier<ReaderLocation> {
  /// How long either half of the answer gets before the reader gives up on it.
  /// Long enough for a warm request, short enough that a dead network - or a
  /// preferences read that never comes back - cannot leave the reader on a
  /// spinner for good.
  static const _budget = Duration(seconds: 3);

  /// Set the moment the reader is somewhere the user chose, so a hydration that
  /// lands late can never pull them off the chapter they just tapped.
  bool _pinned = false;

  @override
  ReaderLocation build() {
    _pinned = false;
    unawaited(_hydrate());

    // Genesis 1, but `restored: false`: a placeholder to satisfy the type, not
    // an answer. It is only ever painted once [_hydrate] has confirmed that
    // this reader has genuinely never opened a chapter.
    return const ReaderLocation(
      versionId: 'statenvertaling',
      book: 'Genesis',
      chapter: 1,
    );
  }

  /// Works out where the reader should open, once per app run.
  ///
  /// Two copies of the answer exist and either can be the only one there is: a
  /// second device that was just installed has only the server's, and a session
  /// spent offline has only this device's. So both are read and the more
  /// recently written one wins, which is the rule `hooks/useBibleData.ts` uses
  /// on the website. A tie goes to this device: that copy was written by the
  /// reader the user actually had open last.
  Future<void> _hydrate() async {
    final settings = ref.read(readingSettingsProvider.notifier);

    // Started before the disk read is awaited so the two run together; the
    // request must not add its latency on top of the preferences load.
    final remoteFuture = _readRemote();
    try {
      await settings.loaded.timeout(_budget);
    } catch (_) {
      // No preferences to be had; the server copy or Genesis 1 answers instead.
    }
    final remote = await remoteFuture;

    // The user got somewhere first, or the scope is gone. Either way there is
    // nothing left to restore.
    if (!ref.mounted || _pinned) return;

    final local = ref.read(readingSettingsProvider);
    final localBook = local.lastBook;
    final localChapter = local.lastChapter;
    final hasLocal = localBook != null && localChapter != null;

    if (remote != null &&
        (!hasLocal || _isNewer(remote.updatedAt, local.lastLocationAt))) {
      state = ReaderLocation(
        versionId: remote.version,
        book: remote.book,
        chapter: remote.chapter,
        restored: true,
      );
      // Bring this device in step so the next launch reaches the same answer
      // without having to wait on the network at all.
      unawaited(settings.setLastVersion(remote.version));
      unawaited(settings.setLastLocation(book: remote.book, chapter: remote.chapter));
      return;
    }

    state = ReaderLocation(
      versionId: local.lastVersionId,
      book: localBook ?? 'Genesis',
      chapter: localChapter ?? 1,
      restored: true,
    );
  }

  Future<LastRead?> _readRemote() async {
    try {
      return await ref
          .read(remoteReaderLocationProvider.future)
          .timeout(_budget);
    } catch (_) {
      // Offline, signed out, or simply slow. The device copy answers instead.
      return null;
    }
  }

  /// Undated on the server side means the comparison cannot be made, and the
  /// copy on this device keeps the benefit of the doubt.
  static bool _isNewer(DateTime? remote, DateTime? local) {
    if (remote == null) return false;
    if (local == null) return true;
    return remote.isAfter(local);
  }

  void openChapter({String? versionId, String? book, int? chapter}) {
    if (versionId != null) {
      unawaited(ref.read(readingSettingsProvider.notifier).setLastVersion(versionId));
    }
    _goTo(
      state.copyWith(
        versionId: versionId,
        book: book,
        chapter: chapter,
        restored: true,
      ),
    );
  }

  void nextChapter(List<int> chapters) {
    final index = chapters.indexOf(state.chapter);
    if (index >= 0 && index + 1 < chapters.length) {
      _goTo(state.copyWith(chapter: chapters[index + 1]));
    }
  }

  void previousChapter(List<int> chapters) {
    final index = chapters.indexOf(state.chapter);
    if (index > 0) {
      _goTo(state.copyWith(chapter: chapters[index - 1]));
    }
  }

  /// Moves the reader and writes the position down in the same breath.
  ///
  /// The write happens here rather than after the chapter renders, because
  /// paging to a chapter that then fails to load is still where the reader is
  /// and a cold start has to come back to it. The server side of the same
  /// record stays in the read screen: that call also feeds the dashboard, so it
  /// remains tied to a chapter that actually opened.
  void _goTo(ReaderLocation next) {
    _pinned = true;
    state = next;

    // Preview runs on canned data; it must never write onto a real account.
    if (PreviewConfig.enabled) return;
    unawaited(
      ref
          .read(readingSettingsProvider.notifier)
          .setLastLocation(book: next.book, chapter: next.chapter),
    );
  }
}
