import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/timed_snack_bar.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../onboarding/present/tour_controller.dart';
import '../data/notes_repository.dart';
import '../domain/note_models.dart';
import 'note_row.dart';
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
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

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
                children: const [
                  _NotesTab(),
                  _HighlightsTab(),
                  _BookmarksTab(),
                ],
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

    return _Refreshable(
      child: notesAsync.when(
        loading: () => const SkeletonList(),
        error: (_, _) => const _Fill(child: _LoadError()),
        data: (notes) {
          if (notes.isEmpty) {
            return const _Fill(
              child: AppEmptyState(
                icon: Icons.edit_note,
                title: 'Nog geen notities',
                description:
                    'Houd een vers ingedrukt in de lezer om er een notitie bij te schrijven.',
              ),
            );
          }
          final sorted = [...notes]
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: sorted.length,
            itemBuilder: (context, index) => NoteRow(note: sorted[index]),
          );
        },
      ),
    );
  }
}

class _HighlightsTab extends ConsumerWidget {
  const _HighlightsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlightsAsync = ref.watch(highlightsListProvider);

    return _Refreshable(
      child: highlightsAsync.when(
        loading: () => const SkeletonList(),
        error: (_, _) => const _Fill(child: _LoadError()),
        data: (highlights) {
          if (highlights.isEmpty) {
            return const _Fill(
              child: AppEmptyState(
                icon: Icons.brush_outlined,
                title: 'Nog geen markeringen',
                description: 'Houd een vers ingedrukt en kies een kleur.',
              ),
            );
          }
          final sorted = [...highlights]
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: sorted.length,
            itemBuilder: (context, index) => NoteRow(note: sorted[index]),
          );
        },
      ),
    );
  }
}

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return _Refreshable(
      child: bookmarksAsync.when(
        loading: () => const SkeletonList(),
        error: (_, _) => const _Fill(child: _LoadError()),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return const _Fill(
              child: AppEmptyState(
                icon: Icons.bookmark_outline,
                title: 'Nog geen bladwijzers',
                description: 'Bewaar een vers om er later snel bij te komen.',
              ),
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: bookmarks.length,
            itemBuilder: (context, index) {
              final bookmark = bookmarks[index];
              return NoteListRow(
                onMenu: () => _handleMenu(context, ref, bookmark),
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
                    NoteMetaLine(
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
      ),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    Bookmark bookmark,
  ) async {
    final picked = await showNoteRowMenu(context, canShare: true);
    if (picked == null || !context.mounted) return;

    if (picked == NoteRowAction.share) {
      // Bookmark carries no verseText/noteText of its own - label is the
      // verse excerpt _addBookmark saved at creation time, so it doubles as
      // the quoted text when there is one.
      final label = bookmark.label?.trim();
      final text = (label == null || label.isEmpty)
          ? bookmark.reference
          : '$label\n\n${bookmark.reference}';
      await shareRowText(context, text: text, subject: bookmark.reference);
      return;
    }

    final confirmed = await confirmNoteDelete(
      context,
      title: 'Bladwijzer verwijderen',
      message:
          'Weet je zeker dat je de bladwijzer bij ${bookmark.reference} wilt verwijderen?',
    );
    if (!confirmed || !context.mounted) return;

    // Captured before the delete invalidates the list and this row is gone -
    // by the time "Ongedaan maken" is tapped, ref (tied to this row) would
    // already be disposed, but the container and messenger outlive the row.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(notesRepositoryProvider).deleteBookmark(bookmark.id);
      ref.invalidate(bookmarksProvider);
      await HapticFeedback.selectionClick();
      showTimedSnackBar(
        messenger,
        SnackBar(
          content: const Text('Bladwijzer verwijderd'),
          duration: kActionSnackBarDuration,
          action: SnackBarAction(
            label: 'Ongedaan maken',
            onPressed: () async {
              try {
                // A fresh id: the server tombstoned the old one on delete and
                // answers 409 to anything that tries to bring it back.
                await container
                    .read(notesRepositoryProvider)
                    .saveBookmark(
                      Bookmark(
                        id: newClientId(),
                        book: bookmark.book,
                        chapter: bookmark.chapter,
                        verse: bookmark.verse,
                        version: bookmark.version,
                        label: bookmark.label,
                        updatedAt: DateTime.now(),
                      ),
                    );
                container.invalidate(bookmarksProvider);
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

/// Pull to refresh, from any of the three tabs.
///
/// All three lists are fetched again, not just the visible one: the header
/// counts read two of them, and a reader who pulls expects the whole screen to
/// be current. Offline edits are pushed first so the fresh lists include them.
/// A failed request keeps the list already on screen.
class _Refreshable extends ConsumerWidget {
  const _Refreshable({required this.child});

  final Widget child;

  Future<void> _refresh(WidgetRef ref) async {
    Future<void> quiet(Future<Object?> request) async {
      try {
        await request;
      } catch (_) {}
    }

    await quiet(ref.read(notesRepositoryProvider).flushPendingChanges());
    await Future.wait<void>([
      quiet(ref.refresh(notesListProvider.future)),
      quiet(ref.refresh(highlightsListProvider.future)),
      quiet(ref.refresh(bookmarksProvider.future)),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    return RefreshIndicator(
      color: AppTheme.teal,
      backgroundColor: AppTheme.paperRaised,
      onRefresh: () => _refresh(ref),
      child: child,
    );
  }
}

/// A non-scrolling state - empty, or failed to load - made scrollable at full
/// height, so it can be pulled down like the list it stands in for.
class _Fill extends StatelessWidget {
  const _Fill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
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
