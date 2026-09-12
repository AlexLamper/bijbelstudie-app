import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/notes_repository.dart';
import '../domain/note_models.dart';
import 'notes_providers.dart';
import 'verse_action_sheet.dart';

/// Everything the reader has written down, as a list they can scan.
///
/// Rows rather than cards, and no date headings: a note is three short lines,
/// and wrapping each one in a bordered card on a grey page turned a page of
/// text into a page of boxes. One hairline between rows is enough separation,
/// and it gives every note the full width to be read in.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// A note on the chapter the reader last had open, with no verse attached -
  /// which the model already allows and [showAddNoteDialog] already writes.
  Future<void> _addLooseNote() async {
    final location = ref.read(readerLocationProvider);
    await showAddNoteDialog(
      context: context,
      ref: ref,
      book: location.book,
      chapter: location.chapter,
      translation: location.versionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      floatingActionButton: FloatingActionButton(
        onPressed: _addLooseNote,
        backgroundColor: AppTheme.teal,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: const CircleBorder(),
        tooltip: 'Nieuwe notitie',
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(controller: _tabController),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_NotesTab(), _HighlightsTab(), _BookmarksTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No large title: the tab tells you what you are looking at, and the counts
/// on the right are the only other thing worth the top of the screen.
class _Header extends ConsumerWidget {
  const _Header({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final notes = ref.watch(notesListProvider).value?.length ?? 0;
    final highlights = ref.watch(highlightsListProvider).value?.length ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'JOUW STUDIE',
                  style: AppTheme.eyebrow.copyWith(fontSize: 11),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_plural(notes, 'notitie', 'notities')} · '
                  '${_plural(highlights, 'markering', 'markeringen')}',
                  style: AppTheme.caption.copyWith(
                    fontSize: 12.5,
                    color: AppTheme.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TourAnchor(
            id: TourAnchorIds.notesTabs,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => AppUnderlineTabs(
                labels: const ['Notities', 'Markeringen', 'Bladwijzers'],
                gap: 22,
                bottomGap: 11,
                selectedIndex: controller.index,
                onChanged: controller.animateTo,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static String _plural(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';
}

class _NotesTab extends ConsumerWidget {
  const _NotesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);

    return notesAsync.when(
      loading: () => const SkeletonList(),
      error: (_, _) => const _LoadError(),
      data: (notes) {
        if (notes.isEmpty) {
          return const AppEmptyState(
            icon: Icons.edit_note,
            title: 'Nog geen notities',
            description:
                'Houd een vers ingedrukt in de lezer om er een notitie bij te schrijven.',
          );
        }
        final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: sorted.length,
          itemBuilder: (context, index) => _NoteRow(note: sorted[index]),
        );
      },
    );
  }
}

class _HighlightsTab extends ConsumerWidget {
  const _HighlightsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightsAsync = ref.watch(highlightsListProvider);

    return highlightsAsync.when(
      loading: () => const SkeletonList(),
      error: (_, _) => const _LoadError(),
      data: (highlights) {
        if (highlights.isEmpty) {
          return const AppEmptyState(
            icon: Icons.brush_outlined,
            title: 'Nog geen markeringen',
            description: 'Houd een vers ingedrukt en kies een kleur.',
          );
        }
        final sorted = [...highlights]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: sorted.length,
          itemBuilder: (context, index) => _NoteRow(note: sorted[index]),
        );
      },
    );
  }
}

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return bookmarksAsync.when(
      loading: () => const SkeletonList(),
      error: (_, _) => const _LoadError(),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return const AppEmptyState(
            icon: Icons.bookmark_outline,
            title: 'Nog geen bladwijzers',
            description: 'Bewaar een vers om er later snel bij te komen.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: bookmarks.length,
          itemBuilder: (context, index) {
            final bookmark = bookmarks[index];
            return _Row(
              onMenu: () => _confirmRemove(context, ref, bookmark),
              onTap: () {
                ref
                    .read(readerLocationProvider.notifier)
                    .openChapter(
                      versionId: bookmark.version,
                      book: bookmark.book,
                      chapter: bookmark.chapter,
                    );
                context.go('/read');
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetaLine(
                    reference: bookmark.reference,
                    date: dutchRelativeDate(bookmark.updatedAt),
                  ),
                  if (bookmark.label != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      bookmark.label!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyMuted.copyWith(
                        height: 1.6,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    Bookmark bookmark,
  ) async {
    final picked = await _showRowMenu(context, canShare: false);
    if (picked != _RowAction.delete) return;
    try {
      await ref.read(notesRepositoryProvider).deleteBookmark(bookmark.id);
      ref.invalidate(bookmarksProvider);
      await HapticFeedback.selectionClick();
    } on SyncRejectedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// One note: where it is from and when, the note itself, then the verse it
/// hangs off at a light rule.
class _NoteRow extends ConsumerWidget {
  const _NoteRow({required this.note});

  final StudyNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);

    return _Row(
      onMenu: () => _menu(context, ref),
      onTap: () {
        ref
            .read(readerLocationProvider.notifier)
            .openChapter(book: note.book, chapter: note.chapter);
        context.go('/read');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaLine(
            reference: note.reference,
            date: dutchRelativeDate(note.updatedAt),
            swatch: note.isHighlight ? note.color.swatch : null,
          ),
          if (note.noteText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note.noteText,
              style: AppTheme.bodyMuted.copyWith(height: 1.6, color: AppTheme.ink),
            ),
          ],
          if (note.verseText.trim().isNotEmpty) ...[
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
    final picked = await _showRowMenu(context, canShare: true);
    if (picked == null || !context.mounted) return;

    if (picked == _RowAction.share) {
      await Share.share(
        '${note.verseText}\n\n${note.noteText}\n\n${note.reference}',
        subject: note.reference,
      );
      return;
    }

    try {
      await ref.read(notesRepositoryProvider).deleteNote(note);
      ref.invalidate(note.isHighlight ? highlightsListProvider : notesListProvider);
      await HapticFeedback.selectionClick();
    } on SyncRejectedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

enum _RowAction { share, delete }

/// Delen and Verwijderen, behind the row's `more_vert`. They used to be two
/// always-visible icon buttons, which put two tap targets the reader almost
/// never wants at the top right of every single row.
Future<_RowAction?> _showRowMenu(BuildContext context, {required bool canShare}) {
  return showModalBottomSheet<_RowAction>(
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
              onTap: () => Navigator.of(sheetContext).pop(_RowAction.share),
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
            onTap: () => Navigator.of(sheetContext).pop(_RowAction.delete),
          ),
        ],
      ),
    ),
  );
}

/// Source, date and the row menu.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
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
class _Row extends StatelessWidget {
  const _Row({required this.child, required this.onTap, required this.onMenu});

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  /// Width reserved for the menu so the meta line never runs under it.
  static const double _menuWidth = 32;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.rule)),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: _menuWidth),
              child: child,
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                label: 'Acties',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMenu,
                  // The glyph is 17; the box around it is the 32 the content
                  // was inset by, so the tap target is not a 17px sliver.
                  child: SizedBox(
                    width: _menuWidth,
                    height: 22,
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

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.wifi_off_outlined,
      title: 'Niet geladen',
      description: 'Controleer je verbinding en probeer het opnieuw.',
    );
  }
}
