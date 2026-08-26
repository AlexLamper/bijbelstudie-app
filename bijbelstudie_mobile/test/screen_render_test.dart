import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/core/db/content_cache.dart';
import 'package:bijbelstudie_mobile/core/preview/preview_data.dart';
import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';
import 'package:bijbelstudie_mobile/features/bible/domain/bible_models.dart';
import 'package:bijbelstudie_mobile/features/bible/present/bible_providers.dart';
import 'package:bijbelstudie_mobile/features/bible/present/read_screen.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_providers.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_screen.dart';
import 'package:bijbelstudie_mobile/features/studies/present/studies_providers.dart';
import 'package:bijbelstudie_mobile/features/studies/present/studies_screen.dart';
import 'package:bijbelstudie_mobile/features/commentary/present/commentary_screen.dart';
import 'package:bijbelstudie_mobile/features/notes/domain/note_models.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_providers.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_screen.dart';
import 'package:bijbelstudie_mobile/features/onboarding/present/onboarding_screen.dart';
import 'package:bijbelstudie_mobile/features/profile/data/profile_model.dart';
import 'package:bijbelstudie_mobile/features/profile/present/profile_provider.dart';
import 'package:bijbelstudie_mobile/features/profile/present/profile_screen.dart';
import 'package:bijbelstudie_mobile/features/settings/present/settings_screen.dart';

/// Keeps these renders off the network.
///
/// The reader posts the open chapter to `/last-read` from a post-frame
/// callback; against the real repository that leaves a Dio timer pending after
/// the tree is torn down, which the test binding reports as a failure.
class _StubDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardData> getDashboard() async => PreviewData.dashboard;

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
  Future<DailyVerse?> getDailyVerse() async => PreviewData.dashboard.dailyVerse;
}

/// Fails with the full error text (including the offending widget chain)
/// instead of the one-line summary `expect` would print.
void expectNoLayoutError(WidgetTester tester) {
  final error = tester.takeException();
  if (error == null) return;

  // Walk the element tree to name the widget whose Flex overflowed — the bare
  // FlutterError only carries the pixel count.
  final culprits = <String>[];
  for (final element in tester.allElements) {
    final render = element.renderObject;
    if (render is! RenderFlex) continue;
    if (!render.toStringShort().contains('OVERFLOWING')) continue;
    culprits.add(element.debugGetCreatorChain(10));
  }

  fail(
    'Layout error:\n$error\n\nOverflowing widget(s):\n${culprits.join('\n\n')}',
  );
}

/// Registers the real Inter / Newsreader files with the test engine.
///
/// Without this the test engine substitutes a placeholder font whose glyphs are
/// all one em wide, which makes every string roughly twice its real width and
/// produces overflow errors that never happen on a device.
Future<void> loadAppFonts() async {
  for (final entry in const {
    'Inter': [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/Inter-Bold.ttf',
    ],
    'Newsreader': [
      'assets/fonts/Newsreader-Regular.ttf',
      'assets/fonts/Newsreader-Medium.ttf',
      'assets/fonts/Newsreader-SemiBold.ttf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await loader.load();
  }
}

/// Renders the main screens at iPhone size with fake data so layout overflows
/// and render exceptions surface in CI instead of on a device.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ReadScreen and CommentaryScreen read the reader preferences on mount;
    // without a mock the plugin channel throws MissingPluginException.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadAppFonts();
  });

  const versions = [
    BibleSource(
      id: 'statenvertaling',
      name: 'Statenvertaling',
      language: 'nl',
      attribution: 'Statenvertaling (1637) — publiek domein',
    ),
    BibleSource(
      id: 'kjv',
      name: 'King James Version',
      language: 'en',
      attribution: 'King James Version (1611) — publiek domein',
    ),
  ];

  const commentaries = [
    BibleSource(
      id: 'matthew_henry_nl',
      name: 'Matthew Henry (NL)',
      language: 'nl',
      attribution: 'Matthew Henry (1662–1714) — publiek domein',
    ),
  ];

  const chapter = ChapterContent(
    sourceId: 'statenvertaling',
    book: 'Genesis',
    chapter: 1,
    attribution: 'Statenvertaling (1637) — publiek domein',
    verses: [
      Verse(
        number: 1,
        text: 'In den beginne schiep God den hemel en de aarde.',
      ),
      Verse(
        number: 2,
        text:
            'De aarde nu was woest en ledig, en duisternis was op den afgrond; '
            'en de Geest Gods zweefde op de wateren.',
      ),
      Verse(
        number: 3,
        text: 'En God zeide: Daar zij licht! en daar werd licht.',
      ),
    ],
  );

  const commentaryChapter = ChapterContent(
    sourceId: 'matthew_henry_nl',
    book: 'Genesis',
    chapter: 1,
    attribution: 'Matthew Henry (1662–1714) — publiek domein',
    verses: [
      // Verse 0 is how the corpus keys a chapter introduction — the renderer
      // has to label it "Inleiding", not "Vers 0".
      Verse(
        number: 0,
        text: 'De grondslag van alle Godsdienst ligt in God als Schepper.',
      ),
      Verse(
        number: 1,
        text: 'De eerste woorden stellen God voor als de Schepper.',
      ),
    ],
  );

  final profile = ProfileModel(
    id: 'u1',
    name: 'Alex Lamper',
    email: 'alex@example.com',
    isPro: true,
    proSource: 'apple',
    proExpiresAt: DateTime(2027, 3, 1),
  );

  final notes = [
    StudyNote(
      id: 'n1',
      book: 'Genesis',
      chapter: 1,
      verse: 1,
      verseText: 'In den beginne schiep God den hemel en de aarde.',
      noteText: 'Alles begint bij God als Schepper.',
      translation: 'statenvertaling',
      isHighlight: false,
      updatedAt: DateTime(2026, 8, 1),
    ),
  ];

  final highlights = [
    StudyNote(
      id: 'h1',
      book: 'Genesis',
      chapter: 1,
      verse: 3,
      verseText: 'En God zeide: Daar zij licht! en daar werd licht.',
      noteText: '',
      translation: 'statenvertaling',
      color: HighlightColor.green,
      isHighlight: true,
      updatedAt: DateTime(2026, 8, 2),
    ),
  ];

  final bookmarks = [
    Bookmark(
      id: 'b1',
      book: 'Johannes',
      chapter: 3,
      verse: 16,
      version: 'statenvertaling',
      label: 'Kernvers over Gods liefde voor de wereld',
      updatedAt: DateTime(2026, 8, 3),
    ),
  ];

  final history = [
    ReadingPosition(
      id: 'r1',
      book: 'Genesis',
      chapter: 1,
      version: 'statenvertaling',
      scrollProgress: 0.4,
      readAt: DateTime(2026, 8, 5),
    ),
  ];

  Widget host(Widget child) {
    return ProviderScope(
      overrides: [
        // sqflite has no databaseFactory under flutter_test; the cache is
        // optional by design, so the widgets take the null path.
        contentCacheProvider.overrideWithValue(null),
        bibleVersionsProvider.overrideWith((ref) async => versions),
        commentarySourcesProvider.overrideWith((ref) async => commentaries),
        bibleBooksProvider.overrideWith(
          (ref, versionId) async => const ['Genesis', 'Exodus'],
        ),
        bibleChaptersProvider.overrideWith(
          (ref, bookRef) async => List<int>.generate(50, (i) => i + 1),
        ),
        chapterContentProvider.overrideWith((ref, chapterRef) async => chapter),
        // No account behind these renders, so the reader settles on its
        // Genesis 1 default rather than waiting on a request that cannot land.
        remoteReaderLocationProvider.overrideWith((ref) async => null),
        dashboardRepositoryProvider.overrideWithValue(
          _StubDashboardRepository(),
        ),
        commentaryChapterProvider.overrideWith(
          (ref, chapterRef) async => commentaryChapter,
        ),
        originalChapterProvider.overrideWith(
          (ref, chapterRef) async => OriginalChapter(
            book: 'Genesis',
            chapter: 1,
            attribution:
                'Grondtekst: STEPBible (TAHOT/TAGNT), CC BY 4.0 - tyndale.org',
            verses: [
              OriginalVerse(
                number: 1,
                words: [
                  OriginalWord(
                    original: 'בְּרֵאשִׁית',
                    transliteration: 'be.re.Shit',
                    gloss: 'in beginning',
                    strongs: 'H7225',
                  ),
                ],
              ),
            ],
          ),
        ),
        profileProvider.overrideWith((ref) async => profile),
        notesListProvider.overrideWith((ref) async => notes),
        highlightsListProvider.overrideWith((ref) async => highlights),
        bookmarksProvider.overrideWith((ref) async => bookmarks),
        readingHistoryProvider.overrideWith((ref) async => history),
        // The preview fixtures already describe a fully-populated account,
        // which is exactly what these render checks need.
        dashboardProvider.overrideWith((ref) async => PreviewData.dashboard),
        curatedStudiesProvider.overrideWith(
          (ref) async => PreviewData.curatedStudies,
        ),
        // The studies screen also asks the account which lessons are already
        // done. There is no account here, so answer it locally rather than
        // leaving a real request pending past the end of the test.
        serverStudyLessonsProvider.overrideWith(
          (ref) async => const <String, Set<int>>{},
        ),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: child),
    );
  }

  /// iPhone 14/15 logical size.
  Future<void> pumpAtPhoneSize(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(screen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Scrolls the page to the bottom so lazily-built slivers are laid out too —
  /// an overflow further down the list stays invisible otherwise.
  Future<void> scrollThrough(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'layout error after scroll step $i',
      );
    }
  }

  testWidgets('dashboard renders the hero, stats and book map', (tester) async {
    await pumpAtPhoneSize(tester, const DashboardScreen());

    expectNoLayoutError(tester);
    expect(find.text('GA VERDER WAAR JE GEBLEVEN WAS'), findsOneWidget);
    expect(find.text('Genesis'), findsWidgets);
    // 3 of the 66 books have a chapter read in the canned data.
    expect(find.text('3 / 66'), findsOneWidget);

    await scrollThrough(tester);
  });

  testWidgets('studies screen renders the filter chips and a study card', (
    tester,
  ) async {
    await pumpAtPhoneSize(tester, const StudiesScreen());

    expectNoLayoutError(tester);
    expect(find.text('Alle'), findsOneWidget);
    expect(find.text('De opstanding van Jezus'), findsOneWidget);

    await scrollThrough(tester);
  });

  testWidgets('reader renders a chapter with verse numbers', (tester) async {
    await pumpAtPhoneSize(tester, const ReadScreen());

    expectNoLayoutError(tester);
    expect(find.text('Genesis 1'), findsOneWidget);
    expect(find.textContaining('In den beginne schiep God'), findsOneWidget);
    // Attribution is a rights requirement, not decoration.
    expect(find.textContaining('publiek domein'), findsOneWidget);
  });

  testWidgets('commentary labels verse 0 as the introduction', (tester) async {
    await pumpAtPhoneSize(tester, const CommentaryScreen());

    expectNoLayoutError(tester);
    expect(find.text('INLEIDING'), findsOneWidget);
    expect(find.text('VERS 0'), findsNothing);
  });

  testWidgets('notes screen renders notes, highlights and bookmarks', (
    tester,
  ) async {
    await pumpAtPhoneSize(tester, const NotesScreen());

    expectNoLayoutError(tester);
    expect(find.text('Genesis 1:1'), findsOneWidget);

    await tester.tap(find.text('Bladwijzers'));
    await tester.pumpAndSettle();
    expectNoLayoutError(tester);
    expect(find.text('Johannes 3:16'), findsOneWidget);
  });

  testWidgets('profile renders Pro status and the delete action', (
    tester,
  ) async {
    await pumpAtPhoneSize(tester, const ProfileScreen());

    expectNoLayoutError(tester);
    expect(find.text('Alex Lamper'), findsOneWidget);

    await scrollThrough(tester);
    // Guideline 5.1.1(v): deletion must be reachable in-app.
    expect(find.text('Account verwijderen'), findsOneWidget);
  });

  testWidgets('settings renders the reader controls', (tester) async {
    await pumpAtPhoneSize(tester, const SettingsScreen());

    expectNoLayoutError(tester);
    expect(find.text('Tekstgrootte'), findsOneWidget);
    await scrollThrough(tester);
  });

  testWidgets('onboarding renders all pages without layout errors', (
    tester,
  ) async {
    await pumpAtPhoneSize(tester, const OnboardingScreen());
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'onboarding page $i');
    }
    expect(find.text('Aan de slag'), findsOneWidget);
  });
}
