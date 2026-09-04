import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:go_router/go_router.dart';

import 'package:bijbelstudie_mobile/features/dashboard/data/daily_verse_store.dart';
import 'package:bijbelstudie_mobile/core/db/content_cache.dart';
import 'package:bijbelstudie_mobile/core/router/app_router.dart';
import 'package:bijbelstudie_mobile/core/preview/preview_data.dart';
import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';
import 'package:bijbelstudie_mobile/features/bible/domain/bible_models.dart';
import 'package:bijbelstudie_mobile/features/bible/present/bible_providers.dart';
import 'package:bijbelstudie_mobile/features/bible/present/read_screen.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_providers.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_screen.dart';
import 'package:bijbelstudie_mobile/features/studies/data/enrollment_models.dart';
import 'package:bijbelstudie_mobile/features/studies/present/studies_providers.dart';
import 'package:bijbelstudie_mobile/features/study/data/context_repository.dart';
import 'package:bijbelstudie_mobile/features/study/present/study_pane_controller.dart';
import 'package:bijbelstudie_mobile/features/study/present/study_screen.dart';
import 'package:bijbelstudie_mobile/features/studies/present/studies_screen.dart';
import 'package:bijbelstudie_mobile/features/commentary/present/commentary_screen.dart';
import 'package:bijbelstudie_mobile/features/notes/domain/note_models.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_providers.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_screen.dart';
import 'package:bijbelstudie_mobile/features/onboarding/present/onboarding_screen.dart';
import 'package:bijbelstudie_mobile/features/onboarding/present/setup_flow_screen.dart';
import 'package:bijbelstudie_mobile/features/onboarding/present/tour_controller.dart';
import 'package:bijbelstudie_mobile/features/onboarding/present/tour_overlay.dart';
import 'package:bijbelstudie_mobile/features/profile/data/profile_model.dart';
import 'package:bijbelstudie_mobile/features/profile/present/profile_provider.dart';
import 'package:bijbelstudie_mobile/features/profile/present/profile_screen.dart';
import 'package:bijbelstudie_mobile/features/settings/data/reading_settings.dart';
import 'package:bijbelstudie_mobile/features/settings/present/settings_screen.dart';
import 'package:bijbelstudie_mobile/features/settings/present/theme_mode_provider.dart';

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

  @override
  Future<List<DailyVerseEntry>> getDayTextHistory({int limit = 60}) async =>
      const [];
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

  fail('Layout error:\n$error\n\nOverflowing widget(s):\n${culprits.join('\n\n')}');
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
      loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
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
      Verse(number: 1, text: 'In den beginne schiep God den hemel en de aarde.'),
      Verse(
        number: 2,
        text:
            'De aarde nu was woest en ledig, en duisternis was op den afgrond; '
            'en de Geest Gods zweefde op de wateren.',
      ),
      Verse(number: 3, text: 'En God zeide: Daar zij licht! en daar werd licht.'),
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
      Verse(number: 0, text: 'De grondslag van alle Godsdienst ligt in God als Schepper.'),
      Verse(number: 1, text: 'De eerste woorden stellen God voor als de Schepper.'),
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

  // Type inferred: `Override` is not exported from flutter_riverpod.
  final testOverrides = [
    // sqflite has no databaseFactory under flutter_test; the cache is
    // optional by design, so the widgets take the null path.
    contentCacheProvider.overrideWithValue(null),
    bibleVersionsProvider.overrideWith((ref) async => versions),
    commentarySourcesProvider.overrideWith((ref) async => commentaries),
    bibleBooksProvider.overrideWith((ref, versionId) async => const ['Genesis', 'Exodus']),
    bibleChaptersProvider.overrideWith(
      (ref, bookRef) async => List<int>.generate(50, (i) => i + 1),
    ),
    chapterContentProvider.overrideWith((ref, chapterRef) async => chapter),
    // No account behind these renders, so the reader settles on its
    // Genesis 1 default rather than waiting on a request that cannot land.
    remoteReaderLocationProvider.overrideWith((ref) async => null),
    dashboardRepositoryProvider.overrideWithValue(_StubDashboardRepository()),
    commentaryChapterProvider.overrideWith((ref, chapterRef) async => commentaryChapter),
    originalChapterProvider.overrideWith(
      (ref, chapterRef) async => OriginalChapter(
        book: 'Genesis',
        chapter: 1,
        attribution: 'Grondtekst: STEPBible (TAHOT/TAGNT), CC BY 4.0 - tyndale.org',
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
    curatedStudiesProvider.overrideWith((ref) async => PreviewData.curatedStudies),
    // The studies screen also asks the account which lessons are already
    // done. There is no account here, so answer it locally rather than
    // leaving a real request pending past the end of the test.
    serverStudyLessonsProvider.overrideWith((ref) async => const <String, Set<int>>{}),
    // Same for the enrollments the catalogue reads to decide what is started.
    studyEnrollmentsProvider.overrideWith(
      (ref) async => const <String, StudyEnrollment>{},
    ),
    // The study screen's IndexedStack builds every tab, so the materials
    // pane's own fetches have to be answered locally too — otherwise these
    // renders reach the network, which is the thing this harness exists to
    // prevent.
    bookSummaryProvider.overrideWith((ref, book) async => 'Genesis opent met de schepping.'),
    geoImagesProvider.overrideWith((ref, geoRef) async => const <GeoImage>[]),
  ];

  Widget host(Widget child) {
    return ProviderScope(
      overrides: testOverrides,
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

  /// Mounts [screen] with the tour overlay above it, exactly as `main.dart`
  /// does, and starts the tour.
  ///
  /// `routerProvider` is overridden because the overlay navigates between
  /// steps; the real one starts at the splash screen and would take the test
  /// through auth. The routes here render nothing - only `/dashboard` matters,
  /// and a step whose anchor is not mounted simply shows its card centred,
  /// which is the behaviour being relied on for the later steps.
  Future<void> pumpTour(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => screen),
        for (final path in ['/study', '/studies', '/notes', '/profile'])
          GoRoute(path: path, builder: (_, __) => const SizedBox.shrink()),
      ],
    );
    addTearDown(router.dispose);

    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...testOverrides, routerProvider.overrideWithValue(router)],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
              builder: (context, child) => TourHost(child: child ?? const SizedBox.shrink()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    captured.read(tourControllerProvider.notifier).start();
    await tester.pumpAndSettle();
  }

  /// The rectangle the overlay cut out of the scrim, or null when it never
  /// found the step's anchor and fell back to a centred card.
  Rect? tourSpotlight(WidgetTester tester) {
    final paint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((p) => p.painter is TourScrimPainter)
        .firstOrNull;
    return (paint?.painter as TourScrimPainter?)?.hole;
  }

  /// Scrolls the page to the bottom so lazily-built slivers are laid out too —
  /// an overflow further down the list stays invisible otherwise.
  Future<void> scrollThrough(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'layout error after scroll step $i');
    }
    // A drag that happens to start on a widget listening for a double tap —
    // the book map does — leaves that recognizer's countdown running, and the
    // bare `pump` above never advances the clock far enough to retire it. Let
    // those timers expire here, or the test ends with a timer still pending
    // whenever the layout shifts a drag onto such a widget.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('dashboard renders the hero, the book map and the daily verse', (
    tester,
  ) async {
    await pumpAtPhoneSize(tester, const DashboardScreen());

    expectNoLayoutError(tester);
    expect(find.text('GA VERDER WAAR JE GEBLEVEN WAS'), findsOneWidget);
    expect(find.text('Genesis'), findsWidgets);
    // The stat strip moved to the profile screen; the photo card took its
    // place as the first thing under the hero that carries a heading.
    expect(find.text('TEKST VAN DE DAG'), findsOneWidget);
    expect(find.text('Johannes 3:16 SV'), findsOneWidget);

    await scrollThrough(tester);
  });

  testWidgets('studies screen renders the filter chips and a study card', (tester) async {
    await pumpAtPhoneSize(tester, const StudiesScreen());

    expectNoLayoutError(tester);
    expect(find.text('Alle'), findsOneWidget);
    // The tabs, the topic grid and the kind pills all have to be there, or the
    // catalogue is a flat list again.
    expect(find.text('Ontdek'), findsOneWidget);
    expect(find.text('Mijn studies'), findsOneWidget);
    expect(find.text('Bijbelboeken'), findsOneWidget);
    // The one fixture study is both the featured card and a row in the list,
    // so its title legitimately renders twice.
    expect(find.text('De opstanding van Jezus'), findsWidgets);

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

  testWidgets('notes screen renders notes, highlights and bookmarks', (tester) async {
    await pumpAtPhoneSize(tester, const NotesScreen());

    expectNoLayoutError(tester);
    expect(find.text('Genesis 1:1'), findsOneWidget);

    await tester.tap(find.text('Bladwijzers'));
    await tester.pumpAndSettle();
    expectNoLayoutError(tester);
    expect(find.text('Johannes 3:16'), findsOneWidget);
  });

  testWidgets('profile renders Pro status and the delete action', (tester) async {
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

  testWidgets('onboarding renders all pages without layout errors', (tester) async {
    await pumpAtPhoneSize(tester, const OnboardingScreen());
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'onboarding page $i');
    }
    expect(find.text('Aan de slag'), findsOneWidget);
  });

  testWidgets('setup wizard walks through translation, reading prefs and reminder', (tester) async {
    await pumpAtPhoneSize(tester, const SetupFlowScreen());
    expectNoLayoutError(tester);
    expect(find.text('Kies je bijbelvertaling'), findsOneWidget);
    // From the canned bibleVersionsProvider override.
    expect(find.text('Statenvertaling'), findsOneWidget);

    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();
    expectNoLayoutError(tester);
    expect(find.text('Stel je leesvoorkeuren in'), findsOneWidget);
    expect(find.text('Tekstgrootte'), findsOneWidget);
    expect(find.text('Regelafstand'), findsOneWidget);

    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();
    expectNoLayoutError(tester);
    expect(find.text('Licht of donker?'), findsOneWidget);
    expect(find.text('Licht'), findsOneWidget);
    expect(find.text('Donker'), findsOneWidget);
    expect(find.text('Systeem'), findsOneWidget);

    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();
    expectNoLayoutError(tester);
    expect(find.text('Wanneer komt het jou uit?'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    // Last step: the button reads "Aan de slag", not "Volgende". Not tapped
    // - finishing writes to secure storage, which has no test double here.
    expect(find.text('Aan de slag'), findsOneWidget);
  });

  testWidgets('a translation dropped from the app falls back instead of dead-ending',
      (tester) async {
    // Luther 1912 left MOBILE_ALLOWED_BIBLES, but the id the reader last used
    // lives on the device. Such a device would open on the 451 empty state
    // every launch; the reader bar switches it to the first translation the
    // server still offers.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader.lastVersionId': 'luther_1912',
      'reader.lastBook': 'Genesis',
      'reader.lastChapter': 1,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    await pumpAtPhoneSize(tester, const ReadScreen());
    final container = ProviderScope.containerOf(tester.element(find.byType(ReadScreen)));
    await tester.pumpAndSettle();

    expect(container.read(readerLocationProvider).versionId, 'statenvertaling');
    expect(find.text('Niet beschikbaar in de app'), findsNothing);
  });

  group('study screen panes', () {
    testWidgets('opens on the reader and switches to the materials tabs',
        (tester) async {
      await pumpAtPhoneSize(tester, const StudyScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudyScreen)),
      );

      expect(container.read(studyPaneProvider).showMaterials, isFalse);
      expect(find.textContaining('In den beginne'), findsOneWidget);

      await tester.tap(find.text('Studie'));
      await tester.pumpAndSettle();
      expectNoLayoutError(tester);

      expect(container.read(studyPaneProvider).showMaterials, isTrue);
      expect(find.text('Commentaar'), findsWidgets);
      expect(find.text('Grondtekst'), findsOneWidget);
    });

    testWidgets('the tab bar and the provider stay in step both ways',
        (tester) async {
      // The pane state moved out of the screen so the guided tour can drive
      // it; the screen has to keep writing back, or the tour reads a stale
      // tab index.
      await pumpAtPhoneSize(tester, const StudyScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudyScreen)),
      );

      container.read(studyPaneProvider.notifier).showMaterials();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notities'));
      await tester.pumpAndSettle();
      expect(container.read(studyPaneProvider).materialsTab, 3);

      // Driven from outside, as the tour does it.
      container.read(studyPaneProvider.notifier).setMaterialsTab(1);
      await tester.pumpAndSettle();
      expectNoLayoutError(tester);
      expect(find.textContaining('be.re.Shit'), findsOneWidget);
    });
  });

  group('setup wizard applies what it asks for', () {
    testWidgets('groups translations by language with a separator', (tester) async {
      await pumpAtPhoneSize(tester, const SetupFlowScreen());

      // Dutch first, no heading above it; the heading appears where the
      // language actually changes.
      expect(find.text('Statenvertaling'), findsOneWidget);
      expect(find.text('King James Version'), findsOneWidget);
      expect(find.text('NEDERLANDS'), findsNothing);
      expect(find.text('ENGELS'), findsOneWidget);

      final dutch = tester.getTopLeft(find.text('Statenvertaling')).dy;
      final separator = tester.getTopLeft(find.text('ENGELS')).dy;
      final english = tester.getTopLeft(find.text('King James Version')).dy;
      expect(dutch, lessThan(separator));
      expect(separator, lessThan(english));
    });

    testWidgets('picking a translation moves the reader, not just the setting', (tester) async {
      await pumpAtPhoneSize(tester, const SetupFlowScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SetupFlowScreen)),
      );

      // The reader hydrates before the wizard is even reached on a returning
      // account (splash warms it deliberately), so writing the preference
      // alone left the choice with nothing listening — the reader kept
      // whatever it had already settled on for the rest of the session.
      await tester.pumpAndSettle();
      expect(container.read(readerLocationProvider).versionId, 'statenvertaling');

      await tester.tap(find.text('King James Version'));
      await tester.pumpAndSettle();

      expect(container.read(readingSettingsProvider).lastVersionId, 'kjv');
      expect(container.read(readerLocationProvider).versionId, 'kjv');
    });

    testWidgets('reading preferences take effect immediately', (tester) async {
      await pumpAtPhoneSize(tester, const SetupFlowScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SetupFlowScreen)),
      );

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Groot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groot'));
      await tester.pumpAndSettle();
      expect(container.read(readingSettingsProvider).fontSize, ReaderFontSize.large);

      await tester.ensureVisible(find.text('Zeer ruim'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zeer ruim'));
      await tester.pumpAndSettle();
      expect(container.read(readingSettingsProvider).lineHeight, ReaderLineHeight.loose);
    });

    testWidgets('the theme question applies immediately', (tester) async {
      await pumpAtPhoneSize(tester, const SetupFlowScreen());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SetupFlowScreen)),
      );

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Volgende'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Licht of donker?'), findsOneWidget);

      // Stored, and therefore live: main.dart resolves AppTheme's brightness
      // from this same value.
      await tester.tap(find.text('Donker'));
      await tester.pumpAndSettle();
      expect(container.read(readingSettingsProvider).themeMode, ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);

      await tester.tap(find.text('Licht'));
      await tester.pumpAndSettle();
      expect(container.read(readingSettingsProvider).themeMode, ThemeMode.light);
    });
  });

  group('guided tour', () {
    test('drops the Pro step for a subscriber and keeps it for a free account', () {
      final free = TourController.stepsFor(isPro: false);
      final pro = TourController.stepsFor(isPro: true);

      expect(free.map((s) => s.title), contains('Upgrade naar Pro'));
      expect(pro.map((s) => s.title), isNot(contains('Upgrade naar Pro')));
      expect(pro.length, free.length - 1);
    });

    test('every step names an anchor and a route the app actually has', () {
      const routes = {'/dashboard', '/study', '/studies', '/notes', '/profile'};
      for (final step in TourController.stepsFor(isPro: false)) {
        expect(step.anchorId, isNotEmpty, reason: '${step.title} has no anchor');
        expect(routes, contains(step.route), reason: '${step.title} points at ${step.route}');
        expect(step.description, isNotEmpty);
      }
    });

    testWidgets('spotlights the live dashboard card and steps forward', (tester) async {
      // The tour paints over the running app rather than replacing it, so the
      // harness is the real dashboard with the overlay on top - the same shape
      // main.dart builds.
      await pumpTour(tester, const DashboardScreen());

      expect(find.text('Je dashboard'), findsOneWidget);
      expect(find.text('Rondleiding · 1/9'), findsOneWidget);

      // The hero card is a TourAnchor, so the overlay found a rect and the
      // scrim was painted with a hole rather than falling back to a centred
      // card with no spotlight.
      expect(tourSpotlight(tester), isNotNull);

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      expectNoLayoutError(tester);
      // "Bijbelstudie" is also the dashboard's own copy, so the step is
      // identified by the counter and its description instead of its title.
      expect(find.text('Rondleiding · 2/9'), findsOneWidget);
      expect(
        find.textContaining('Via deze tab kom je bij de bijbeltekst'),
        findsOneWidget,
      );

      await tester.tap(find.text('Vorige'));
      await tester.pumpAndSettle();
      expect(find.text('Rondleiding · 1/9'), findsOneWidget);
      expect(find.text('Je dashboard'), findsOneWidget);
    });

    testWidgets('Overslaan closes the overlay and leaves the app alone', (tester) async {
      await pumpTour(tester, const DashboardScreen());
      expect(find.text('Je dashboard'), findsOneWidget);

      await tester.tap(find.text('Overslaan'));
      await tester.pumpAndSettle();

      expect(find.text('Je dashboard'), findsNothing);
      expect(find.text('Overslaan'), findsNothing);
      // The screen underneath is untouched.
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });
}
