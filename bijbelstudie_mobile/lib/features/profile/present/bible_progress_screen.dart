import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/bible_books.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/data/dashboard_models.dart';
import '../../dashboard/data/resume_link.dart';
import '../../dashboard/domain/bible_milestones.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../study/present/study_pane_controller.dart';
import '../domain/bible_progress.dart';
import 'bible_book_groups.dart';
import 'bible_milestone_bar.dart';

/// Every book with the reader's progress, derived from `/dashboard`.
final bibleProgressProvider = Provider.autoDispose<AsyncValue<BibleProgress>>((ref) {
  return ref
      .watch(dashboardProvider)
      .whenData((data) => BibleProgress.fromReadChapters(data.readChapters));
});

/// What the "Verder lezen" card offers. Null while `/dashboard` is still in
/// flight, and once every chapter of the Bible is read.
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

/// One chapter to open, the way the "Verder lezen" card and a book row hand it
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
/// Start and the Bijbelboeken tile on Profiel. Read-only: every number comes
/// from the `readChapters` map `/api/v1/dashboard` already returns. Inside the
/// tab shell, so the bottom bar stays put. Mirrors `/profiel/bijbel` on the
/// website.
class BibleProgressScreen extends ConsumerStatefulWidget {
  const BibleProgressScreen({super.key});

  @override
  ConsumerState<BibleProgressScreen> createState() => _BibleProgressScreenState();
}

class _BibleProgressScreenState extends ConsumerState<BibleProgressScreen>
    with SingleTickerProviderStateMixin {
  /// Short on purpose: the page is a reference, not a reward screen.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _introStarted = false;

  /// 0 = Alles, 1 = Oude T., 2 = Nieuwe T.
  int _filter = 0;

  /// Group labels currently expanded.
  final Set<String> _open = {};

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Runs once, as soon as the progress is first on screen - the page may paint
  /// its skeleton before `/dashboard` answers. Reduce-motion lands on the
  /// finished state without ever ticking.
  void _startIntro() {
    if (_introStarted) return;
    _introStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _intro.forward(from: 0);
    });
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

  /// A book row opens where the reader would want to carry on inside that book:
  /// its first unread chapter, or chapter 1 once it is finished.
  void _openBook(BookProgress book) {
    final next = (() {
      for (var n = 1; n <= book.chapters; n++) {
        if (!book.isRead(n)) return n;
      }
      return 1;
    })();
    _openChapter(NextChapter(book: book.name, chapter: next));
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final progress = ref.watch(bibleProgressProvider);
    if (progress.hasValue) _startIntro();

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
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
      ),
    );
  }

  Widget _content(BibleProgress p) {
    final byName = {for (final b in p.books) b.name: b};
    final groups = switch (_filter) {
      1 => BibleBookGroup.forTestament(newTestament: false),
      2 => BibleBookGroup.forTestament(newTestament: true),
      _ => BibleBookGroup.all,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AnimatedBuilder(
          animation: _intro,
          builder: (context, _) => _SummaryCard(progress: p, intro: _intro.value),
        ),
        const SizedBox(height: 12),
        _ResumeCard(onOpen: _openChapter),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: AppSegmentedControl(
            labels: const ['Alles', 'Oude T.', 'Nieuwe T.'],
            selectedIndex: _filter,
            onChanged: (index) => setState(() => _filter = index),
          ),
        ),
        const SizedBox(height: 14),
        const _Legend(),
        const SizedBox(height: 14),
        for (final group in groups) ...[
          AnimatedBuilder(
            animation: _intro,
            builder: (context, _) => _GroupCard(
              group: group,
              books: [
                for (final name in group.books)
                  byName[name] ??
                      BookProgress(
                        name: name,
                        isNewTestament: BibleBooks.newTestament.contains(name),
                        chapters: BibleBooks.chaptersIn(name),
                        readChapters: const [],
                      ),
              ],
              intro: _intro.value,
              expanded: _open.contains(group.label),
              onToggle: () => setState(() {
                if (!_open.remove(group.label)) _open.add(group.label);
              }),
              onOpenBook: _openBook,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// A whole number with the Dutch thousands separator: 1189 -> "1.189". Hand
/// rolled like `adminNumber` and `formatCount` elsewhere; the app does not
/// depend on `intl`.
String _count(int n) {
  final digits = (n < 0 ? 0 : n).toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The three colours a book can wear, here and in the squares on Start.
enum _Status {
  read('Gelezen'),
  busy('Bezig'),
  none('Nog niet');

  const _Status(this.label);

  final String label;

  static _Status of(BookProgress book) => book.completed
      ? _Status.read
      : book.started
      ? _Status.busy
      : _Status.none;

  Color get color => switch (this) {
    // The same trio the "Je Bijbel" book grid paints with.
    _Status.read => AppTheme.teal,
    _Status.busy => AppTheme.teal.withValues(alpha: 0.35),
    _Status.none => AppTheme.paperSunkenStrong,
  };
}

/// Canonical position of every book, 0-65. [BibleBooks.all] builds a fresh
/// list on every read, so the square wave looks the position up here instead of
/// scanning that list once per square per frame.
final Map<String, int> _canonIndex = () {
  final order = BibleBooks.all;
  return {for (var i = 0; i < order.length; i++) order[i]: i};
}();

/// How far along the reveal the square for the book at [index] of 66 is: one
/// short wave from Genesis to Openbaring.
double _squareReveal(double intro, int index) {
  const start = 0.10;
  const span = 0.45;
  const pop = 0.16;
  final at = start + span * index / (_canonIndex.length - 1);
  return ((intro - at) / pop).clamp(0.0, 1.0);
}

/// White bar with the back arrow and the page title, matching the one on
/// Bronnen and Alle studies.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              tooltip: 'Terug',
              onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
              icon: Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.inkSoft),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Bijbelvoortgang',
                style: AppTheme.displayTitle.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// The share read, the two counts, the milestone bar and what is left to the
/// next milestone.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.progress, required this.intro});

  final BibleProgress progress;
  final double intro;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final p = progress;
    final surface = Theme.of(context).colorScheme.surface;

    // The number counts up over the first stretch of the intro, then sits on
    // the real value - never a rounded-up share the reader has not reached.
    final counted =
        p.percent * Curves.easeOutCubic.transform(const Interval(0, 0.6).transform(intro));
    final shown = intro >= 1 ? p.percent : counted;
    final percentText =
        shown < 0.1 && shown < p.percent ? '0%' : formatBiblePercent(shown);
    final footer = bibleMilestoneFooter(p.chaptersRead, p.chaptersTotal);

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            percentText,
                            style: AppTheme.statNumber.copyWith(
                              fontSize: 40,
                              height: 1.05,
                              letterSpacing: -1,
                              color: AppTheme.teal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('van de Bijbel gelezen', style: AppTheme.caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _Count(
                            '${_count(p.chaptersRead)} / ${_count(p.chaptersTotal)}',
                            'hoofdstukken',
                          ),
                          const SizedBox(height: 6),
                          _Count(
                            '${_count(p.booksCompleted)} / ${_count(p.booksTotal)}',
                            'boeken',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                BibleMilestoneBar(fraction: p.percent / 100, intro: intro, cut: surface),
              ],
            ),
          ),
          Container(
            color: AppTheme.tealTint,
            padding: const EdgeInsets.fromLTRB(18, 11, 16, 11),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 16, color: AppTheme.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    footer,
                    maxLines: 2,
                    style: AppTheme.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "694 / 1.189 hoofdstukken" on one line, the number weighted.
class _Count extends StatelessWidget {
  const _Count(this.value, this.unit);

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: AppTheme.caption.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(text: ' $unit', style: AppTheme.caption.copyWith(fontSize: 13)),
        ],
      ),
      textAlign: TextAlign.right,
    );
  }
}

/// "Verder lezen" with the next chapter and a teal button that opens it.
class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.onOpen});

  final void Function(NextChapter target) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final next = ref.watch(nextChapterProvider);
    if (next == null) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verder lezen',
                  style: AppTheme.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  next.reference,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 17),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SiteButton(
            label: 'Lezen',
            expand: false,
            height: 40,
            onPressed: () => onOpen(next),
          ),
        ],
      ),
    );
  }
}

/// What the three colours mean. Without it the squares are decorative.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Row(
      children: [
        for (final status in _Status.values) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: status.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: AppTheme.caption.copyWith(fontSize: 12, color: AppTheme.inkMuted),
          ),
          if (status != _Status.values.last) const SizedBox(width: 16),
        ],
      ],
    );
  }
}

/// One canon group: its name, how many of its books are read, a square per
/// book, and - once tapped - the books themselves.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.books,
    required this.intro,
    required this.expanded,
    required this.onToggle,
    required this.onOpenBook,
  });

  final BibleBookGroup group;
  final List<BookProgress> books;
  final double intro;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(BookProgress book) onOpenBook;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final done = books.where((b) => b.completed).length;
    final finished = done == books.length && books.isNotEmpty;

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: '${group.label}, $done van ${books.length} boeken gelezen',
            excludeSemantics: true,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.label,
                            style: AppTheme.bodyStrong,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (finished)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.tealTint,
                              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                            ),
                            child: Text(
                              'Klaar',
                              style: AppTheme.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.teal,
                              ),
                            ),
                          )
                        else
                          Text(
                            '$done van ${books.length}',
                            style: AppTheme.caption.copyWith(
                              fontSize: 12.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(Icons.expand_more, color: AppTheme.inkFaint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final book in books)
                            _Square(
                              status: _Status.of(book),
                              reveal: _squareReveal(intro, _canonIndex[book.name] ?? 0),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            for (final book in books) ...[
              Divider(height: 1, color: Theme.of(context).colorScheme.outline),
              _BookRow(book: book, onTap: () => onOpenBook(book)),
            ],
        ],
      ),
    );
  }
}

/// One book as a small square in its status colour, popping into place during
/// the intro.
class _Square extends StatelessWidget {
  const _Square({required this.status, required this.reveal});

  final _Status status;
  final double reveal;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final empty = _Status.none.color;
    final t = Curves.easeOut.transform(reveal);
    // A finished square is the only one worth announcing; grey needs no reveal.
    final color = status == _Status.none ? empty : Color.lerp(empty, status.color, t)!;
    final scale = status == _Status.none ? 1.0 : 1 + 0.22 * math.sin(math.pi * reveal);

    return SizedBox(
      width: 11,
      height: 11,
      child: Center(
        child: Container(
          width: 11 * scale,
          height: 11 * scale,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3 * scale),
          ),
        ),
      ),
    );
  }
}

/// One book inside an expanded group: status dot, name, bar, chapters read.
class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.onTap});

  final BookProgress book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final status = _Status.of(book);

    return Semantics(
      button: true,
      label: '${book.name}, ${book.readCount} van ${book.chapters} hoofdstukken '
          'gelezen${book.completed ? ', voltooid' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Text(
                  book.name,
                  style: AppTheme.caption.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: SiteProgressBar(value: book.percent / 100, height: 4),
              ),
              const SizedBox(width: 10),
              Text(
                '${book.readCount}/${book.chapters}',
                style: AppTheme.caption.copyWith(
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: const [
        Skeleton(height: 168),
        SizedBox(height: 12),
        Skeleton(height: 72),
        SizedBox(height: 18),
        Skeleton(height: 34),
        SizedBox(height: 14),
        Skeleton(height: 320),
      ],
    );
  }
}
