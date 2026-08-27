import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/core/db/content_cache.dart';
import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';
import 'package:bijbelstudie_mobile/features/bible/domain/bible_models.dart';
import 'package:bijbelstudie_mobile/features/bible/present/bible_providers.dart';
import 'package:bijbelstudie_mobile/features/bible/present/read_screen.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:bijbelstudie_mobile/features/notes/data/notes_repository.dart';
import 'package:bijbelstudie_mobile/features/notes/domain/note_models.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_providers.dart';

/// Notes made from the reader never reached the server, while highlights and
/// bookmarks made from the same sheet always did.
///
/// The cause was lifetime, not transport: the sheet popped itself and then
/// opened the note dialog with its own `context` and `ref`. By the time the
/// reader tapped "Opslaan" - seconds later, after the sheet had finished
/// animating out and been unmounted - `ref.read` threw `StateError: Using
/// "ref" when a widget is about to or has been unmounted is unsafe`. Only
/// `SyncRejectedException` was caught, so the note disappeared with no error,
/// no request and nothing in the Notities tab. Highlights and bookmarks were
/// saved *before* the pop, which is why they were never affected.
///
/// These tests drive the real widgets end to end and assert the repository was
/// actually reached.
class _RecordingNotesRepository implements NotesRepository {
  final List<StudyNote> savedNotes = [];
  final List<Bookmark> savedBookmarks = [];

  @override
  Future<StudyNote> saveNote(StudyNote note) async {
    savedNotes.add(note);
    return note;
  }

  @override
  Future<Bookmark> saveBookmark(Bookmark bookmark) async {
    savedBookmarks.add(bookmark);
    return bookmark;
  }

  @override
  Future<List<StudyNote>> listNotes() async => savedNotes;

  @override
  Future<List<StudyNote>> listHighlights() async =>
      savedNotes.where((n) => n.isHighlight).toList();

  @override
  Future<List<Bookmark>> listBookmarks() async => savedBookmarks;

  @override
  Future<List<ReadingPosition>> listReadingHistory() async => const [];

  @override
  Future<void> deleteNote(StudyNote note) async => savedNotes.remove(note);

  @override
  Future<void> deleteBookmark(String id) async {}

  @override
  Future<void> recordReadingPosition({
    required String version,
    required String book,
    required int chapter,
    required double scrollProgress,
  }) async {}

  @override
  Future<int> flushPendingChanges() async => 0;

  @override
  void unawaitedFlush() {}
}

class _StubDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardData> getDashboard() async => throw UnimplementedError();

  @override
  Future<void> recordRead({
    required String book,
    required int chapter,
    required String version,
    String? commentary,
  }) async {}

  @override
  Future<LastRead?> getLastRead() async => null;

  @override
  Future<StreakResult?> bumpStreak() async => null;

  @override
  Future<DailyVerse?> getDailyVerse() async => null;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Every save path in the verse sheet fires a haptic first, and under the
    // test binding `SystemChannels.platform` has no handler, so that Future
    // never completes and the code after the await simply never runs - the
    // sheet would never even open. Answering the channel is what lets these
    // flows be driven end to end.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  const chapter = ChapterContent(
    sourceId: 'statenvertaling',
    book: 'Genesis',
    chapter: 1,
    attribution: 'Statenvertaling (1637) - publiek domein',
    verses: [
      Verse(number: 1, text: 'In den beginne schiep God den hemel en de aarde.'),
      Verse(number: 2, text: 'De aarde nu was woest en ledig.'),
    ],
  );

  late _RecordingNotesRepository repository;

  Future<void> pumpReader(WidgetTester tester) async {
    repository = _RecordingNotesRepository();

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentCacheProvider.overrideWithValue(null),
          notesRepositoryProvider.overrideWithValue(repository),
          dashboardRepositoryProvider.overrideWithValue(_StubDashboardRepository()),
          remoteReaderLocationProvider.overrideWith((ref) async => null),
          bibleVersionsProvider.overrideWith(
            (ref) async => const [
              BibleSource(
                id: 'statenvertaling',
                name: 'Statenvertaling',
                language: 'nl',
                attribution: '',
              ),
            ],
          ),
          bibleBooksProvider.overrideWith((ref, versionId) async => const ['Genesis']),
          bibleChaptersProvider.overrideWith((ref, bookRef) async => const [1, 2]),
          chapterContentProvider.overrideWith((ref, chapterRef) async => chapter),
          notesListProvider.overrideWith((ref) async => repository.savedNotes),
          highlightsListProvider.overrideWith((ref) async => const <StudyNote>[]),
          bookmarksProvider.overrideWith((ref) async => const <Bookmark>[]),
          readingHistoryProvider.overrideWith((ref) async => const <ReadingPosition>[]),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const ReadScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openVerseSheet(WidgetTester tester) async {
    await tester.longPress(find.textContaining('In den beginne'));
    await tester.pumpAndSettle();
  }

  testWidgets('a note written from the verse sheet reaches the repository', (tester) async {
    await pumpReader(tester);
    await openVerseSheet(tester);

    await tester.tap(find.text('Notitie toevoegen'));
    // Settles the sheet all the way out, which is precisely the moment the old
    // code lost its `ref`. The dialog has to survive it.
    await tester.pumpAndSettle();

    expect(find.text('Genesis 1:1'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Alles begint bij God als Schepper.');
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();

    expect(repository.savedNotes, hasLength(1));
    final note = repository.savedNotes.single;
    expect(note.noteText, 'Alles begint bij God als Schepper.');
    expect(note.book, 'Genesis');
    expect(note.chapter, 1);
    expect(note.verse, 1);
    expect(note.isHighlight, isFalse);
    expect(note.translation, 'statenvertaling');
    // The client id travels with the record, so a retried upload is an upsert.
    expect(note.id, isNotEmpty);
  });

  testWidgets('cancelling the dialog saves nothing', (tester) async {
    await pumpReader(tester);
    await openVerseSheet(tester);

    await tester.tap(find.text('Notitie toevoegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bedacht me');
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(repository.savedNotes, isEmpty);
  });

  testWidgets('an empty note is not saved', (tester) async {
    await pumpReader(tester);
    await openVerseSheet(tester);

    await tester.tap(find.text('Notitie toevoegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();

    expect(repository.savedNotes, isEmpty);
  });

  testWidgets('highlights and bookmarks still save from the same sheet', (tester) async {
    await pumpReader(tester);

    await openVerseSheet(tester);
    await tester.tap(find.bySemanticsLabel('Markeer Groen'));
    await tester.pumpAndSettle();
    expect(repository.savedNotes.where((n) => n.isHighlight), hasLength(1));

    await openVerseSheet(tester);
    await tester.tap(find.text('Bladwijzer plaatsen'));
    await tester.pumpAndSettle();
    expect(repository.savedBookmarks, hasLength(1));
  });
}
