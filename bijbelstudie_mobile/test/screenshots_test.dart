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
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_repository.dart';
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
import 'package:bijbelstudie_mobile/features/studies/present/studies_providers.dart';
import 'package:bijbelstudie_mobile/features/studies/present/studies_screen.dart';

import 'screenshot_fixtures.dart';

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
/// One App Store Connect screenshot slot.
///
/// `logical * scale` is the pixel size Apple wants, so the capture is always
/// 1:1 and nothing is ever resampled.
class ShotDevice {
  const ShotDevice({
    required this.slug,
    required this.logical,
    required this.scale,
    required this.pixels,
  });

  final String slug;
  final Size logical;
  final double scale;
  final Size pixels;

  String get outDir => '../screenshots/$slug';
}

const List<ShotDevice> kDevices = [
  // iPhone 14/15 Pro Max — the 6.5"/6.9" slot. Apple derives the smaller
  // iPhone sizes from this one.
  ShotDevice(
    slug: '6.5',
    logical: Size(428, 926),
    scale: 3.0,
    pixels: Size(1284, 2778),
  ),
  // iPad Pro 13" (M4) — the 13" slot, mandatory because the app ships as
  // universal (TARGETED_DEVICE_FAMILY = "1,2").
  ShotDevice(
    slug: '13-ipad',
    logical: Size(1032, 1376),
    scale: 2.0,
    pixels: Size(2064, 2752),
  ),
];

final GlobalKey _captureKey = GlobalKey();

/// The icon font ships with the framework, not with the app, so it is loaded
/// from the Flutter cache. Without it every `Icon()` renders as an empty box.
Future<void> loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (!file.existsSync()) {
    throw StateError('Material icon font not found at ${file.path}');
  }
  final loader = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer),
      ),
    );
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
      loader.addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await loader.load();
  }
}

/// The reader tells the server which chapter was opened. A screenshot run must
/// not, so the repository is swapped for one that answers without a socket —
/// an in-flight Dio request also leaves a pending timer and fails the test.
class _StubDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardData> getDashboard() async => _dashboard;

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
  Future<DailyVerse?> getDailyVerse() async => _dashboard.dailyVerse;
}

/// A paywall that shows real prices instead of the `—` placeholder the empty
/// offering would render. Apple requires a screenshot of this screen for each
/// subscription product, and a dashed price reads as a broken build.
class _StubPremiumController extends PremiumController {
  static const _context = PresentedOfferingContext('default', null, null);

  static StoreProduct _product(
    String productId,
    double price,
    String priceString,
    String title,
    String period,
  ) {
    return StoreProduct(
      productId,
      'BijbelStudie Pro',
      title,
      price,
      priceString,
      'EUR',
      subscriptionPeriod: period,
      presentedOfferingContext: _context,
    );
  }

  static Package _package(String packageId, PackageType type, StoreProduct product) {
    return Package(packageId, type, product, _context);
  }

  static final StoreProduct _monthly = _product(
    'bijbelstudie_pro_monthly',
    9.99,
    '€ 9,99',
    'BijbelStudie Pro maandelijks',
    'P1M',
  );

  static final StoreProduct _yearly = _product(
    'bijbelstudie_pro_yearly',
    69.99,
    '€ 69,99',
    'BijbelStudie Pro jaarlijks',
    'P1Y',
  );

  @override
  PremiumState build() {
    // `priceStatus: ready` with both products present is what a store that
    // answered looks like. Leaving it at the default (`loading`) would put the
    // paywall's buy button in its spinner state, which never settles and is
    // not a screenshot anyone wants on the App Store.
    return PremiumState(
      priceStatus: PriceStatus.ready,
      monthlyProduct: _monthly,
      yearlyProduct: _yearly,
      packages: [
        _package(r'$rc_monthly', PackageType.monthly, _monthly),
        _package(r'$rc_annual', PackageType.annual, _yearly),
      ],
    );
  }

  /// The screenshot host must never reach the real store.
  @override
  Future<void> loadPrices() async {}
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
  badges: PreviewData.dashboard.badges,
  lastRead: PreviewData.dashboard.lastRead,
  dailyVerse: PreviewData.dashboard.dailyVerse,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ReadScreen and CommentaryScreen read the reader preferences on mount;
    // without a mock the plugin channel throws MissingPluginException.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadMaterialIcons();
    await loadAppFonts();
    for (final device in kDevices) {
      Directory(device.outDir).createSync(recursive: true);
    }
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
    attribution: kGenesisAttribution,
    verses: kGenesis1Verses,
  );

  const commentaryChapter = ChapterContent(
    sourceId: 'matthew_henry_nl',
    book: 'Genesis',
    chapter: 1,
    attribution: kCommentaryAttribution,
    verses: kMatthewHenryGenesis1,
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
    StudyNote(
      id: 'n3',
      book: 'Psalmen',
      chapter: 23,
      verse: 1,
      verseText: 'De HEERE is mijn Herder, mij zal niets ontbreken.',
      noteText:
          'Herder is hier geen sfeerbeeld maar een bestuursvorm: de herder '
          'bepaalt de route.',
      translation: 'statenvertaling',
      isHighlight: false,
      updatedAt: DateTime(2026, 8, 6),
    ),
    StudyNote(
      id: 'n4',
      book: 'Genesis',
      chapter: 1,
      verse: 27,
      verseText: 'En God schiep den mens naar Zijn beeld.',
      noteText:
          'Naar Zijn beeld — gezegd van iedereen, voordat er ook maar iets '
          'gepresteerd is.',
      translation: 'statenvertaling',
      isHighlight: false,
      updatedAt: DateTime(2026, 8, 7),
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

  // A saved position in a chapter these shots do not show. The reader restores
  // the offset it holds for the chapter on screen, and a store screenshot has
  // to open at the top of Genesis 1, not forty percent into it.
  final history = [
    ReadingPosition(
      id: 'r1',
      book: 'Johannes',
      chapter: 3,
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
        bibleBooksProvider.overrideWith(
          (ref, versionId) async => const ['Genesis', 'Exodus'],
        ),
        bibleChaptersProvider.overrideWith(
          (ref, bookRef) async => List<int>.generate(50, (i) => i + 1),
        ),
        chapterContentProvider.overrideWith((ref, chapterRef) async => chapter),
        commentaryChapterProvider.overrideWith(
          (ref, chapterRef) async => commentaryChapter,
        ),
        profileProvider.overrideWith((ref) async => profile),
        notesListProvider.overrideWith((ref) async => notes),
        highlightsListProvider.overrideWith((ref) async => highlights),
        bookmarksProvider.overrideWith((ref) async => bookmarks),
        readingHistoryProvider.overrideWith((ref) async => history),
        dashboardProvider.overrideWith((ref) async => _dashboard),
        dashboardRepositoryProvider.overrideWithValue(
          _StubDashboardRepository(),
        ),
        curatedStudiesProvider.overrideWith(
          (ref) async => PreviewData.curatedStudies,
        ),
        // The studies screen also asks the account which lessons are already
        // done. There is no account here, so answer it locally rather than
        // leaving a real request pending past the end of the test.
        serverStudyLessonsProvider.overrideWith(
          (ref) async => const <String, Set<int>>{},
        ),
        premiumControllerProvider.overrideWith(_StubPremiumController.new),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(key: _captureKey, child: child),
      ),
    );
  }

  Future<void> capture(
    WidgetTester tester,
    ShotDevice device,
    String fileName,
  ) async {
    // Let any pending image/layout work finish before reading pixels.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final boundary =
        _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    late final ByteData? png;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: device.scale);
      png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
    });

    final bytes = png!.buffer.asUint8List();
    File('${device.outDir}/$fileName.png').writeAsBytesSync(bytes);

    // Guard the one thing Apple rejects outright: wrong dimensions. Read them
    // straight out of the PNG's IHDR chunk — `decodeImageFromList` needs the
    // real event loop and deadlocks under the test binding.
    final header = ByteData.view(bytes.buffer);
    expect(
      header.getUint32(16),
      device.pixels.width.round(),
      reason: '${device.slug}/$fileName has the wrong width',
    );
    expect(
      header.getUint32(20),
      device.pixels.height.round(),
      reason: '${device.slug}/$fileName has the wrong height',
    );
  }

  Future<void> pump(
    WidgetTester tester,
    ShotDevice device,
    Widget screen, {
    ProfileModel? profile,
  }) async {
    tester.view.physicalSize = device.logical * device.scale;
    tester.view.devicePixelRatio = device.scale;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(screen, profile: profile ?? proProfile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  for (final device in kDevices) {
    group(device.slug, () {
      void shot(
        String fileName,
        Widget Function() screen, {
        bool free = false,
      }) {
        testWidgets(fileName, (tester) async {
          await pump(
            tester,
            device,
            screen(),
            profile: free ? freeProfile : null,
          );
          await capture(tester, device, fileName);
        });
      }

      shot('01-dashboard', DashboardScreen.new);
      shot('02-lezen', ReadScreen.new);
      shot('03-commentaar', CommentaryScreen.new);
      shot('04-studies', StudiesScreen.new);
      shot('05-notities', NotesScreen.new);
      shot('06-profiel', ProfileScreen.new);
      shot('07-pro', PremiumScreen.new, free: true);
    });
  }
}
