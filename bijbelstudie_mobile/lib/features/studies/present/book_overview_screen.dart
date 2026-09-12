import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/bible_books.dart';
import '../../../core/theme/app_theme.dart';
import 'studies_providers.dart';

/// Every bible book at once, in six canon groups.
///
/// Studies · Ontdek can only ever show a handful of rows before the page turns
/// into the flat seventy-seven-deep list the redesign was about. This is the
/// exhaustive view instead: 66 tiles, about two swipes end to end, with the
/// group headings acting as landmarks so scrolling never loses the reader.
///
/// The tile colour is the only new information here, and it is derived rather
/// than stored - see [bookProgressProvider].
class BookOverviewScreen extends ConsumerWidget {
  const BookOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final progress = ref.watch(bookProgressProvider);
    final started = progress.values
        .where((status) => status != BookProgress.none)
        .length;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AppBar(started: started),
            const _Legend(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  for (final group in CanonGroup.all)
                    _Group(group: group, progress: progress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar({required this.started});

  final int started;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Terug',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.pop(),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Alle studies',
                    style: AppTheme.displayTitle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${BibleBooks.all.length} boeken · $started begonnen',
                  style: AppTheme.caption.copyWith(
                    fontSize: 11.5,
                    color: AppTheme.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Semantics(
            button: true,
            label: 'Zoeken',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/search'),
              child: Icon(Icons.search, size: 19, color: AppTheme.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the three tile colours mean. Without it the grid is decorative.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    Widget entry(Color color, String label, {bool outlined = false}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: outlined ? Border.all(color: AppTheme.rule) : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.inkMuted,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          entry(AppTheme.teal, 'afgerond'),
          const SizedBox(width: 14),
          entry(AppTheme.tealSoft, 'bezig'),
          const SizedBox(width: 14),
          entry(AppTheme.paperSunken, 'nog niet', outlined: true),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.group, required this.progress});

  final CanonGroup group;
  final Map<String, BookProgress> progress;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Row(
            children: [
              Text(group.label.toUpperCase(), style: AppTheme.groupLabel),
              const SizedBox(width: 9),
              Text(
                '${group.books.length} boeken',
                style: AppTheme.caption.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.inkFaint,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(child: Container(height: 1, color: AppTheme.rule)),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: group.books.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            mainAxisExtent: 48,
          ),
          itemBuilder: (context, index) {
            final book = group.books[index];
            return _BookTile(
              book: book,
              status: progress[book] ?? BookProgress.none,
            );
          },
        ),
      ],
    );
  }
}

class _BookTile extends ConsumerWidget {
  const _BookTile({required this.book, required this.status});

  final String book;
  final BookProgress status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final study = ref.watch(studyForBookProvider(book));

    final (background, foreground, weight) = switch (status) {
      BookProgress.done => (AppTheme.teal, Colors.white, FontWeight.w700),
      BookProgress.started => (
        AppTheme.tealSoft,
        AppTheme.tealStrong,
        FontWeight.w700,
      ),
      BookProgress.none => (
        AppTheme.paperSunken,
        AppTheme.inkSoft,
        FontWeight.w600,
      ),
    };

    return Semantics(
      button: study != null,
      label: '$book, ${_statusLabel(status)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A book the catalogue has no study for is inert rather than a tap
        // that goes nowhere - the same choice the locked lessons make.
        onTap: study == null ? null : () => context.push('/studies/${study.id}'),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: status == BookProgress.none
                ? Border.all(color: AppTheme.rule)
                : null,
          ),
          child: Text(
            book,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.sansFontName,
              fontSize: 12,
              height: 1.2,
              fontWeight: weight,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }

  static String _statusLabel(BookProgress status) => switch (status) {
    BookProgress.done => 'afgerond',
    BookProgress.started => 'bezig',
    BookProgress.none => 'nog niet begonnen',
  };
}
