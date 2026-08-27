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

/// What the sheet was dismissed with. Only the note needs one: everything else
/// the sheet offers is done before it closes.
enum _VerseSheetResult { note }

/// Long-press on a verse: highlight, note, bookmark, share, copy.
///
/// The note editor is opened by *this* function, after the sheet has closed,
/// rather than by the sheet itself. The sheet used to pop and then immediately
/// `showDialog` with its own context and `ref`; by the time the reader tapped
/// "Opslaan", seconds later, the sheet's element was long unmounted and
/// `ref.read` threw `StateError: Using "ref" when a widget is about to or has
/// been unmounted is unsafe`. Only [SyncRejectedException] was caught, so the
/// note vanished with no error and no request - which is why notes never
/// arrived while highlights and bookmarks, saved before the pop, always did.
/// [context] and [ref] here belong to the reader, which stays mounted.
Future<void> showVerseActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterContent chapter,
  required Verse verse,
}) async {
  final result = await showModalBottomSheet<_VerseSheetResult>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (sheetContext) => _VerseActionSheet(chapter: chapter, verse: verse),
  );

  if (result != _VerseSheetResult.note || !context.mounted) return;
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

/// Prompts for note text, then saves it through [NotesRepository] and
/// invalidates [notesListProvider] so any open list picks it up without a
/// manual refresh.
///
/// The one note editor in the app: [showVerseActionSheet] calls this for a
/// single verse, and the empty state of the Notities tab in
/// `study_screen.dart` calls it for the chapter as a whole, with [verse] left
/// `null`.
///
/// Everything the save needs - the repository, the container to invalidate
/// through, the messenger to complain to - is captured *before* the dialog is
/// awaited. A note editor is open for as long as it takes to write a note, and
/// nothing guarantees the widget that opened it is still mounted by then;
/// reaching back through `ref` or `context` afterwards is what silently ate
/// every note this dialog ever produced.
Future<void> showAddNoteDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String book,
  required int chapter,
  int? verse,
  String verseText = '',
  required String translation,
}) async {
  final repository = ref.read(notesRepositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final reference = verse == null ? '$book $chapter' : '$book $chapter:$verse';
  final text = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _NoteEditorDialog(reference: reference),
  );

  if (text == null || text.isEmpty) return;

  try {
    await repository.saveNote(
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
    container.invalidate(notesListProvider);
    await HapticFeedback.lightImpact();
  } on SyncRejectedException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    // Anything else - a malformed response, a plugin blowing up - is still a
    // note the reader believes they saved. Say so rather than letting it
    // disappear into an unhandled async error, which is exactly how this bug
    // stayed invisible.
    messenger?.showSnackBar(
      const SnackBar(content: Text('Notitie kon niet worden opgeslagen. Probeer het opnieuw.')),
    );
  }
}

/// The note editor's text field.
///
/// A widget rather than a bare [TextEditingController] held by
/// [showAddNoteDialog], because the controller has to outlive the dialog's
/// exit animation: the field is still being rebuilt while the route animates
/// away, and disposing the controller the moment `showDialog` returns throws
/// "A TextEditingController was used after being disposed". Owning it here
/// ties its lifetime to the field that uses it, which is the only place that
/// knows when that is over.
class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({required this.reference});

  final String reference;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.reference),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width * 0.85).clamp(0, 420),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Jouw notitie'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Opslaan'),
        ),
      ],
    );
  }
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
                  onTap: () => _addNote(context),
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

    try {
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
    } on SyncRejectedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    if (context.mounted) Navigator.of(context).pop();
  }

  /// Hands the note back to [showVerseActionSheet] instead of opening the
  /// editor here — see the note on that function for why.
  void _addNote(BuildContext context) {
    Navigator.of(context).pop(_VerseSheetResult.note);
  }

  Future<void> _addBookmark(BuildContext context, WidgetRef ref) async {
    final location = ref.read(readerLocationProvider);
    try {
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
    } on SyncRejectedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
