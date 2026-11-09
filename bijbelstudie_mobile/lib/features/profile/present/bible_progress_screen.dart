import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/bible_books.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/lucide_icon.dart';
import '../../../core/ui/skeleton.dart';
import '../../auth/present/auth_controller.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/data/resume_link.dart';
import '../../dashboard/domain/bible_milestones.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../study/present/study_pane_controller.dart';
import '../data/finished_books_store.dart';
import '../domain/bible_progress.dart';
import '../domain/bookcase.dart';
import 'bookcase_books.dart';
import 'bookcase_view.dart';

/// Every book with the reader's progress, derived from `/dashboard`.
final bibleProgressProvider = Provider.autoDispose<AsyncValue<BibleProgress>>((ref) {
  return ref
      .watch(dashboardProvider)
      .whenData((data) => BibleProgress.fromReadChapters(data.readChapters));
});

/// Where the leeslint lies: the chapter the reading-ribbon card offers. Null
/// while `/dashboard` is still in flight, and once every chapter is read.
final nextChapterProvider = Provider.autoDispose<NextChapter?>((ref) {
  final data = ref.watch(dashboardProvider).value;
  final progress = ref.watch(bibleProgressProvider).value;
  if (data == null || progress == null) return null;
  final anchor = resumeAnchor(data);
  return nextUnreadChapter(
    progress: progress,
    book: anchor.book,
    chapter: anchor.chapter,
    version: anchor.version,
  );
});

/// One chapter to open, the way the leeslint card and a book's sheet hand it
/// to the reader.
class NextChapter {
  const NextChapter({required this.book, required this.chapter, this.version});

  final String book;
  final int chapter;

  /// The translation to open it in; null keeps the reader's current one.
  final String? version;

  /// "Psalmen 91".
  String get reference => '$book $chapter';
}

/// Where the reader left off: the server's own resume answer when it points at
/// a chapter, else the last chapter read, else where a new reader starts.
///
/// Reuses `resumeTargetFor`, so this page and the "Verder waar je gebleven was"
/// card on Start read the same `resume` object the same way.
({String book, int chapter, String? version}) resumeAnchor(DashboardData data) {
  final href = data.resume?.primary.href;
  if (href != null) {
    final target = resumeTargetFor(href);
    if (target is ResumeChapter) {
      return (
        book: BibleBooks.toCanonical(target.book),
        chapter: target.chapter,
        version: target.version,
      );
    }
  }
  final last = data.lastRead;
  if (last != null) {
    return (
      book: BibleBooks.toCanonical(last.book),
      chapter: last.chapter,
      version: last.version,
    );
  }
  return (book: BibleBooks.startBook, chapter: 1, version: null);
}

/// The first chapter not yet read at or after [book] [chapter], walking the
/// canon forward and wrapping round to Genesis so the anchor book's earlier
/// chapters are offered too. Null once the whole Bible is read.
NextChapter? nextUnreadChapter({
  required BibleProgress progress,
  required String book,
  required int chapter,
  String? version,
}) {
  final byName = {for (final b in progress.books) b.name: b};
  final order = BibleBooks.all;
  final start = math.max(0, order.indexOf(book));

  // One extra step so the anchor book comes round again from chapter 1.
  for (var step = 0; step <= order.length; step++) {
    final name = order[(start + step) % order.length];
    final entry = byName[name];
    if (entry == null) continue;
    final from = step == 0 ? chapter.clamp(1, math.max(1, entry.chapters)).toInt() : 1;
    for (var n = from; n <= entry.chapters; n++) {
      if (!entry.isRead(n)) {
        return NextChapter(book: name, chapter: n, version: version);
      }
    }
  }
  return null;
}

/// "Bijbelvoortgang" at `/profile/bijbel`, reached from the "Je Bijbel" card on
/// Start and the Bijbelboeken tile on Profiel: "Je boekenkast".
///
/// A deep-teal case holds the 66 books as spines. A spine's width follows its
/// chapter count, its colour rises from the bottom as chapters are read, and a
/// finished book wears gold lettering. Each shelf's brass plaque counts its
/// group. A library ladder leaning on the case is the overall bar, with the
/// reader's marker climbing to the share read. Below: where the leeslint lies,
/// the books on the reading table and the next rung on three tracks.
///
/// Read-only: every number comes from `/api/v1/dashboard`. Inside the tab
/// shell, so the bottom bar stays put. Mirrors `/profiel/bijbel` on the
/// website (`components/profile/BibleProgressView.tsx`).
class BibleProgressScreen extends ConsumerStatefulWidget {
  const BibleProgressScreen({super.key});

  @override
  ConsumerState<BibleProgressScreen> createState() => _BibleProgressScreenState();
}

class _BibleProgressScreenState extends ConsumerState<BibleProgressScreen>
    with TickerProviderStateMixin {
  /// Spines filling in a wave, the count running up, the marker climbing.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  /// The sparks over a book finished since the last visit.
  late final AnimationController _celebrate = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// A tapped spine sliding out of the shelf while its sheet is open.
  late final AnimationController _pull = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );

  bool _introStarted = false;
  bool _celebrated = false;

  /// Books finished since the case was last seen on this device.
  List<String> _fresh = const [];
  String? _pulled;
  bool _scrolled = false;

  BookcaseLayout? _layout;
  BibleProgress? _layoutFor;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) _maybeCelebrate();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _celebrate.dispose();
    _pull.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// Runs once, as soon as the progress is first on screen - the page may paint
  /// its skeleton before `/dashboard` answers. Reduce-motion lands on the
  /// finished state without ever ticking.
  void _startIntro(BibleProgress progress) {
    if (_introStarted) return;
    _introStarted = true;
    unawaited(_checkFinished(progress));
    if (_reduceMotion) {
      _intro.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _intro.forward(from: 0);
    });
  }

  /// Compares the finished books with the ones the case last showed and
  /// remembers the new set.
  Future<void> _checkFinished(BibleProgress progress) async {
    final userId = ref.read(authControllerProvider).value?.id;
    final before = await FinishedBooksStore.read(userId);
    if (!mounted) return;
    final now = {for (final b in progress.books) if (b.completed) b.name};
    if (before == null || !setEquals(before, now)) {
      unawaited(FinishedBooksStore.write(userId, now));
    }
    final fresh = newlyFinishedBooks(before: before, now: progress);
    if (fresh.isEmpty) return;
    setState(() => _fresh = fresh);
    _maybeCelebrate();
  }

  /// The sparks go off once the intro has settled, so they do not compete
  /// with the spines filling.
  void _maybeCelebrate() {
    if (!mounted || _fresh.isEmpty || _celebrated || !_intro.isCompleted) return;
    _celebrated = true;
    if (_reduceMotion) return;
    AppHaptics.light();
    unawaited(_celebrate.forward(from: 0));
  }

  void _openChapter(NextChapter target) {
    // Same hand-off as the dashboard's book map: pin the reader, show the
    // reader half of the split screen, go.
    ref.read(readerLocationProvider.notifier).openChapter(
          versionId: target.version,
          book: target.book,
          chapter: target.chapter,
        );
    ref.read(studyPaneProvider.notifier).showReader();
    context.go('/study');
  }

  /// A tapped spine slides out of the shelf and its sheet opens; the spine
  /// slides back when the sheet closes.
  Future<void> _showBook(BookProgress book, NextChapter? next) async {
    AppHaptics.selection();
    final isCurrent = next != null && next.book == book.name;
    setState(() => _pulled = book.name);
    if (_reduceMotion) {
      _pull.value = 1;
    } else {
      unawaited(_pull.forward(from: 0));
    }
    await showShelfBookSheet(
      context,
      book: book,
      leeslint: isCurrent ? next.chapter : null,
      onRead: (chapter) => _openChapter(
        NextChapter(book: book.name, chapter: chapter, version: isCurrent ? next.version : null),
      ),
    );
    if (!mounted) return;
    if (_reduceMotion) {
      _pull.value = 0;
    } else {
      await _pull.reverse();
    }
    if (mounted) setState(() => _pulled = null);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final progress = ref.watch(bibleProgressProvider);
    if (progress.hasValue) _startIntro(progress.requireValue);
    final palette = BookcasePalette.current;

    return Scaffold(
      backgroundColor: _pageColor,
      body: Column(
        children: [
          _Header(color: palette.wallTop, scrolled: _scrolled),
          Expanded(
            child: progress.when(
              loading: () => const _Skeleton(),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(20),
                child: AppEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Leesvoortgang niet geladen',
                  description: 'Controleer je verbinding en probeer het opnieuw.',
                  action: SiteOutlineButton(
                    label: 'Opnieuw proberen',
                    expand: false,
                    onPressed: () => ref.invalidate(dashboardProvider),
                  ),
                ),
              ),
              data: _content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BibleProgress p) {
    final palette = BookcasePalette.current;
    final data = ref.watch(dashboardProvider).value;
    final next = ref.watch(nextChapterProvider);
    if (!identical(_layoutFor, p)) {
      _layout = BookcaseLayout.of(p);
      _layoutFor = p;
    }
    final layout = _layout!;
    final byName = {for (final b in p.books) b.name: b};
    final current = next == null ? null : byName[next.book];
    final table = readingTable(p, current: next?.book);
    final steps = ladderSteps(
      chaptersRead: p.chaptersRead,
      chaptersTotal: p.chaptersTotal,
      booksStarted: p.booksStarted,
      streak: data?.streak ?? 0,
    );
    final page = _pageColor;
    final allRead = next == null && p.chaptersRead >= p.chaptersTotal;
    final restart = NextChapter(book: BibleBooks.oldTestament.first, chapter: 1);

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        final scrolled = n.metrics.pixels > 2;
        if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
        return false;
      },
      child: DecoratedBox(
        // Overscroll at the top shows wall, at the bottom shows page.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.wallTop, palette.wallTop, page, page],
            stops: const [0, 0.5, 0.5, 1],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_intro, _celebrate, _pull]),
              builder: (context, _) => _Room(
                progress: p,
                layout: layout,
                palette: palette,
                intro: _intro.value,
                current: next?.book,
                fresh: _fresh,
                celebrate: _celebrate.value,
                pulled: _pulled,
                pull: _pull.value,
                onTapBook: (book) => _showBook(book, next),
              ),
            ),
            ColoredBox(
              color: page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (context, _) => allRead || current == null
                            ? const _AllReadCard()
                            : _RibbonCard(
                                book: current,
                                chapter: next!.chapter,
                                fresh: p.chaptersRead == 0,
                                intro: _intro.value,
                                palette: palette,
                                onTap: () => _showBook(current, next),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: SiteButton(
                      label: allRead || next == null
                          ? 'Begin opnieuw bij ${restart.reference}'
                          : 'Lees ${next.reference}',
                      height: 46,
                      onPressed: () => _openChapter(allRead || next == null ? restart : next),
                    ),
                  ),
                  _Section(
                    title: 'Op je leestafel',
                    lede: 'Boeken die je begonnen bent',
                    child: AnimatedBuilder(
                      animation: _intro,
                      builder: (context, _) => _ReadingTable(
                        books: table,
                        current: next?.book,
                        intro: _intro.value,
                        onTap: (book) => _showBook(book, next),
                      ),
                    ),
                  ),
                  if (steps.isNotEmpty)
                    _Section(
                      title: 'De ladder op',
                      lede: 'Elke sport is een stuk van de Bijbel',
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (context, _) => _LadderSteps(steps: steps, intro: _intro.value),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White below the room in light mode, as in the design; the dark canvas in
/// dark mode, so the raised cards still lift off it.
Color get _pageColor => AppTheme.isDark ? AppTheme.paper : AppTheme.paperRaised;

TextStyle _serif(double size, {Color? color, double letterSpacing = 0, double height = 1.15}) => TextStyle(
      fontFamily: AppTheme.serifFontName,
      fontVariations: const [FontVariation.weight(600)],
      fontWeight: FontWeight.w600,
      fontSize: size,
      letterSpacing: letterSpacing,
      height: height,
      color: color ?? AppTheme.ink,
    );

/// [text] with every number in it weighted and in full ink.
TextSpan _boldNumbers(String text, TextStyle base) {
  final spans = <TextSpan>[];
  text.splitMapJoin(
    RegExp(r'\d[\d.]*'),
    onMatch: (m) {
      spans.add(TextSpan(text: m[0], style: base.copyWith(fontWeight: FontWeight.w700, color: AppTheme.ink)));
      return '';
    },
    onNonMatch: (s) {
      if (s.isNotEmpty) spans.add(TextSpan(text: s));
      return '';
    },
  );
  return TextSpan(style: base, children: spans);
}

/// Back arrow and page title on the wall colour, so the room runs up to the
/// status bar. A hairline appears once the page scrolls under it.
class _Header extends StatelessWidget {
  const _Header({required this.color, required this.scrolled});

  final Color color;
  final bool scrolled;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: color,
        border: Border(
          bottom: BorderSide(color: scrolled ? AppTheme.rule : color.withValues(alpha: 0)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IconButton(
                  tooltip: 'Terug',
                  onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
                  icon: Icon(Icons.arrow_back, size: 22, color: AppTheme.ink),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Bijbelvoortgang',
                    style: AppTheme.displayTitle.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wall with the title, the two counts and the bookcase standing on the
/// floor.
class _Room extends StatelessWidget {
  const _Room({
    required this.progress,
    required this.layout,
    required this.palette,
    required this.intro,
    required this.current,
    required this.fresh,
    required this.celebrate,
    required this.pulled,
    required this.pull,
    required this.onTapBook,
  });

  final BibleProgress progress;
  final BookcaseLayout layout;
  final BookcasePalette palette;
  final double intro;
  final String? current;
  final List<String> fresh;
  final double celebrate;
  final String? pulled;
  final double pull;
  final void Function(BookProgress book) onTapBook;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final p = progress;
    final count = intro >= 1
        ? p.chaptersRead
        : (p.chaptersRead * Curves.easeOutCubic.transform(const Interval(0, 0.6).transform(intro))).round();
    final climbed = intro >= 1 ? p.percent : p.percent * BookcaseMotion.ladder(intro);
    final marker = climbed < 0.1 && climbed < p.percent ? '0%' : formatBiblePercent(climbed);
    final freshIn = Curves.easeOut.transform(const Interval(0.8, 1).transform(intro));

    return LayoutBuilder(
      builder: (context, constraints) {
        final caseWidth = math.min(constraints.maxWidth - 20, Bookcase.maxWidth);
        final s = caseWidth / BookcaseLayout.width;
        return CustomPaint(
          painter: BookcaseRoomPainter(palette: palette, floorHeight: 46 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text('Je boekenkast', style: _serif(27, letterSpacing: -0.4, height: 1.1)),
                          ),
                          const SizedBox(height: 5),
                          Text.rich(
                            _boldNumbers(
                              shelfSummary(p),
                              AppTheme.bodyMuted.copyWith(fontSize: 14, height: 1.3, color: AppTheme.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      excludeSemantics: true,
                      label: '${p.chaptersRead} van ${p.chaptersTotal} hoofdstukken gelezen, '
                          '${formatBiblePercent(p.percent)} van de Bijbel',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatShelfCount(count),
                            style: AppTheme.statNumber.copyWith(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              height: 1,
                              color: AppTheme.tealStrong,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'van ${formatShelfCount(p.chaptersTotal)} hoofdstukken',
                            style: AppTheme.caption.copyWith(color: AppTheme.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (fresh.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Opacity(
                      opacity: freshIn,
                      child: Transform.translate(
                        offset: Offset(0, 6 * (1 - freshIn)),
                        child: _FreshChip(names: fresh),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Center(
                child: SizedBox(
                  width: caseWidth,
                  child: Bookcase(
                    layout: layout,
                    fraction: p.chaptersRead / math.max(1, p.chaptersTotal),
                    markerLabel: marker,
                    intro: intro,
                    current: current,
                    celebrating: fresh.toSet(),
                    celebrate: celebrate,
                    pulled: pulled,
                    pull: pull,
                    onTapBook: onTapBook,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Nieuw uit: Exodus" on a brass plate, for books finished since last time.
class _FreshChip extends StatelessWidget {
  const _FreshChip({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final label = names.length > 3
        ? '${joinBookNames(names)} nieuw uit'
        : 'Nieuw uit: ${joinBookNames(names)}';
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB98A2E), Color(0xFFF5D98B), Color(0xFFC49533)],
            stops: [0, 0.45, 1],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Color(0x33A47C2C), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 5, 12, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF5B4314)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF5B4314),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Je leeslint ligt in Exodus 10": the book's cover with the ribbon, and a
/// strip with a cell per chapter. Tapping it opens the book's sheet.
class _RibbonCard extends StatelessWidget {
  const _RibbonCard({
    required this.book,
    required this.chapter,
    required this.fresh,
    required this.intro,
    required this.palette,
    required this.onTap,
  });

  final BookProgress book;
  final int chapter;

  /// No chapter read yet: the card invites a start instead.
  final bool fresh;
  final double intro;
  final BookcasePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final color = shelfColorFor(book.name);
    final kicker = fresh ? 'Hier begin je' : 'Je leeslint ligt in';
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$kicker ${book.name} $chapter. ${book.readCount} van ${book.chapters} hoofdstukken gelezen.',
      onTap: onTap,
      child: _RaisedCard(
        onTap: onTap,
        child: Row(
          children: [
            BookCover(
              title: book.name,
              color: color,
              width: 58,
              height: 80,
              titleSize: book.name.length > 9 ? 9 : 11,
              ruleTop: 30,
              ribbon: const Color(0xFFC2410C),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kicker, style: AppTheme.caption.copyWith(fontSize: 12.5)),
                  const SizedBox(height: 1),
                  Text(
                    '${book.name} $chapter',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.displaySmall.copyWith(letterSpacing: -0.3, height: 1.25),
                  ),
                  const SizedBox(height: 8),
                  _ChapterStrip(
                    book: book,
                    next: chapter,
                    color: color,
                    empty: palette.chapterEmpty,
                    nextColor: palette.chapterNext,
                    reveal: intro,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once every chapter is read: the whole case is gold.
class _AllReadCard extends StatelessWidget {
  const _AllReadCard();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return _RaisedCard(
      child: Row(
        children: [
          const BookCover(title: 'Bijbel', color: Color(0xFF134E4A), width: 58, height: 80, titleSize: 11, ruleTop: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Je boekenkast is vol', style: AppTheme.caption.copyWith(fontSize: 12.5)),
                const SizedBox(height: 1),
                Text(
                  'Je hebt de hele Bijbel gelezen',
                  style: AppTheme.displaySmall.copyWith(fontSize: 18, letterSpacing: -0.3, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The floating white card of the design: rounded 20, a long soft shadow.
class _RaisedCard extends StatelessWidget {
  const _RaisedCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final radius = BorderRadius.circular(20);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppTheme.isDark ? const Color(0x99000000) : const Color(0x590F172A),
            blurRadius: 30,
            offset: const Offset(0, 14),
            spreadRadius: -14,
          ),
        ],
      ),
      child: Material(
        color: AppTheme.paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: AppTheme.isDark ? AppTheme.rule : const Color(0x0A0F172A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null ? null : AppHaptics.tap(onTap),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A cell per chapter: read in the book's colour, the leeslint's chapter in
/// ribbon orange, the rest empty. Read cells fill in left to right during the
/// intro.
class _ChapterStrip extends StatelessWidget {
  const _ChapterStrip({
    required this.book,
    required this.next,
    required this.color,
    required this.empty,
    required this.nextColor,
    required this.reveal,
  });

  final BookProgress book;
  final int next;
  final Color color;
  final Color empty;
  final Color nextColor;
  final double reveal;

  static const _gap = 2.0;
  static const _cell = 8.0;

  @override
  Widget build(BuildContext context) {
    final cols = book.chapters > 100 ? 25 : 20;
    final rows = (book.chapters / cols).ceil();
    return SizedBox(
      height: rows * (_cell + _gap) - _gap,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChapterStripPainter(
          book: book,
          next: next,
          cols: cols,
          color: color,
          empty: empty,
          nextColor: nextColor,
          reveal: reveal,
        ),
      ),
    );
  }
}

class _ChapterStripPainter extends CustomPainter {
  _ChapterStripPainter({
    required this.book,
    required this.next,
    required this.cols,
    required this.color,
    required this.empty,
    required this.nextColor,
    required this.reveal,
  });

  final BookProgress book;
  final int next;
  final int cols;
  final Color color;
  final Color empty;
  final Color nextColor;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = _ChapterStrip._gap;
    const cell = _ChapterStrip._cell;
    final w = (size.width - gap * (cols - 1)) / cols;
    final n = book.chapters;
    final sweep = ((reveal - 0.3) / 0.55).clamp(0.0, 1.0) * (n + 2);
    for (var i = 0; i < n; i++) {
      final chapter = i + 1;
      final rect = Rect.fromLTWH((i % cols) * (w + gap), (i ~/ cols) * (cell + gap), w, cell);
      final t = (sweep - i).clamp(0.0, 1.0);
      final target = book.isRead(chapter) ? color : (chapter == next ? nextColor : empty);
      final fill = target == empty ? empty : Color.lerp(empty, target, t)!;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()..color = fill);
    }
  }

  @override
  bool shouldRepaint(_ChapterStripPainter old) =>
      old.reveal != reveal ||
      !identical(old.book, book) ||
      old.next != next ||
      old.color != color ||
      old.empty != empty ||
      old.nextColor != nextColor;
}

/// A titled block below the case: Lora heading, a muted line, content.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lede, required this.child});

  final String title;
  final String lede;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: _serif(20, letterSpacing: -0.2))),
          const SizedBox(height: 3),
          Text(lede, style: AppTheme.bodyMuted.copyWith(fontSize: 13.5, height: 1.35)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// "Op je leestafel": the books started but not finished, lying slightly
/// askew, each with its ribbon. Four fit across; more scroll sideways.
class _ReadingTable extends StatelessWidget {
  const _ReadingTable({
    required this.books,
    required this.current,
    required this.intro,
    required this.onTap,
  });

  final List<BookProgress> books;
  final String? current;
  final double intro;
  final void Function(BookProgress book) onTap;

  static const _tilts = [-3.0, 2.0, -1.5, 3.0];

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    if (books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.paperSunken,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Nog niets op tafel. Open een hoofdstuk in de lezer en het boek ligt hier klaar.',
          style: AppTheme.bodyMuted.copyWith(fontSize: 13.5),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final perRow = books.length > 4 ? 4.35 : 4.0;
        final itemWidth = (constraints.maxWidth - gap * 3) / perRow;
        final coverWidth = math.min(70.0, itemWidth - 6);
        final items = [
          for (var i = 0; i < books.length; i++)
            _TableBook(
              book: books[i],
              width: itemWidth,
              coverWidth: coverWidth,
              tilt: _tilts[i % _tilts.length],
              reveal: Curves.easeOutCubic.transform(
                ((intro - 0.35 - 0.07 * math.min(i, 6)) / 0.35).clamp(0.0, 1.0),
              ),
              onTap: () => onTap(books[i]),
            ),
        ];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          physics: books.length > 4 ? null : const NeverScrollableScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                items[i],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TableBook extends StatelessWidget {
  const _TableBook({
    required this.book,
    required this.width,
    required this.coverWidth,
    required this.tilt,
    required this.reveal,
    required this.onTap,
  });

  final BookProgress book;
  final double width;
  final double coverWidth;
  final double tilt;
  final double reveal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final share = book.readCount / math.max(1, book.chapters);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${book.name}, ${book.readCount} van ${book.chapters} hoofdstukken gelezen',
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: AppHaptics.tap(onTap),
        child: Opacity(
          opacity: reveal,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - reveal)),
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  Transform.rotate(
                    angle: tilt * math.pi / 180 * (0.4 + 0.6 * reveal),
                    child: BookCover(
                      title: book.name,
                      color: shelfColorFor(book.name),
                      width: coverWidth,
                      height: coverWidth * 90 / 70,
                      ribbon: ribbonRed,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    book.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyStrong.copyWith(fontSize: 13, height: 1.3),
                  ),
                  Text(
                    '${book.readCount} van ${book.chapters}',
                    style: AppTheme.caption.copyWith(
                      fontSize: 11.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 5),
                  ShelfBar(value: share, color: AppTheme.teal, height: 4, width: math.min(56, width - 8)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "De ladder op": the next rung on each track, with a brass bar.
class _LadderSteps extends StatelessWidget {
  const _LadderSteps({required this.steps, required this.intro});

  final List<LadderStep> steps;
  final double intro;

  // Lucide `flag`, `book-open` and `flame`, as the website draws them.
  static const _flag =
      '<path d="M4 22V4a1 1 0 0 1 .4-.8A6 6 0 0 1 8 2c3 0 5 2 7.333 2q2 0 3.067-.8A1 1 0 0 1 20 4v10a1 1 0 0 1-.4.8A6 6 0 0 1 16 16c-3 0-5-2-8-2a6 6 0 0 0-4 1.528"/>';
  static const _book = '<path d="M12 7v14"/>'
      '<path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/>';
  static const _flame =
      '<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>';

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final grow = Curves.easeOutCubic.transform(const Interval(0.5, 1).transform(intro.clamp(0.0, 1.0)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(AppTheme.rule)),
            _rung(steps[i], grow),
          ],
        ],
      ),
    );
  }

  Widget _rung(LadderStep step, double grow) {
    final (icon, bg, fg) = switch (step.track) {
      LadderTrack.bible => (
          _flag,
          AppTheme.isDark ? const Color(0xFF3A2E12) : const Color(0xFFFEF3C7),
          AppTheme.isDark ? const Color(0xFFE9C46A) : const Color(0xFFA47C2C),
        ),
      LadderTrack.books => (_book, AppTheme.tealSoft, AppTheme.isDark ? AppTheme.teal : AppTheme.tealStrong),
      LadderTrack.streak => (_flame, AppTheme.flameTint, AppTheme.isDark ? AppTheme.flame : AppTheme.vermilionStrong),
    };
    return Semantics(
      excludeSemantics: true,
      label: '${step.title}, ${step.subtitle}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: LucideIcon(icon, size: 19, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: AppTheme.bodyStrong.copyWith(fontSize: 14.5, height: 1.3)),
                  Text(step.subtitle, style: AppTheme.caption.copyWith(fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ShelfBar(value: step.fraction * grow, color: brass, height: 6, width: 64),
          ],
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + 3.5, size.width), 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: const [
        Skeleton(height: 54),
        SizedBox(height: 14),
        Skeleton(height: 420, radius: 10),
        SizedBox(height: 14),
        Skeleton(height: 112, radius: 20),
        SizedBox(height: 12),
        Skeleton(height: 46, radius: 12),
      ],
    );
  }
}
