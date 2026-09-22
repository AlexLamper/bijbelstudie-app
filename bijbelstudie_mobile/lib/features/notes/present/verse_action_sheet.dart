import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../commentary/present/commentary_jump.dart';
import '../../crossrefs/present/crossref_providers.dart';
import '../../crossrefs/present/crossref_sheet.dart';
import '../../study/present/study_pane_controller.dart';
import '../data/notes_repository.dart';
import '../domain/note_models.dart';
import 'notes_providers.dart';

/// What the sheet was dismissed with. Only the note needs one: everything else
/// the sheet offers is done before it closes.
enum _VerseSheetResult { note, commentary, crossRefs }

/// Long-press on a verse: highlight, commentary, note, bookmark, share, copy.
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

  /// Called after "Commentaar bij vers N" has pointed the study page at this
  /// verse, for a caller that is not already inside `/studie` and has to
  /// navigate there. Null inside `/studie`, where flipping the pane is enough.
  VoidCallback? onOpenCommentary,
}) async {
  final result = await showModalBottomSheet<_VerseSheetResult>(
    context: context,
    // Six rows under a four-line verse are taller than the default 9/16 cap
    // on a small phone; the sheet sizes to its content and scrolls instead.
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (sheetContext) =>
        _VerseActionSheet(chapter: chapter, verse: verse),
  );

  if (result == _VerseSheetResult.commentary) {
    if (context.mounted) onOpenCommentary?.call();
    return;
  }
  if (result == _VerseSheetResult.crossRefs) {
    // Opened from the reader's context, not the sheet's, for the same reason
    // the note editor is: following a reference navigates and shows a
    // snackbar seconds later, by which time this sheet is long gone.
    if (context.mounted) {
      await showCrossRefSheet(
        context: context,
        ref: ref,
        chapter: chapter,
        verse: verse,
      );
    }
    return;
  }
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
  final text = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (sheetContext) =>
        _NoteEditorSheet(reference: reference, verseText: verseText),
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
      const SnackBar(
        content: Text(
          'Notitie kon niet worden opgeslagen. Probeer het opnieuw.',
        ),
      ),
    );
  }
}

/// The note editor's text field and the sheet chrome around it.
///
/// A widget rather than a bare [TextEditingController] held by
/// [showAddNoteDialog], because the controller has to outlive the sheet's
/// exit animation: the field is still being rebuilt while the route animates
/// away, and disposing the controller the moment `showModalBottomSheet`
/// returns throws "A TextEditingController was used after being disposed".
/// Owning it here ties its lifetime to the field that uses it, which is the
/// only place that knows when that is over.
class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({required this.reference, required this.verseText});

  final String reference;
  final String verseText;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    // The keyboard covers the sheet unless its own inset is padded in here;
    // the bottom safe-area (home indicator) is separate from that and still
    // needs SafeArea once the keyboard padding above it is accounted for.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        // Two boxes, not one scroll view: on a short viewport - a small phone
        // with the keyboard up - a single scrolling column put "Opslaan" below
        // the fold, where a tap landed on the barrier and silently threw the
        // note away. The actions are pinned; only the verse and the field
        // scroll.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.rule,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      widget.reference,
                      style: AppTheme.pillLabel.copyWith(color: AppTheme.teal),
                    ),
                    if (widget.verseText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.verseText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.verseFragment,
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      minLines: 5,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Schrijf hier je notitie…',
                        filled: true,
                        fillColor: AppTheme.paperSunken,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annuleren'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) => SiteButton(
                        label: 'Opslaan',
                        onPressed: value.text.trim().isEmpty ? null : _save,
                      ),
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

class _VerseActionSheet extends ConsumerWidget {
  const _VerseActionSheet({required this.chapter, required this.verse});

  final ChapterContent chapter;
  final Verse verse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = '${chapter.book} ${chapter.chapter}:${verse.number}';
    final highlights = ref.watch(highlightIndexProvider);
    final existing =
        highlights[VerseKey(chapter.book, chapter.chapter, verse.number)];
    // The count is a courtesy, not a gate. It reads the cache only, so a
    // long-press costs no request: the row opens either way and simply says
    // nothing until this chapter's references have been fetched once.
    final crossRefCount = ref
        .watch(
          cachedCrossRefChapterProvider(
            ChapterRef(chapter.sourceId, chapter.book, chapter.chapter),
          ),
        )
        .value
        ?.countFor(verse.number);

    return SafeArea(
      child: SingleChildScrollView(
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
              onSelected: (color) =>
                  _toggleHighlight(context, ref, color, existing),
            ),
            const SizedBox(height: 20),
            RuleGrid(
              children: [
                RuleListTile(
                  onTap: () => _openCommentary(context, ref),
                  child: _ActionRow(
                    icon: Icons.menu_book_outlined,
                    label: 'Commentaar bij vers ${verse.number}',
                  ),
                ),
                RuleListTile(
                  onTap: () => _addNote(context),
                  child: const _ActionRow(
                    icon: Icons.edit_note,
                    label: 'Notitie toevoegen',
                  ),
                ),
                RuleListTile(
                  onTap: () => _addBookmark(context, ref),
                  child: const _ActionRow(
                    icon: Icons.bookmark_add_outlined,
                    label: 'Bladwijzer plaatsen',
                  ),
                ),
                RuleListTile(
                  onTap: () => _openCrossRefs(context),
                  child: _ActionRow(
                    icon: Icons.link,
                    label: 'Kruisverwijzingen',
                    trailing: crossRefCount == null || crossRefCount == 0
                        ? null
                        : '$crossRefCount',
                  ),
                ),
                RuleListTile(
                  onTap: () => _share(context),
                  child: const _ActionRow(
                    icon: Icons.ios_share,
                    label: 'Delen',
                  ),
                ),
                RuleListTile(
                  showRule: false,
                  onTap: () => _copy(context, reference),
                  child: const _ActionRow(
                    icon: Icons.copy_all_outlined,
                    label: 'Kopiëren',
                  ),
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
        final all =
            ref.read(highlightsListProvider).value ?? const <StudyNote>[];
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    if (context.mounted) Navigator.of(context).pop();
  }

  /// Points the Commentaar tab of `/studie` at this verse and shows it. The
  /// navigation, when the reader is not already inside `/studie`, is left to
  /// [showVerseActionSheet]'s caller once this sheet has closed.
  void _openCommentary(BuildContext context, WidgetRef ref) {
    ref
        .read(pendingCommentaryVerseProvider.notifier)
        .jumpTo(ChapterVerse(chapter.book, chapter.chapter, verse.number));
    ref
        .read(studyPaneProvider.notifier)
        .apply(showMaterials: true, materialsTab: 0);
    Navigator.of(context).pop(_VerseSheetResult.commentary);
  }

  /// Hands the note back to [showVerseActionSheet] instead of opening the
  /// editor here — see the note on that function for why.
  void _addNote(BuildContext context) {
    Navigator.of(context).pop(_VerseSheetResult.note);
  }

  /// Same hand-back as the note: the cross-reference sheet outlives this one.
  void _openCrossRefs(BuildContext context) {
    Navigator.of(context).pop(_VerseSheetResult.crossRefs);
  }

  Future<void> _addBookmark(BuildContext context, WidgetRef ref) async {
    final location = ref.read(readerLocationProvider);
    try {
      await ref
          .read(notesRepositoryProvider)
          .saveBookmark(
            Bookmark(
              id: newClientId(),
              book: chapter.book,
              chapter: chapter.chapter,
              verse: verse.number,
              version: location.versionId,
              label: verse.text.length > 60
                  ? '${verse.text.substring(0, 57)}…'
                  : verse.text,
              updatedAt: DateTime.now(),
            ),
          );
      ref.invalidate(bookmarksProvider);
      await HapticFeedback.lightImpact();
    } on SyncRejectedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
      ClipboardData(
        text: '${verse.text}\n\n$reference - ${chapter.attribution}',
      ),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Gekopieerd')));
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onSelected});

  final HighlightColor? selected;
  final ValueChanged<HighlightColor> onSelected;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
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
                  color: color.fill(Theme.of(context).brightness),
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
  const _ActionRow({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;

  /// A count at the end of the row, or null while there is nothing to say.
  /// Never a placeholder: a row that reads "0" or "—" invites a tap that
  /// leads nowhere.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.inkSoft),
        const SizedBox(width: 12),
        // Flexible so a long label under large text wraps rather than
        // overflowing the sheet.
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          Text(trailing!, style: AppTheme.caption),
        ],
      ],
    );
  }
}
