import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../study/present/study_pane_controller.dart';
import '../domain/bible_progress.dart';

/// Every book with the reader's progress, derived from `/dashboard`.
final bibleProgressProvider = Provider.autoDispose<AsyncValue<BibleProgress>>((ref) {
  return ref
      .watch(dashboardProvider)
      .whenData((data) => BibleProgress.fromReadChapters(data.readChapters));
});

/// "Bijbel gelezen" at `/profile/bijbel`, reached from the Bijbelboeken tile on
/// Profiel and the Bijbelboeken card on Start. Read-only: the numbers come from
/// the `readChapters` map `/api/v1/dashboard` already returns. Mirrors
/// `/profiel/bijbel` on the website.
class BibleProgressScreen extends ConsumerStatefulWidget {
  const BibleProgressScreen({super.key});

  @override
  ConsumerState<BibleProgressScreen> createState() => _BibleProgressScreenState();
}

class _BibleProgressScreenState extends ConsumerState<BibleProgressScreen> {
  BookFilter _filter = BookFilter.all;
  final Set<String> _open = {};

  void _openChapter(String book, int chapter) {
    // Same hand-off as the dashboard's book map: pin the reader, show the
    // reader half of the split screen, go.
    ref
        .read(readerLocationProvider.notifier)
        .openChapter(versionId: 'statenvertaling', book: book, chapter: chapter);
    ref.read(studyPaneProvider.notifier).showReader();
    context.go('/study');
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(bibleProgressProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Bijbel gelezen')),
      body: progress.when(
        loading: () => const _Skeleton(),
        error: (_, __) => AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: 'Leesvoortgang niet geladen',
          description: 'Controleer je verbinding en probeer het opnieuw.',
          action: SiteOutlineButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: () => ref.invalidate(dashboardProvider),
          ),
        ),
        data: _content,
      ),
    );
  }

  Widget _content(BibleProgress p) {
    AppTheme.dependOn(context);
    final counts = {for (final f in BookFilter.values) f: p.filtered(p.books, f).length};

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Hoofdstukken',
                value: '${p.chaptersRead}/${p.chaptersTotal}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                label: 'Boeken voltooid',
                value: '${p.booksCompleted}/${p.booksTotal}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(label: 'Van de Bijbel', value: _formatPercent(p.percent)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SiteProgressBar(value: p.percent / 100),
        if (p.chaptersRead == 0) ...[
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Je hebt nog geen hoofdstukken gelezen. Open een hoofdstuk in de '
              'lezer en het verschijnt hier.',
              style: AppTheme.bodyMuted,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in BookFilter.values)
              ChoiceChip(
                label: Text('${f.label} ${counts[f]}'),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 24),
        ..._testament('Oude Testament', p.oldTestament, p),
        const SizedBox(height: 24),
        ..._testament('Nieuwe Testament', p.newTestament, p),
      ],
    );
  }

  List<Widget> _testament(String title, List<BookProgress> all, BibleProgress p) {
    final books = p.filtered(all, _filter);
    final read = all.fold<int>(0, (s, b) => s + b.readCount);
    final total = all.fold<int>(0, (s, b) => s + b.chapters);
    final done = all.where((b) => b.completed).length;

    return [
      SectionHeader(
        title: title,
        description: '$read/$total hoofdstukken · $done/${all.length} boeken voltooid',
      ),
      const SizedBox(height: 10),
      if (books.isEmpty)
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Text('Geen boeken in deze selectie.', style: AppTheme.bodyMuted),
        )
      else
        AppCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            children: [
              for (var i = 0; i < books.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                _BookTile(
                  book: books[i],
                  expanded: _open.contains(books[i].name),
                  onToggle: () => setState(() {
                    if (!_open.remove(books[i].name)) _open.add(books[i].name);
                  }),
                  onOpenChapter: (n) => _openChapter(books[i].name, n),
                ),
              ],
            ],
          ),
        ),
    ];
  }
}

String _formatPercent(double pct) {
  if (pct > 0 && pct < 0.1) return '<0,1%';
  final text = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')}%';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppTheme.statNumber.copyWith(
                fontSize: 17,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.caption.copyWith(fontSize: 11),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.expanded,
    required this.onToggle,
    required this.onOpenChapter,
  });

  final BookProgress book;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(int chapter) onOpenChapter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: '${book.name}, ${book.readCount} van ${book.chapters} '
              'hoofdstukken gelezen${book.completed ? ', voltooid' : ''}',
          excludeSemantics: true,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                book.name,
                                style: AppTheme.bodyStrong,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (book.completed) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.tealTint,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                                ),
                                child: Text(
                                  'Voltooid',
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.teal,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: SiteProgressBar(value: book.percent / 100, height: 4)),
                            const SizedBox(width: 10),
                            Text(
                              '${book.readCount}/${book.chapters} · ${book.percent}%',
                              style: AppTheme.caption.copyWith(
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.expand_more, color: AppTheme.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var n = 1; n <= book.chapters; n++)
                  _ChapterCell(
                    number: n,
                    read: book.isRead(n),
                    bookName: book.name,
                    onTap: () => onOpenChapter(n),
                    outline: scheme.outline,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChapterCell extends StatelessWidget {
  const _ChapterCell({
    required this.number,
    required this.read,
    required this.bookName,
    required this.onTap,
    required this.outline,
  });

  final int number;
  final bool read;
  final String bookName;
  final VoidCallback onTap;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$bookName $number, ${read ? 'gelezen' : 'nog niet gelezen'}',
      excludeSemantics: true,
      child: Material(
        // `tealFill` is the same strong teal in both themes, so white numbers
        // keep their contrast in dark mode.
        color: read ? AppTheme.tealFill : scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Container(
            width: 42,
            height: 40,
            alignment: Alignment.center,
            decoration: read
                ? null
                : BoxDecoration(
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
            child: Text(
              '$number',
              style: AppTheme.caption.copyWith(
                fontSize: 13,
                fontWeight: read ? FontWeight.w700 : FontWeight.w500,
                color: read ? Colors.white : AppTheme.inkMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: const [
        Skeleton(height: 64),
        SizedBox(height: 16),
        Skeleton(height: 32),
        SizedBox(height: 24),
        Skeleton(height: 420),
      ],
    );
  }
}
