import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/bible_books.dart';
import '../../../core/notifications/reminder_refresh.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart';
import '../../onboarding/present/tour_controller.dart';
import '../../studies/data/study_models.dart';
import '../../studies/data/study_plan_store.dart';
import '../../studies/present/studies_providers.dart';
import '../data/daily_verse_store.dart';
import '../data/dashboard_models.dart';
import 'daily_verse_card.dart';
import 'dashboard_providers.dart';

/// `/dashboard` on www.bijbel-studie.com, folded into one column.
///
/// The website lays this out as a wide main column plus a 280px sidebar; on a
/// phone the two stack in the order the site prioritises them — hero, stats,
/// book map, studies, then what the sidebar holds.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    // Fire-and-forget: tops the daily reminder up with fresh copy from the
    // server, once per session and only when the batch has gone stale. The
    // result is never rendered - see reminderCopyRefreshProvider.
    ref.watch(reminderCopyRefreshProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // The greeting header paints its own `scheme.surface` block full-bleed to
      // the very top of the screen (see `_DashboardBody`'s header `Container`,
      // which adds the status-bar inset itself), so only the loading / error
      // states — which have no header of their own — keep the top SafeArea.
      body: dashboard.when(
        loading: () => const DashboardSkeleton(),
        error: (error, _) => SafeArea(
          child: AppEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Dashboard niet geladen',
            description: '$error',
            action: SiteButton(
              label: 'Opnieuw proberen',
              expand: false,
              onPressed: () => ref.invalidate(dashboardProvider),
            ),
          ),
        ),
        data: (data) => SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            color: AppTheme.teal,
            onRefresh: () async => ref.invalidate(dashboardProvider),
            child: _DashboardBody(data: data),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data});

  final DashboardData data;

  void _openChapter(
    BuildContext context,
    WidgetRef ref, {
    required String book,
    required int chapter,
    String version = 'statenvertaling',
  }) {
    ref
        .read(readerLocationProvider.notifier)
        .openChapter(versionId: version, book: book, chapter: chapter);
    context.go('/study');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasArchivedVerse =
        ref.watch(dailyVerseStoreProvider).history.isNotEmpty;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Header: greeting, date, streak pill ──────────────────────────
        // Paints full-bleed under the status bar; the outer Scaffold has no
        // top SafeArea for this branch, so the status-bar inset is added here
        // instead of letting the scaffold background show through above it.
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20 + MediaQuery.of(context).padding.top,
            20,
            18,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greetingFor(data.name),
                      style: AppTheme.displaySmall.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(dutchLongDate(), style: AppTheme.bodyMuted),
                  ],
                ),
              ),
              if (data.streak > 0) ...[
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SiteBadge(
                    '${data.streak} ${data.streak == 1 ? 'dag' : 'dagen'}',
                    icon: Icons.local_fire_department,
                    foreground: AppTheme.flame,
                  ),
                ),
              ],
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TourAnchor(
                id: TourAnchorIds.dashboardHero,
                child: _HeroCard(
                  lastRead: data.lastRead,
                  onContinue: () {
                    final last = data.lastRead;
                    _openChapter(
                      context,
                      ref,
                      book: last?.book ?? 'Genesis',
                      chapter: last?.chapter ?? 1,
                      version: last?.version ?? 'statenvertaling',
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // The card renders today's verse, or — offline — the newest one
              // in its local archive. It is left out entirely only when there
              // is neither, which is why the archive is consulted here too.
              if (data.dailyVerse != null || hasArchivedVerse) ...[
                DailyVerseCard(
                  verse: data.dailyVerse,
                  onOpenChapter: (book, chapter) =>
                      _openChapter(context, ref, book: book, chapter: chapter),
                ),
                const SizedBox(height: 16),
              ],

              _BookMapCard(
                readChapters: data.readChapters,
                booksStarted: data.booksStarted,
                onOpenBook: (book) =>
                    _openChapter(context, ref, book: book, chapter: 1),
              ),
              const SizedBox(height: 16),

              _RecommendedStudiesCard(
                onOpen: (study) => _openChapter(
                  context,
                  ref,
                  book: study.startBook,
                  chapter: study.startChapter,
                  version: study.startVersion,
                ),
              ),
              const SizedBox(height: 16),

              _WeeklyStatsCard(days: data.weekDays, total: data.weekTotal),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact single-row card: cover icon, title + progress line, chevron.
/// Kept short on purpose — this is the first thing on the dashboard and the
/// site's tall hero block doesn't earn that much vertical space on a phone.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.lastRead, required this.onContinue});

  final LastRead? lastRead;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final hasProgress = lastRead != null;
    return BrandHeroCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onContinue,
      child: Row(
        children: [
          Icon(
            hasProgress ? Icons.menu_book_outlined : Icons.auto_stories,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasProgress
                      ? 'GA VERDER WAAR JE GEBLEVEN WAS'
                      : 'BEGIN MET LEZEN',
                  style: AppTheme.overline.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  hasProgress ? lastRead!.book : 'Start je bijbelstudie',
                  style: AppTheme.displayBase.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hasProgress
                      ? 'Hoofdstuk ${lastRead!.chapter} · ${lastRead!.version}'
                      : 'Lees dag voor dag door de Bijbel',
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ],
      ),
    );
  }
}

/// The 66-square contribution map. Tapping a square opens chapter 1 of that
/// book; the site does the same on click and shows the ratio on hover, which
/// here becomes a tap-to-select info line.
class _BookMapCard extends StatefulWidget {
  const _BookMapCard({
    required this.readChapters,
    required this.booksStarted,
    required this.onOpenBook,
  });

  final Map<String, List<int>> readChapters;
  final int booksStarted;
  final void Function(String book) onOpenBook;

  @override
  State<_BookMapCard> createState() => _BookMapCardState();
}

class _BookMapCardState extends State<_BookMapCard> {
  String? _selected;

  int _read(String book) => widget.readChapters[book]?.length ?? 0;

  double _ratio(String book) => _read(book) / BibleBooks.chaptersIn(book);

  /// `progressColor` in `app/dashboard/page.tsx`.
  Color _color(double ratio, ColorScheme scheme) {
    if (ratio == 0) return scheme.surfaceContainerHighest;
    if (ratio < 0.25) return AppTheme.teal.withValues(alpha: 0.22);
    if (ratio < 0.50) return AppTheme.teal.withValues(alpha: 0.45);
    if (ratio < 1.00) return AppTheme.teal.withValues(alpha: 0.72);
    return AppTheme.teal;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: Icons.menu_book_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bijbelboeken',
                      style: AppTheme.displayBase.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      '${widget.booksStarted} van 66 '
                      '${widget.booksStarted == 1 ? 'boek' : 'boeken'} geopend',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Legend: Minder ▢▢▢▢▢ Meer
          Row(
            children: [
              Text(
                'Minder',
                style: AppTheme.overline.copyWith(letterSpacing: 0),
              ),
              const SizedBox(width: 6),
              for (final ratio in const [0.0, 0.15, 0.37, 0.75, 1.0]) ...[
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: _color(ratio, scheme),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              Text('Meer', style: AppTheme.overline.copyWith(letterSpacing: 0)),
            ],
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 18,
            child: _selected == null
                ? Text('Tik op een boek voor details', style: AppTheme.caption)
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _selected,
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.teal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' - ${_read(_selected!)} van '
                              '${BibleBooks.chaptersIn(_selected!)} hoofdstukken gelezen',
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),

          _TestamentGrid(
            label: 'Oude Testament',
            books: BibleBooks.oldTestament,
            selected: _selected,
            colorFor: (book) => _color(_ratio(book), scheme),
            onTap: (book) =>
                setState(() => _selected = _selected == book ? null : book),
            onOpen: widget.onOpenBook,
          ),
          const SizedBox(height: 14),
          _TestamentGrid(
            label: 'Nieuwe Testament',
            books: BibleBooks.newTestament,
            selected: _selected,
            colorFor: (book) => _color(_ratio(book), scheme),
            onTap: (book) =>
                setState(() => _selected = _selected == book ? null : book),
            onOpen: widget.onOpenBook,
          ),
        ],
      ),
    );
  }
}

class _TestamentGrid extends StatelessWidget {
  const _TestamentGrid({
    required this.label,
    required this.books,
    required this.selected,
    required this.colorFor,
    required this.onTap,
    required this.onOpen,
  });

  final String label;
  final List<String> books;
  final String? selected;
  final Color Function(String book) colorFor;
  final void Function(String book) onTap;
  final void Function(String book) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${label.toUpperCase()}  (${books.length} boeken)',
          style: AppTheme.overline,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [
            for (final book in books)
              GestureDetector(
                onTap: () => onTap(book),
                onDoubleTap: () => onOpen(book),
                onLongPress: () => onOpen(book),
                child: Tooltip(
                  message: book,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorFor(book),
                      borderRadius: BorderRadius.circular(3),
                      border: selected == book
                          ? Border.all(color: AppTheme.teal, width: 2)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecommendedStudiesCard extends ConsumerWidget {
  const _RecommendedStudiesCard({required this.onOpen});

  final void Function(CuratedStudy study) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studies = ref.watch(curatedStudiesProvider);
    final plans = ref.watch(studyPlansProvider);
    final serverLessons =
        ref.watch(serverStudyLessonsProvider).value ??
        const <String, Set<int>>{};
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.lightbulb_outline,
            title: 'Aanbevolen studies',
            actionLabel: 'Bekijk alle',
            onAction: () => context.go('/studies'),
          ),
          const SizedBox(height: 12),
          studies.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SkeletonText(lines: 4, lineHeight: 12, gap: 14),
            ),
            error: (_, __) => Text(
              'Studies konden niet worden geladen.',
              style: AppTheme.caption,
            ),
            data: (list) => Column(
              children: [
                for (var i = 0; i < list.length && i < 5; i++) ...[
                  if (i > 0) const RuleLine(),
                  Opacity(
                    opacity:
                        isStudyFinished(
                          study: list[i],
                          plans: plans,
                          serverLessons: serverLessons,
                        )
                        ? 0.55
                        : 1,
                    child: InkWell(
                      onTap: () => onOpen(list[i]),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.teal.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                list[i].type.toUpperCase(),
                                style: AppTheme.overline.copyWith(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    list[i].title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.bodyStrong.copyWith(
                                      fontSize: 13,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${list[i].durationLabel} · ${list[i].startBook}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.caption.copyWith(
                                      fontSize: 11,
                                      color: AppTheme.inkFaint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward,
                              size: 13,
                              color: AppTheme.teal,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyStatsCard extends StatelessWidget {
  const _WeeklyStatsCard({required this.days, required this.total});

  final List<WeekDay> days;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final week = days.isEmpty
        ? const ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo']
              .map(
                (l) =>
                    WeekDay(label: l, count: 0, heightPct: 0, isToday: false),
              )
              .toList()
        : days;

    return AppCard(
      radius: AppTheme.radiusMd,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, size: 14, color: AppTheme.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Deze week',
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Text(
                total == 0 ? 'Geen activiteit' : '$total× gelezen',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < week.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: week[i].count > 0
                          ? (week[i].heightPct.clamp(20, 100)) / 100
                          : 0.30,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: week[i].count > 0
                              ? (week[i].isToday
                                    ? AppTheme.teal
                                    : AppTheme.teal.withValues(alpha: 0.4))
                              : (week[i].isToday
                                    ? AppTheme.teal.withValues(alpha: 0.25)
                                    : scheme.surfaceContainerHighest),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < week.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    week[i].label,
                    textAlign: TextAlign.center,
                    style: AppTheme.overline.copyWith(
                      letterSpacing: 0,
                      color: week[i].isToday
                          ? AppTheme.teal
                          : AppTheme.inkFaint,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

