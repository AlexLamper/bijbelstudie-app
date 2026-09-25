import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/timed_snack_bar.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../data/notes_repository.dart';
import '../domain/note_models.dart';
import 'notes_providers.dart';

/// One note: where it is from and when, the note itself, then the verse it
/// hangs off at a light rule.
class NoteRow extends ConsumerWidget {
  const NoteRow({super.key, required this.note, this.tapOpensReader = true});

  final StudyNote note;

  /// Whether tapping the row jumps the reader to the note's chapter.
  ///
  /// True on the Notities screen, where the note is the only way back to the
  /// passage. False in the study screen's Notities tab: the chapter is
  /// already open in the pane beside it, so a tap that navigated away would
  /// throw the reader out of the study they are in.
  final bool tapOpensReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);

    return NoteListRow(
      onMenu: () => _menu(context, ref),
      onTap: tapOpensReader
          ? () {
              ref
                  .read(readerLocationProvider.notifier)
                  .openChapter(book: note.book, chapter: note.chapter);
              context.go('/read');
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NoteMetaLine(
            reference: note.reference,
            date: dutchRelativeDate(note.updatedAt),
            swatch: note.isHighlight
                ? note.color.fill(Theme.of(context).brightness)
                : null,
          ),
          if (note.isStudyReflection)
            ReflectionNoteBody(note: note)
          else if (note.noteText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note.noteText,
              style: AppTheme.bodyMuted.copyWith(height: 1.6, color: AppTheme.ink),
            ),
          ],
          if (!note.isStudyReflection && note.verseText.trim().isNotEmpty) ...[
            const SizedBox(height: 9),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 2, color: AppTheme.tealSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(note.verseText, style: AppTheme.verseFragment),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final picked = await showNoteRowMenu(context, canShare: true);
    if (picked == null || !context.mounted) return;

    final kind = note.isHighlight ? 'Markering' : 'Notitie';

    if (picked == NoteRowAction.share) {
      final text = [
        if (note.isStudyReflection) ...[
          note.reflectionParts.question,
          note.reflectionParts.answer,
        ] else ...[
          note.verseText.trim(),
          note.noteText.trim(),
        ],
        note.reference,
      ].where((part) => part.isNotEmpty).join('\n\n');
      await shareRowText(context, text: text, subject: note.reference);
      return;
    }

    final confirmed = await confirmNoteDelete(
      context,
      title: '$kind verwijderen',
      message:
          'Weet je zeker dat je de ${kind.toLowerCase()} bij ${note.reference} wilt verwijderen?',
    );
    if (!confirmed || !context.mounted) return;

    // Captured before the delete invalidates the list and this row is gone -
    // by the time "Ongedaan maken" is tapped, ref (tied to this row) would
    // already be disposed, but the container and messenger outlive the row.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final listProvider = note.isHighlight ? highlightsListProvider : notesListProvider;

    try {
      await ref.read(notesRepositoryProvider).deleteNote(note);
      ref.invalidate(listProvider);
      await HapticFeedback.selectionClick();
      showTimedSnackBar(
        messenger,
        SnackBar(
          content: Text('$kind verwijderd'),
          duration: kActionSnackBarDuration,
          action: SnackBarAction(
            label: 'Ongedaan maken',
            onPressed: () async {
              try {
                // A fresh id: the server tombstoned the old one on delete and
                // answers 409 to anything that tries to bring it back.
                await container
                    .read(notesRepositoryProvider)
                    .saveNote(note.withNewId(newClientId()));
                container.invalidate(listProvider);
              } on SyncRejectedException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
          ),
        ),
      );
    } on SyncRejectedException catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// A note from a study lesson's reflection step: a small mark that says where
/// it came from, the lesson's question, and the reader's answer right under it.
///
/// No scripture. The server copies the whole lesson passage into these - for
/// a chapter study, the entire chapter - which buried a two-line answer under
/// a wall of text. The reference on the meta line above is all the row needs,
/// and a tap on the Notities screen opens that chapter anyway.
class ReflectionNoteBody extends StatelessWidget {
  const ReflectionNoteBody({super.key, required this.note});

  final StudyNote note;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final (:question, :answer) = note.reflectionParts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.auto_stories_outlined, size: 13, color: AppTheme.teal),
            const SizedBox(width: 5),
            Text(
              'Reflectie uit je studie',
              style: AppTheme.caption.copyWith(fontSize: 12, color: AppTheme.teal),
            ),
          ],
        ),
        if (question.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            question,
            style: AppTheme.bodyMuted.copyWith(
              fontSize: 13.5,
              height: 1.45,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (answer.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(answer, style: AppTheme.bodyMuted.copyWith(height: 1.5, color: AppTheme.ink)),
        ],
      ],
    );
  }
}

enum NoteRowAction { share, delete }

/// Delen and Verwijderen, behind the row's `more_vert`. They used to be two
/// always-visible icon buttons, which put two tap targets the reader almost
/// never wants at the top right of every single row.
Future<NoteRowAction?> showNoteRowMenu(BuildContext context, {required bool canShare}) {
  return showModalBottomSheet<NoteRowAction>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canShare)
            ListTile(
              leading: Icon(Icons.ios_share, size: 20, color: AppTheme.inkSoft),
              title: Text('Delen', style: AppTheme.bodyStrong),
              onTap: () => Navigator.of(sheetContext).pop(NoteRowAction.share),
            ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              size: 20,
              color: AppTheme.destructive,
            ),
            title: Text(
              'Verwijderen',
              style: AppTheme.bodyStrong.copyWith(color: AppTheme.destructive),
            ),
            onTap: () => Navigator.of(sheetContext).pop(NoteRowAction.delete),
          ),
        ],
      ),
    ),
  );
}

/// Confirms before deleting anything - the sheet used to hand back
/// [NoteRowAction.delete] and the caller deleted on the spot, with no reminder
/// of which row a tap had actually landed on and no way back.
Future<bool> confirmNoteDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
          child: const Text('Verwijderen'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Shares [text] through the system sheet.
///
/// Anchored on the row's own on-screen rect: on iPad share_plus pops the
/// sheet from [sharePositionOrigin] and has nothing to anchor to without it,
/// which is one way this used to fail silently. The call is also wrapped
/// rather than fired-and-forgotten as before, so a platform failure lands as
/// a SnackBar instead of nothing happening at all.
Future<void> shareRowText(BuildContext context, {required String text, String? subject}) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
  try {
    await Share.share(text, subject: subject, sharePositionOrigin: origin);
  } on Exception {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Delen is niet gelukt.')));
    }
  }
}

/// Source, date and the row menu.
class NoteMetaLine extends StatelessWidget {
  const NoteMetaLine({
    super.key,
    required this.reference,
    required this.date,
    this.swatch,
  });

  final String reference;
  final String date;

  /// The highlight's colour, on the Markeringen tab.
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Row(
      children: [
        if (swatch != null) ...[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: AppTheme.rule),
            ),
          ),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: Text(
            reference,
            style: AppTheme.pillLabel.copyWith(color: AppTheme.teal),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 9),
        Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: AppTheme.ruleStrong,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          date,
          style: AppTheme.caption.copyWith(
            fontSize: 12.5,
            color: AppTheme.inkFaint,
          ),
        ),
      ],
    );
  }
}

/// An edge-to-edge row under one hairline. No card, no margin, no radius.
///
/// The row owns the overflow menu rather than the meta line inside it, so the
/// glyph lands in the same corner on every row - note, highlight or bookmark -
/// whatever the reference and date underneath it happen to be.
class NoteListRow extends StatelessWidget {
  const NoteListRow({super.key, required this.child, required this.onMenu, this.onTap});

  final Widget child;

  /// Null when the row has nowhere to go - the row then only answers its menu.
  final VoidCallback? onTap;
  final VoidCallback onMenu;

  /// Width reserved for the menu so the meta line never runs under it - also
  /// the button's own tap-target size, Apple HIG's 44x44 minimum. The row's
  /// own padding (16 right, 17 top) isn't enough room for that on its own, so
  /// the Stack below spans the whole row rather than sitting inside the
  /// padding, letting the button reach into it without moving the glyph.
  static const double _menuWidth = 44;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.rule)),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 17, _menuWidth, 17),
              child: child,
            ),
            Positioned(
              top: 0,
              right: 0,
              width: _menuWidth,
              height: _menuWidth,
              child: Semantics(
                button: true,
                label: 'Acties',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMenu,
                  // The tap target fills the box above; the glyph is padded
                  // back down to where the row's own padding used to put it,
                  // so it doesn't visibly move when the target grows.
                  child: Padding(
                    padding: const EdgeInsets.only(top: 17, right: 16),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Icon(
                        Icons.more_vert,
                        size: 17,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
