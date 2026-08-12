import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/core/db/content_cache.dart';
import 'package:bijbelstudie_mobile/core/preview/preview_data.dart';
import 'package:bijbelstudie_mobile/core/theme/app_theme.dart';
import 'package:bijbelstudie_mobile/features/bible/domain/bible_models.dart';
import 'package:bijbelstudie_mobile/features/bible/present/bible_providers.dart';
import 'package:bijbelstudie_mobile/features/bible/present/read_screen.dart';
import 'package:bijbelstudie_mobile/features/commentary/present/commentary_screen.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_models.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_providers.dart';
import 'package:bijbelstudie_mobile/features/dashboard/present/dashboard_screen.dart';
import 'package:bijbelstudie_mobile/features/notes/domain/note_models.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_providers.dart';
import 'package:bijbelstudie_mobile/features/notes/present/notes_screen.dart';
import 'package:bijbelstudie_mobile/features/premium/present/premium_controller.dart';
import 'package:bijbelstudie_mobile/features/premium/present/premium_screen.dart';
import 'package:bijbelstudie_mobile/features/profile/data/profile_model.dart';
import 'package:bijbelstudie_mobile/features/profile/present/profile_provider.dart';
import 'package:bijbelstudie_mobile/features/profile/present/profile_screen.dart';
import 'package:bijbelstudie_mobile/features/studies/data/study_models.dart';
import 'package:bijbelstudie_mobile/features/studies/present/studies_providers.dart';
import 'package:bijbelstudie_mobile/features/studies/present/studies_screen.dart';

/// Renders the store screenshots.
///
/// iOS cannot be built on this machine, so these come out of the widget tester
/// rather than a simulator. The surface is set to the 6.5" display's native
/// **1284 × 2778 px** — 428 × 926 logical at devicePixelRatio 3 — and captured
/// at that same ratio, so the PNGs are pixel-exact and never resampled. Apple
/// derives every smaller size from this one.
///
/// Run with:
///   flutter test test/screenshots_test.dart
///
/// Output: ../screenshots/6.5/
const double kScale = 3.0;
const Size kLogicalSize = Size(428, 926);

const String kOutDir = '../screenshots/6.5';

final GlobalKey _captureKey = GlobalKey();

/// The icon font ships with the framework, not with the app, so it is loaded
/// from the Flutter cache. Without it every `Icon()` renders as an empty box.
Future<void> loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:lutter';
  final file = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (!file.existsSync()) {
    throw StateError('Material icon font not found at ${file.path}');
  }
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer)));
  await loader.load();
}

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
    'Lora': ['assets/fonts/Lora-Variable.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }
}

/// A paywall that shows real prices instead of the `—` placeholder the empty
/// offering would render. Apple requires a screenshot of this screen for each
/// subscription product, and a dashed price reads as a broken build.
class _StubPremiumController extends PremiumController {
  static const _context = PresentedOfferingContext('default', null, null);

  static Package _package(
    String packageId,
    PackageType type,
    String productId,
    double price,
    String priceString,
    String title,
    String period,
  ) {
    return Package(
      packageId,
      type,
      StoreProduct(
        productId,
        'BijbelStudie Pro',
        title,
        price,
        priceString,
        'EUR',
        subscriptionPeriod: period,
        presentedOfferingContext: _context,
      ),
      _context,
    );
  }

  @override
  PremiumState build() {
    return PremiumState(
      packages: [
        _package(
          r'$rc_monthly',
          PackageType.monthly,
          'bijbelstudie_pro_monthly',
          9.99,
          '€ 9,99',
          'BijbelStudie Pro maandelijks',
          'P1M',
        ),
        _package(
          r'$rc_annual',
          PackageType.annual,
          'bijbelstudie_pro_yearly',
          69.99,
          '€ 69,99',
          'BijbelStudie Pro jaarlijks',
          'P1Y',
        ),
      ],
    );
  }
}

/// `PreviewData.dashboard` greets "Preview Gebruiker"; a store screenshot
/// should show a real name.
final DashboardData _dashboard = DashboardData(
  name: 'Alex',
  isPro: PreviewData.dashboard.isPro,
  streak: PreviewData.dashboard.streak,
  freezes: PreviewData.dashboard.freezes,
  readChapters: PreviewData.dashboard.readChapters,
  weekDays: PreviewData.dashboard.weekDays,
  weekTotal: PreviewData.dashboard.weekTotal,
  notesCount: PreviewData.dashboard.notesCount,
  recentNotes: PreviewData.dashboard.recentNotes,
  lastRead: PreviewData.dashboard.lastRead,
  dailyVerse: PreviewData.dashboard.dailyVerse,
  activePlan: PreviewData.dashboard.activePlan,
);

const List<BiblePlan> _plans = [
  BiblePlan(
    id: 'p1',
    title: 'Het evangelie van Johannes in 21 dagen',
    description: 'Elke dag een hoofdstuk, met een korte vraag om over door te denken.',
    duration: 21,
    category: 'Nieuwe Testament',
    isEnrolled: true,
    completedDays: [1, 2, 3, 4, 5],
    progressPercentage: 24,
    readings: [
      PlanReading(day: 1, book: 'Johannes', chapter: 1, title: 'Het Woord werd vlees'),
      PlanReading(day: 2, book: 'Johannes', chapter: 2, title: 'De bruiloft te Kana'),
    ],
  ),
  BiblePlan(
    id: 'p2',
    title: 'De Psalmen in een maand',
    description: 'Vijf psalmen per dag, van klaagzang tot lofprijzing.',
    duration: 30,
    category: 'Oude Testament',
    isEnrolled: false,
    completedDays: [],
    progressPercentage: 0,
    readings: [
      PlanReading(day: 1, book: 'Psalmen', chapter: 1, title: 'De twee wegen'),
    ],
  ),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ReadScreen and CommentaryScreen read the reader preferences on mount;
    // without a mock the plugin channel throws MissingPluginException.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadMaterialIcons();
    await loadAppFonts();
    Directory(kOutDir).createSync(recursive: true);
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
      Verse(number: 4, text: 'En God zag het licht, dat het goed was; en God maakte '
          'scheiding tussen het licht en tussen de duisternis.'),
      Verse(number: 5, text: 'En God noemde het licht dag, en de duisternis noemde Hij '
          'nacht. Toen was het avond geweest, en het was morgen geweest, de eerste dag.'),
      Verse(number: 6, text: 'En God zeide: Daar zij een uitspansel in het midden der '
          'wateren; en dat make scheiding tussen wateren en wateren!'),
    ],
  );

  const commentaryChapter = ChapterContent(
    sourceId: 'matthew_henry_nl',
    book: 'Genesis',
    chapter: 1,
    attribution: 'Matthew Henry (1662–1714) — publiek domein',
    verses: [
      Verse(
        number: 0,
        text: 'De grondslag van alle Godsdienst ligt in God als Schepper. Het eerste '
            'hoofdstuk van de Bijbel geeft geen bewijs voor Gods bestaan, maar zet Hem '
            'zonder omhaal aan het begin van alles wat is.',
      ),
      Verse(
        number: 1,
        text: 'De eerste woorden stellen God voor als de Schepper. Hemel en aarde staan '
            'hier voor het geheel van de schepping, zichtbaar en onzichtbaar.',
      ),
      Verse(
        number: 3,
        text: 'Het licht wordt geroepen, niet gemaakt uit iets anders. Gods woord is '
            'genoeg; wat Hij spreekt, staat er.',
      ),
    ],
  );

  final proProfile = ProfileModel(
    id: 'u1',
    name: 'Alex Lamper',
    email: 'alex@bijbel-studie.com',
    isPro: true,
    proSource: 'apple',
    proExpiresAt: DateTime(2027, 3, 1),
  );

  final freeProfile = ProfileModel(
    id: 'u1',
    name: 'Alex Lamper',
    email: 'alex@bijbel-studie.com',
    isPro: false,
  );

  final notes = [
    StudyNote(
      id: 'n1',
      book: 'Genesis',
      chapter: 1,
      verse: 1,
      verseText: 'In den beginne schiep God den hemel en de aarde.',
      noteText: 'Alles begint bij God als Schepper — niet bij de mens.',
      translation: 'statenvertaling',
      isHighlight: false,
      updatedAt: DateTime(2026, 8, 1),
    ),
    StudyNote(
      id: 'n2',
      book: 'Johannes',
      chapter: 1,
      verse: 14,
      verseText: 'En het Woord is vlees geworden, en heeft onder ons gewoond.',
      noteText: 'Parallel met Genesis 1: opnieuw begint alles met het Woord.',
      translation: 'statenvertaling',
      isHighlight: false,
      updatedAt: DateTime(2026, 8, 4),
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

  Widget host(Widget child, {required ProfileModel profile}) {
    return ProviderScope(
      overrides: [
        contentCacheProvider.overrideWithValue(null),
        bibleVersionsProvider.overrideWith((ref) async => versions),
        commentarySourcesProvider.overrideWith((ref) async => commentaries),
        bibleBooksProvider.overrideWith((ref, versionId) async => const ['Genesis', 'Exodus']),
        bibleChaptersProvider.overrideWith(
          (ref, bookRef) async => List<int>.generate(50, (i) => i + 1),
        ),
        chapterContentProvider.overrideWith((ref, chapterRef) async => chapter),
        commentaryChapterProvider.overrideWith((ref, chapterRef) async => commentaryChapter),
        profileProvider.overrideWith((ref) async => profile),
        notesListProvider.overrideWith((ref) async => notes),
        highlightsListProvider.overrideWith((ref) async => highlights),
        bookmarksProvider.overrideWith((ref) async => bookmarks),
        readingHistoryProvider.overrideWith((ref) async => history),
        dashboardProvider.overrideWith((ref) async => _dashboard),
        curatedStudiesProvider.overrideWith((ref) async => PreviewData.curatedStudies),
        biblePlansProvider.overrideWith((ref, type) async => _plans),
        premiumControllerProvider.overrideWith(_StubPremiumController.new),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(key: _captureKey, child: child),
      ),
    );
  }

  Future<void> capture(WidgetTester tester, String fileName) async {
    // Let any pending image/layout work finish before reading pixels.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final boundary = _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    late final ByteData? png;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: kScale);
      png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
    });

    final bytes = png!.buffer.asUint8List();
    final file = File('$kOutDir/$fileName.png');
    file.writeAsBytesSync(bytes);

    // Guard the one thing Apple rejects outright: wrong dimensions. Read them
    // straight out of the PNG's IHDR chunk — `decodeImageFromList` needs the
    // real event loop and deadlocks under the test binding.
    final header = ByteData.view(bytes.buffer);
    expect(header.getUint32(16), 1284, reason: '$fileName has the wrong width');
    expect(header.getUint32(20), 2778, reason: '$fileName has the wrong height');
  }

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    ProfileModel? profile,
  }) async {
    tester.view.physicalSize = kLogicalSize * kScale;
    tester.view.devicePixelRatio = kScale;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(screen, profile: profile ?? proProfile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('01 dashboard', (tester) async {
    await pump(tester, const DashboardScreen());
    await capture(tester, '01-dashboard');
  });

  testWidgets('02 reader', (tester) async {
    await pump(tester, const ReadScreen());
    await capture(tester, '02-lezen');
  });

  testWidgets('03 commentary', (tester) async {
    await pump(tester, const CommentaryScreen());
    await capture(tester, '03-commentaar');
  });

  testWidgets('04 studies', (tester) async {
    await pump(tester, const StudiesScreen());
    await capture(tester, '04-studies');
  });

  testWidgets('05 notes', (tester) async {
    await pump(tester, const NotesScreen());
    await capture(tester, '05-notities');
  });

  testWidgets('06 profile', (tester) async {
    await pump(tester, const ProfileScreen());
    await capture(tester, '06-profiel');
  });

  testWidgets('07 paywall', (tester) async {
    await pump(tester, const PremiumScreen(), profile: freeProfile);
    await capture(tester, '07-pro');
  });
}
