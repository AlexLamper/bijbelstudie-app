import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../bible/present/bible_providers.dart';
import '../data/notes_repository.dart';
import '../domain/note_models.dart';
import 'notes_providers.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Eyebrow('Jouw studie')),
            ),
            TabBar(
              controller: _tabController,
              labelStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Notities'),
                Tab(text: 'Markeringen'),
                Tab(text: 'Bladwijzers'),
              ],
            ),
            const RuleLine(),
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

class _NotesTab extends ConsumerWidget {
  const _NotesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);

    return notesAsync.when(
      loading: () => const AppLoader(),
      error: (_, __) => const _LoadError(),
      data: (notes) {
        if (notes.isEmpty) {
          return const AppEmptyState(
            icon: Icons.edit_note,
            title: 'Nog geen notities',
            description:
                'Houd een vers ingedrukt in de lezer om er een notitie bij te schrijven.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: notes.length,
          itemBuilder: (context, index) => _NoteTile(note: notes[index]),
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
      loading: () => const AppLoader(),
      error: (_, __) => const _LoadError(),
      data: (highlights) {
        if (highlights.isEmpty) {
          return const AppEmptyState(
            icon: Icons.brush_outlined,
            title: 'Nog geen markeringen',
            description: 'Houd een vers ingedrukt en kies een kleur.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: highlights.length,
          itemBuilder: (context, index) => _NoteTile(note: highlights[index]),
        );
      },
    );
  }
}

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return bookmarksAsync.when(
      loading: () => const AppLoader(),
      error: (_, __) => const _LoadError(),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return const AppEmptyState(
            icon: Icons.bookmark_outline,
            title: 'Nog geen bladwijzers',
            description: 'Bewaar een vers om er later snel bij te komen.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: bookmarks.length,
          itemBuilder: (context, index) {
            final bookmark = bookmarks[index];
            return RuleListTile(
              onTap: () {
                ref.read(readerLocationProvider.notifier).openChapter(
                      versionId: bookmark.version,
                      book: bookmark.book,
                      chapter: bookmark.chapter,
                    );
                context.go('/read');
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookmark.reference,
                          style: AppTheme.caption.copyWith(color: AppTheme.lapis),
                        ),
                        if (bookmark.label != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            bookmark.label!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bladwijzer verwijderen',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () async {
                      try {
                        await ref.read(notesRepositoryProvider).deleteBookmark(bookmark.id);
                        ref.invalidate(bookmarksProvider);
                        await HapticFeedback.selectionClick();
                      } on SyncRejectedException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note});

  final StudyNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RuleListTile(
      onTap: () {
        ref
            .read(readerLocationProvider.notifier)
            .openChapter(book: note.book, chapter: note.chapter);
        context.go('/read');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (note.isHighlight)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: note.color.swatch,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppTheme.rule),
                  ),
                ),
              Expanded(
                child: Text(
                  note.reference,
                  style: AppTheme.caption.copyWith(color: AppTheme.lapis),
                ),
              ),
              IconButton(
                tooltip: 'Delen',
                icon: const Icon(Icons.ios_share, size: 16),
                onPressed: () => Share.share(
                  '${note.verseText}\n\n${note.noteText}\n\n${note.reference}',
                  subject: note.reference,
                ),
              ),
              IconButton(
                tooltip: 'Verwijderen',
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () async {
                  try {
                    await ref.read(notesRepositoryProvider).deleteNote(note);
                    ref.invalidate(
                      note.isHighlight ? highlightsListProvider : notesListProvider,
                    );
                    await HapticFeedback.selectionClick();
                  } on SyncRejectedException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
              ),
            ],
          ),
          if (note.verseText.isNotEmpty)
            Text(
              note.verseText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyMuted.copyWith(fontSize: 12),
            ),
          if (note.noteText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note.noteText, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ],
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
