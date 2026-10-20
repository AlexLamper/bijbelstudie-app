import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/kring_share_action.dart';
import '../../../core/ui/timed_snack_bar.dart';
import '../../bible/present/bible_providers.dart';
import '../../commentary/domain/commentary_copy_policy.dart';
import '../../commentary/domain/commentary_note_anchor.dart';
import '../../commentary/present/commentary_note_target.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../friends/data/friend_models.dart' show FriendPostKind;
import '../../settings/data/reading_settings.dart';
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

  /// The commentary section this note hangs off, or null for a note on a bible
  /// verse. Read out of the note's own tags - see `CommentaryNoteAnchor`.
  CommentaryNoteAnchor? get _anchor => CommentaryNoteAnchor.fromTags(
    note.tags,
    book: note.book,
    chapter: note.chapter,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final anchor = _anchor;

    return NoteListRow(
      onMenu: () => _menu(context, ref),
      onTap: tapOpensReader
          ? () {
              if (anchor != null) {
                _openCommentary(context, ref, anchor);
                return;
              }
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
          if (anchor != null) CommentaryNoteLine(anchor: anchor),
          if (note.isStudyReflection)
            ReflectionNoteBody(note: note)
          else if (note.noteText.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              note.noteText,
              style: AppTheme.bodyMuted.copyWith(color: AppTheme.ink),
            ),
          ],
          if (!note.isStudyReflection && note.verseText.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: AppTheme.tealSoft),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        note.verseText,
                        style: AppTheme.verseFragment,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Puts the reader back in the commentary this note was written in: the
  /// chapter, the commentator, and the section the anchor names.
  ///
  /// The source is set first, because the pane on `/commentary` loads whatever
  /// commentary the reader last chose; the anchor is what it scrolls to once
  /// that chapter is up.
  void _openCommentary(
    BuildContext context,
    WidgetRef ref,
    CommentaryNoteAnchor anchor,
  ) {
    ref
        .read(readerLocationProvider.notifier)
        .openChapter(book: anchor.book, chapter: anchor.chapter);
    ref
        .read(readingSettingsProvider.notifier)
        .setLastCommentary(anchor.commentaryId);
    ref.read(pendingCommentaryNoteProvider.notifier).set(anchor);
    context.go('/commentary');
  }

  /// The note as text, without the reference: a reflection is its question and
  /// its answer, anything else the verse it hangs off and what the reader
  /// wrote. Shared by both share actions so the kring reads the same note the
  /// system sheet would hand out.
  ///
  /// One exception, and it is the whole point of the copy guard: a note on a
  /// licensed commentary shares what the reader wrote and where they wrote it,
  /// never the commentary's own words. Keeping that fragment in the reader's
  /// private note is fine; putting it on the clipboard or in the kring is the
  /// redistribution no licence here covers.
  String _body() {
    final anchor = _anchor;
    final quoteStaysHere =
        anchor != null && isCommentaryCopyRestricted(anchor.commentaryId);

    return [
      if (note.isStudyReflection) ...[
        note.reflectionParts.question,
        note.reflectionParts.answer,
      ] else ...[
        if (!quoteStaysHere) note.verseText.trim(),
        note.noteText.trim(),
      ],
    ].where((part) => part.isNotEmpty).join('\n\n');
  }

  /// The line a share signs off with. A commentary note names its commentator,
  /// which is attribution rather than text and travels freely.
  String _shareReference() {
    final anchor = _anchor;
    if (anchor == null) return note.reference;
    return '${note.reference} - ${commentaryDisplayName(anchor.commentaryId)}';
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final picked = await showNoteRowMenu(
      context,
      canShare: true,
      canShareToKring: true,
    );
    if (picked == null || !context.mounted) return;

    final kind = note.isHighlight ? 'Markering' : 'Notitie';

    if (picked == NoteRowAction.share) {
      final reference = _shareReference();
      final text = [_body(), reference]
          .where((part) => part.isNotEmpty)
          .join('\n\n');
      await shareRowText(context, text: text, subject: reference);
      return;
    }

    if (picked == NoteRowAction.shareToKring) {
      // A copy, not a view: the text as it reads at this tap. Editing the
      // note afterwards leaves the post in the kring exactly as the kring
      // read it, which is what VRIENDENKRING_PLAN.md §8 promises. The note's
      // id travels as sourceId so the server can dedupe a double tap and so
      // deleting the note can find the post again.
      await shareIntoKring(
        context,
        ref,
        kind: FriendPostKind.note,
        body: _body(),
        reference: _shareReference(),
        sourceId: note.id,
      );
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

/// Says a note hangs off a commentary rather than off the bible text, and which
/// commentator and section - the same two words the pane pills that entry with,
/// so the row names the spot the way the reader saw it.
///
/// Kept to one quiet line, like "Reflectie uit je studie" above: the note the
/// reader wrote is still the row's subject.
class CommentaryNoteLine extends StatelessWidget {
  const CommentaryNoteLine({super.key, required this.anchor});

  final CommentaryNoteAnchor anchor;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.menu_book_outlined, size: 13, color: AppTheme.teal),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Commentaar: ${commentaryDisplayName(anchor.commentaryId)}, '
              '${anchor.sectionLabel.toLowerCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(fontSize: 12, color: AppTheme.teal),
            ),
          ),
        ],
      ),
    );
  }
}

enum NoteRowAction { share, shareToKring, delete }

/// Delen and Verwijderen, behind the row's `more_vert`. They used to be two
/// always-visible icon buttons, which put two tap targets the reader almost
/// never wants at the top right of every single row.
///
/// [canShareToKring] adds the second, quite different share: "Delen" hands the
/// note to the apps on the phone, "Deel met je vrienden" places a copy of it
/// in the reader's vriendenkring. It is off unless a caller asks for it, so a
/// screen that does not handle [NoteRowAction.shareToKring] can never be given
/// it.
Future<NoteRowAction?> showNoteRowMenu(
  BuildContext context, {
  required bool canShare,
  bool canShareToKring = false,
}) {
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
              subtitle: canShareToKring
                  ? Text('Via de apps op je telefoon', style: AppTheme.caption)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(NoteRowAction.share),
            ),
          if (canShareToKring)
            ListTile(
              leading: Icon(Icons.group_outlined, size: 20, color: AppTheme.teal),
              title: Text('Deel met je vrienden', style: AppTheme.bodyStrong),
              subtitle: Text(
                'In je vriendenkring in de app',
                style: AppTheme.caption,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(NoteRowAction.shareToKring),
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
            style: AppTheme.bodyStrong.copyWith(color: AppTheme.teal),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: AppTheme.ruleStrong,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        // Takes the rest of the line, so the dot stays by the reference it
        // belongs to instead of drifting out to the menu.
        Expanded(
          child: Text(
            date,
            style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  /// The row's own insets. The menu reaches into the right one, so the glyph
  /// does not move when its tap target grows to 44.
  static const double _padLeft = 24;
  static const double _padTop = 20;
  static const double _padRight = 24;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        // A lighter line than the screen's own rules: inside a list of notes it
        // separates rather than frames.
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.paperSunken)),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _padLeft,
                _padTop,
                _menuWidth,
                22,
              ),
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
                    padding: const EdgeInsets.only(
                      top: _padTop,
                      right: _padRight,
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Icon(
                        Icons.more_vert,
                        size: 18,
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
