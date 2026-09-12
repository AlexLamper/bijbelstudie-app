import 'package:flutter/material.dart';
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
import 'package:bijbelstudie_mobile/features/dashboard/data/daily_verse_store.dart';
import 'package:bijbelstudie_mobile/features/notes/domain/note_models.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_providers.dart';

/// [pendingVerseAnchorProvider] is set from two very different places, and the
/// reader has to answer both.
///
/// The old callers - the daily verse card and search - set it and then
/// *navigated*, so a fresh [ReadScreen] read it once on its first build. The
/// chapter-marks sheet sets it while the reader is already mounted on that
/// exact chapter, where nothing navigates and nothing rebuilds, so the reader
/// now watches the provider instead of reading it.
///
/// That is the part worth a test. Watching a provider the same widget also
/// resets to null *during its own build* is the kind of thing that works until
/// Riverpod decides it is a cycle, and no other test exercises the path at all.
/// These assert both that the anchor is consumed exactly once and that doing so
/// throws nothing and settles.
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

  @override
  Future<List<DailyVerseEntry>> getDayTextHistory({int limit = 60}) async =>
      const [];
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const chapter = ChapterContent(
    sourceId: 'statenvertaling',
    book: 'Genesis',
    chapter: 1,
    attribution: 'Statenvertaling (1637) - publiek domein',
    verses: [
      Verse(number: 1, text: 'In den beginne schiep God den hemel en de aarde.'),
      Verse(number: 2, text: 'De aarde nu was woest en ledig.'),
      Verse(number: 3, text: 'En God zeide: Daar zij licht! en daar werd licht.'),
    ],
  );

  Future<ProviderContainer> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        contentCacheProvider.overrideWithValue(null),
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
        notesListProvider.overrideWith((ref) async => const <StudyNote>[]),
        highlightsListProvider.overrideWith((ref) async => const <StudyNote>[]),
        bookmarksProvider.overrideWith((ref) async => const <Bookmark>[]),
        readingHistoryProvider.overrideWith((ref) async => const <ReadingPosition>[]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.lightTheme, home: const ReadScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('an anchor set while the reader is already mounted is consumed', (
    tester,
  ) async {
    final container = await pumpReader(tester);

    // Nothing pending on a plain open, or the reader would fight the remembered
    // scroll position on every chapter.
    expect(container.read(pendingVerseAnchorProvider), isNull);

    // What the chapter-marks sheet does: set the anchor on a reader that is
    // already sitting on this chapter. No navigation, no new ReadScreen.
    container.read(pendingVerseAnchorProvider.notifier).set(3);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Consumed, not left behind: a stale anchor would re-fire on the next
    // chapter change.
    expect(container.read(pendingVerseAnchorProvider), isNull);
  });

  testWidgets('an anchor naming a verse this chapter does not have is left alone', (
    tester,
  ) async {
    final container = await pumpReader(tester);

    // The daily verse card can name a verse in a chapter that has not loaded
    // yet. The reader must not swallow it against the wrong chapter.
    container.read(pendingVerseAnchorProvider.notifier).set(99);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(pendingVerseAnchorProvider), 99);
  });

  testWidgets('setting the anchor repeatedly does not loop or throw', (
    tester,
  ) async {
    final container = await pumpReader(tester);

    for (final verse in [1, 2, 3, 1]) {
      container.read(pendingVerseAnchorProvider.notifier).set(verse);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(container.read(pendingVerseAnchorProvider), isNull);
    }
  });
}
