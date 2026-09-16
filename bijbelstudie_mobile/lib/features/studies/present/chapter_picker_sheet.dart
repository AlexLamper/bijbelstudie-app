import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/bible_books.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../study/domain/chapter_study_models.dart';
import '../data/study_models.dart';
import 'studies_providers.dart';

/// Canonical Dutch book name -> chapters studied, from the completed lessons
/// the app already loads ([serverStudyLessonsProvider]) and the catalogue.
///
/// Only whole-book studies count: a lesson of a theme study on part of a
/// chapter is not that chapter studied. The lesson's own book and chapter are
/// used rather than its day, because an authored study need not number its
/// lessons by chapter.
Map<String, Set<int>> studiedChaptersByBook(
  List<CuratedStudy> studies,
  Map<String, Set<int>> completedLessons,
) {
  final out = <String, Set<int>>{};
  for (final study in studies) {
    if (study.type != 'Boek') continue;
    final days = completedLessons[study.id];
    if (days == null || days.isEmpty) continue;
    for (final lesson in study.lessons) {
      if (!days.contains(lesson.day)) continue;
      out.putIfAbsent(BibleBooks.toCanonical(lesson.book), () => <int>{}).add(lesson.chapter);
    }
  }
  return out;
}

/// "Kies een hoofdstuk": book, then chapter, then straight into the
/// single-chapter study. Marks what is already read (outlined) and studied
/// (filled), from data the app already has.
Future<void> showChapterPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppTheme.paperRaised,
    builder: (sheetContext) => const _ChapterPicker(),
  );
}

class _ChapterPicker extends ConsumerStatefulWidget {
  const _ChapterPicker();

  @override
  ConsumerState<_ChapterPicker> createState() => _ChapterPickerState();
}

class _ChapterPickerState extends ConsumerState<_ChapterPicker> {
  String? _book;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final read = ref.watch(dashboardProvider).value?.readChapters ?? const {};
    final studies = ref.watch(curatedStudiesProvider).value ?? const <CuratedStudy>[];
    final completed = ref.watch(serverStudyLessonsProvider).value ?? const <String, Set<int>>{};
    final studied = studiedChaptersByBook(studies, completed);
    final book = _book;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (book != null)
                  IconButton(
                    onPressed: () => setState(() => _book = null),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Alle boeken',
                  ),
                Expanded(
                  child: Text(book ?? 'Kies een hoofdstuk', style: AppTheme.displayTitle),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              book == null
                  ? 'Kies eerst een bijbelboek.'
                  : 'Bestudeer één hoofdstuk, zonder een hele studie te starten.',
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: book == null
                  ? _BookList(
                      studied: studied,
                      onPick: (name) => setState(() => _book = name),
                    )
                  : _ChapterGrid(
                      book: book,
                      read: (read[book] ?? const <int>[]).toSet(),
                      studied: studied[book] ?? const <int>{},
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookList extends StatelessWidget {
  const _BookList({required this.studied, required this.onPick});

  final Map<String, Set<int>> studied;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    Widget section(String label, List<String> books) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 6),
        for (final name in books)
          RuleListTile(
            onTap: () => onPick(name),
            child: Row(
              children: [
                Expanded(child: Text(name, style: AppTheme.bodyStrong)),
                Text(
                  (studied[name]?.isNotEmpty ?? false)
                      ? '${studied[name]!.length}/${BibleBooks.chaptersIn(name)}'
                      : '${BibleBooks.chaptersIn(name)}',
                  style: AppTheme.caption,
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.inkFaint),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );

    return ListView(
      children: [
        section('Oude Testament', BibleBooks.oldTestament),
        section('Nieuwe Testament', BibleBooks.newTestament),
      ],
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({required this.book, required this.read, required this.studied});

  final String book;
  final Set<int> read;
  final Set<int> studied;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final count = BibleBooks.chaptersIn(book);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 56,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: count,
            itemBuilder: (context, index) {
              final chapter = index + 1;
              final isStudied = studied.contains(chapter);
              final isRead = read.contains(chapter);
              final state = isStudied ? ', bestudeerd' : isRead ? ', gelezen' : '';
              return Semantics(
                button: true,
                label: '$book $chapter$state',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(chapterStudyRoute(book, chapter));
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isStudied ? AppTheme.teal : Colors.transparent,
                      border: Border.all(
                        color: isStudied || isRead ? AppTheme.teal : AppTheme.rule,
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: isStudied
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(
                            '$chapter',
                            style: AppTheme.bodyStrong.copyWith(
                              color: isRead ? AppTheme.tealStrong : AppTheme.ink,
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Legend(filled: false, label: 'Gelezen'),
            const SizedBox(width: 16),
            _Legend(filled: true, label: 'Bestudeerd'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.filled, required this.label});

  final bool filled;
  final String label;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: filled ? AppTheme.teal : Colors.transparent,
            border: Border.all(color: AppTheme.teal),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTheme.caption),
      ],
    );
  }
}
