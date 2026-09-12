import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../notes/domain/note_models.dart';
import '../../notes/present/notes_providers.dart';
import 'read_screen.dart' show pendingVerseAnchorProvider;

/// Opened by [showChapterMarksSheet] from the "N notities · N markeringen"
/// line in the reader header (`_ChapterMarks` in `read_screen.dart`), which
/// used to just sit there. Lists this chapter's notes and highlights in verse
/// order; tapping one dismisses the sheet and scrolls the reader to it.
Future<void> showChapterMarksSheet(
  BuildContext context,
  WidgetRef ref, {
  required String book,
  required int chapter,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (_) => _ChapterMarksSheet(book: book, chapter: chapter),
  );
}

class _ChapterMarksSheet extends ConsumerWidget {
  const _ChapterMarksSheet({required this.book, required this.chapter});

  final String book;
  final int chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final notes = ref.watch(notesListProvider).value ?? const <StudyNote>[];
    final highlights = ref.watch(highlightsListProvider).value ?? const <StudyNote>[];

    bool here(StudyNote n) => n.book == book && n.chapter == chapter;
    // Chapter-level entries (no verse) have nowhere to sort inside verse
    // order, so they fall to the end rather than jumbling in at the top.
    final entries = [...notes.where(here), ...highlights.where(here)]
      ..sort((a, b) {
        if (a.verse == null && b.verse == null) return 0;
        if (a.verse == null) return 1;
        if (b.verse == null) return -1;
        return a.verse!.compareTo(b.verse!);
      });

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Notities & markeringen'),
                  const SizedBox(height: 3),
                  Text(
                    '$book $chapter',
                    style: AppTheme.displayTitle.copyWith(
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const RuleLine(),
            Flexible(
              child: entries.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.edit_note_outlined,
                      title: 'Niets meer om te tonen',
                      description:
                          'De notities en markeringen van dit hoofdstuk zijn verwijderd.',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, index) => _MarkRow(
                        note: entries[index],
                        onJump: (verse) {
                          ref.read(pendingVerseAnchorProvider.notifier).set(verse);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One note or highlight. Only tappable when it has a verse to jump to -
/// a chapter-level note has nowhere to scroll the reader.
class _MarkRow extends StatelessWidget {
  const _MarkRow({required this.note, required this.onJump});

  final StudyNote note;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final verse = note.verse;
    final bodyText = (note.isHighlight ? note.verseText : note.noteText).trim();

    return Semantics(
      button: verse != null,
      label: verse != null
          ? 'Ga naar ${note.reference}'
          : note.reference,
      child: RuleListTile(
        onTap: verse == null ? null : () => onJump(verse),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: note.isHighlight
                  ? Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        color: note.color.swatch,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: AppTheme.rule),
                      ),
                    )
                  : Icon(Icons.edit_note_outlined, size: 16, color: AppTheme.teal),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.reference, style: AppTheme.bodyStrong),
                  if (bodyText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bodyText,
                      style: AppTheme.bodyMuted,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (verse != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right, size: 16, color: AppTheme.inkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
