import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/content_cache.dart';
import '../../features/bible/domain/bible_models.dart';
import '../../features/bible/present/bible_providers.dart';
import '../../features/dashboard/data/dashboard_models.dart';
import '../../features/dashboard/present/dashboard_providers.dart';
import '../../features/notes/domain/note_models.dart';
import '../../features/notes/present/notes_providers.dart';
import '../../features/profile/data/profile_model.dart';
import '../../features/profile/present/profile_provider.dart';
import '../../features/studies/data/study_models.dart';
import '../../features/studies/present/studies_providers.dart';

/// Canned data for design-preview mode.
///
/// `flutter run -d chrome --dart-define=PREVIEW=true` boots straight into the
/// reader with this data, so the UI can be reviewed without a login, a running
/// backend, or a network. It is hard-disabled in release builds
/// (see [PreviewConfig]), so it cannot ship.
class PreviewData {
  const PreviewData._();

  static const List<BibleSource> versions = [
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

  static const List<BibleSource> commentaries = [
    BibleSource(
      id: 'matthew_henry_nl',
      name: 'Matthew Henry (NL)',
      language: 'nl',
      attribution: 'Matthew Henry (1662–1714) — publiek domein',
    ),
  ];

  static const List<String> books = [
    'Genesis',
    'Exodus',
    'Psalmen',
    'Jesaja',
    'Johannes',
    'Romeinen',
  ];

  static const ChapterContent chapter = ChapterContent(
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
      Verse(
        number: 4,
        text:
            'En God zag het licht, dat het goed was; en God maakte scheiding '
            'tussen het licht en tussen de duisternis.',
      ),
      Verse(
        number: 5,
        text:
            'En God noemde het licht dag, en de duisternis noemde Hij nacht. '
            'Toen was het avond geweest, en het was morgen geweest, de eerste dag.',
      ),
    ],
  );

  static const ChapterContent commentaryChapter = ChapterContent(
    sourceId: 'matthew_henry_nl',
    book: 'Genesis',
    chapter: 1,
    attribution: 'Matthew Henry (1662–1714) — publiek domein',
    verses: [
      // Verse 0 is the chapter introduction — that is how the corpus keys it.
      Verse(
        number: 0,
        text:
            'Daar de grondslag van alle Godsdienst gelegd is in onze betrekking '
            'tot God als onze Schepper, was het voegzaam dat het boek van de '
            'Goddelijke openbaringen begint met een bericht van de schepping.',
      ),
      Verse(
        number: 1,
        text: 'De eerste woorden van de Schrift stellen God voor als de Schepper.',
      ),
    ],
  );

  static final ProfileModel profile = ProfileModel(
    id: 'preview-user',
    name: 'Preview Gebruiker',
    email: 'preview@bijbel-studie.com',
    isPro: true,
    proSource: 'apple',
    proExpiresAt: DateTime.now().add(const Duration(days: 300)),
  );

  static final List<StudyNote> notes = [
    StudyNote(
      id: 'preview-note-1',
      book: 'Genesis',
      chapter: 1,
      verse: 1,
      verseText: 'In den beginne schiep God den hemel en de aarde.',
      noteText: 'Alles begint bij God als Schepper.',
      translation: 'statenvertaling',
      isHighlight: false,
      updatedAt: DateTime.now(),
    ),
  ];

  static final List<StudyNote> highlights = [
    StudyNote(
      id: 'preview-highlight-1',
      book: 'Genesis',
      chapter: 1,
      verse: 3,
      verseText: 'En God zeide: Daar zij licht! en daar werd licht.',
      noteText: '',
      translation: 'statenvertaling',
      color: HighlightColor.green,
      isHighlight: true,
      updatedAt: DateTime.now(),
    ),
  ];

  static final List<ReadingPosition> history = [
    ReadingPosition(
      id: 'preview-position-1',
      book: 'Genesis',
      chapter: 1,
      version: 'statenvertaling',
      scrollProgress: 0.35,
      readAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  static final List<CuratedStudy> curatedStudies = [
    const CuratedStudy(
      id: 'opstanding',
      type: 'Gedeelte',
      title: 'De opstanding van Jezus',
      description:
          'Hoe het lege graf de wereld voor altijd veranderde — van wanhoop '
          'naar hoop.',
      durationLabel: '3 lessen',
      startBook: 'Johannes',
      startChapter: 20,
      startVersion: 'statenvertaling',
      image: '',
      lessons: [
        StudyLesson(
          day: 1,
          title: 'Het lege graf',
          book: 'Johannes',
          chapter: 20,
          verseRange: '1–18',
          focus: 'Wie waren de eerste getuigen?',
        ),
      ],
    ),
  ];

  static final DashboardData dashboard = DashboardData(
    name: profile.name,
    isPro: profile.isPro,
    streak: 7,
    freezes: 1,
    readChapters: const {
      'Genesis': [1, 2, 3],
      'Psalmen': [23],
      'Johannes': [1, 3],
    },
    weekDays: const [
      WeekDay(label: 'Ma', count: 1, heightPct: 50, isToday: false),
      WeekDay(label: 'Di', count: 2, heightPct: 100, isToday: false),
      WeekDay(label: 'Wo', count: 0, heightPct: 0, isToday: false),
      WeekDay(label: 'Do', count: 1, heightPct: 50, isToday: false),
      WeekDay(label: 'Vr', count: 1, heightPct: 50, isToday: false),
      WeekDay(label: 'Za', count: 0, heightPct: 0, isToday: false),
      WeekDay(label: 'Zo', count: 1, heightPct: 50, isToday: true),
    ],
    weekTotal: 6,
    notesCount: 1,
    recentNotes: const [
      RecentNote(
        id: 'preview-note-1',
        book: 'Genesis',
        chapter: 1,
        verse: 1,
        text: 'Alles begint bij God als Schepper.',
      ),
    ],
    lastRead: const LastRead(
      book: 'Genesis',
      chapter: 1,
      version: 'statenvertaling',
    ),
    dailyVerse: const DailyVerse(
      text: 'Want alzo lief heeft God de wereld gehad.',
      reference: 'Johannes 3:16',
      book: 'Johannes',
      chapter: 3,
      verse: 16,
    ),
    activePlan: const ActivePlanSummary(
      id: 'preview-plan',
      title: 'Het evangelie van Johannes',
      duration: 21,
      completedDays: 7,
      progressPercentage: 33,
    ),
  );

  /// Wraps the app in a ProviderScope whose network-backed providers are
  /// replaced by the canned values above.
  static Widget scope(Widget child) {
    return ProviderScope(
      overrides: [
        dashboardProvider.overrideWith((ref) async => dashboard),
        curatedStudiesProvider.overrideWith((ref) async => curatedStudies),
        // Preview runs in a browser or a test, where there is no sqflite.
        contentCacheProvider.overrideWithValue(null),
        bibleVersionsProvider.overrideWith((ref) async => versions),
        commentarySourcesProvider.overrideWith((ref) async => commentaries),
        bibleBooksProvider.overrideWith((ref, versionId) async => books),
        bibleChaptersProvider.overrideWith(
          (ref, bookRef) async => List<int>.generate(50, (i) => i + 1),
        ),
        chapterContentProvider.overrideWith((ref, chapterRef) async => chapter),
        commentaryChapterProvider.overrideWith((ref, chapterRef) async => commentaryChapter),
        profileProvider.overrideWith((ref) async => profile),
        notesListProvider.overrideWith((ref) async => notes),
        highlightsListProvider.overrideWith((ref) async => highlights),
        bookmarksProvider.overrideWith((ref) async => const <Bookmark>[]),
        readingHistoryProvider.overrideWith((ref) async => history),
      ],
      child: child,
    );
  }
}
