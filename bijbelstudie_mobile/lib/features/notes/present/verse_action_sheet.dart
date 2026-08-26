import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../data/notes_repository.dart';
import '../domain/note_models.dart';
import 'notes_providers.dart';

/// Long-press on a verse: highlight, note, bookmark, share, copy.
Future<void> showVerseActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterContent chapter,
  required Verse verse,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (sheetContext) => _VerseActionSheet(chapter: chapter, verse: verse),
  );
}

/// Prompts for note text, then saves it through [NotesRepository] and
/// invalidates [notesListProvider] so any open list picks it up without a
/// manual refresh.
///
/// The one note editor in the app: [_VerseActionSheet] calls this for a
/// single verse, and the empty state of the Notities tab in
/// `study_screen.dart` calls it for the chapter as a whole, with [verse] left
/// `null`.
Future<void> showAddNoteDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String book,
  required int chapter,
  int? verse,
  String verseText = '',
  required String translation,
}) async {
  final controller = TextEditingController();
  final reference = verse == null ? '$book $chapter' : '$book $chapter:$verse';
  final text = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(reference),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 5,
        decoration: const InputDecoration(hintText: 'Jouw notitie'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );

  if (text == null || text.isEmpty) return;

  await ref.read(notesRepositoryProvider).saveNote(
        StudyNote(
          id: newClientId(),
          book: book,
          chapter: chapter,
          verse: verse,
          verseText: verseText,
          noteText: text,
          translation: translation,
          isHighlight: false,
          updatedAt: DateTime.now(),
        ),
      );
  ref.invalidate(notesListProvider);
  await HapticFeedback.lightImpact();
}

class _VerseActionSheet extends ConsumerWidget {
  const _VerseActionSheet({required this.chapter, required this.verse});

  final ChapterContent chapter;
  final Verse verse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = '${chapter.book} ${chapter.chapter}:${verse.number}';
    final highlights = ref.watch(highlightIndexProvider);
    final existing = highlights[VerseKey(chapter.book, chapter.chapter, verse.number)];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(reference),
            const SizedBox(height: 12),
            Text(
              verse.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyMuted,
            ),
            const SizedBox(height: 20),
            _ColorRow(
              selected: existing,
              onSelected: (color) => _toggleHighlight(context, ref, color, existing),
            ),
            const SizedBox(height: 20),
            RuleGrid(
              children: [
                RuleListTile(
                  onTap: () => _addNote(context, ref),
                  child: const _ActionRow(icon: Icons.edit_note, label: 'Notitie toevoegen'),
                ),
                RuleListTile(
                  onTap: () => _addBookmark(context, ref),
                  child: const _ActionRow(
                    icon: Icons.bookmark_add_outlined,
                    label: 'Bladwijzer plaatsen',
                  ),
                ),
                RuleListTile(
                  onTap: () => _share(context),
                  child: const _ActionRow(icon: Icons.ios_share, label: 'Delen'),
                ),
                RuleListTile(
                  showRule: false,
                  onTap: () => _copy(context, reference),
                  child: const _ActionRow(icon: Icons.copy_all_outlined, label: 'Kopiëren'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleHighlight(
    BuildContext context,
    WidgetRef ref,
    HighlightColor color,
    HighlightColor? existing,
  ) async {
    await HapticFeedback.lightImpact();
    final repo = ref.read(notesRepositoryProvider);

    if (existing == color) {
      // Tapping the active colour clears the highlight.
      final all = ref.read(highlightsListProvider).value ?? const <StudyNote>[];
      final match = all.where(
        (h) =>
            h.book == chapter.book &&
            h.chapter == chapter.chapter &&
            h.verse == verse.number,
      );
      if (match.isNotEmpty) await repo.deleteNote(match.first);
    } else {
      await repo.saveNote(
        StudyNote(
          id: newClientId(),
          book: chapter.book,
          chapter: chapter.chapter,
          verse: verse.number,
          verseText: verse.text,
          noteText: '',
          translation: chapter.sourceId,
          color: color,
          isHighlight: true,
          updatedAt: DateTime.now(),
        ),
      );
    }

    ref.invalidate(highlightsListProvider);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    Navigator.of(context).pop();
    await showAddNoteDialog(
      context: context,
      ref: ref,
      book: chapter.book,
      chapter: chapter.chapter,
      verse: verse.number,
      verseText: verse.text,
      translation: chapter.sourceId,
    );
  }

  Future<void> _addBookmark(BuildContext context, WidgetRef ref) async {
    final location = ref.read(readerLocationProvider);
    await ref.read(notesRepositoryProvider).saveBookmark(
          Bookmark(
            id: newClientId(),
            book: chapter.book,
            chapter: chapter.chapter,
            verse: verse.number,
            version: location.versionId,
            label: verse.text.length > 60 ? '${verse.text.substring(0, 57)}…' : verse.text,
            updatedAt: DateTime.now(),
          ),
        );
    ref.invalidate(bookmarksProvider);
    await HapticFeedback.lightImpact();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _share(BuildContext context) async {
    Navigator.of(context).pop();
    await Share.share(
      chapter.shareText(onlyVerses: [verse.number]),
      subject: '${chapter.book} ${chapter.chapter}:${verse.number}',
    );
  }

  Future<void> _copy(BuildContext context, String reference) async {
    await Clipboard.setData(
      ClipboardData(text: '${verse.text}\n\n$reference - ${chapter.attribution}'),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gekopieerd')),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onSelected});

  final HighlightColor? selected;
  final ValueChanged<HighlightColor> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final color in HighlightColor.values)
          Semantics(
            label: 'Markeer ${color.label}',
            selected: selected == color,
            button: true,
            child: InkWell(
              onTap: () => onSelected(color),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Container(
                width: 42,
                height: 34,
                decoration: BoxDecoration(
                  color: color.swatch,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: selected == color ? AppTheme.teal : AppTheme.rule,
                    width: selected == color ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.inkSoft),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
