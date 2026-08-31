import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_cache.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../data/bible_repository.dart';
import '../domain/bible_models.dart';
import 'bible_providers.dart';
import 'book_download_button.dart';

/// "Offline lezen": what is on this device, and how to add or remove a book.
///
/// It opens from the reader's own toolbar rather than from inside the book
/// picker's expanded chapter grid, which was the only way to reach the download
/// button before. A feature the paywall sells has to be findable by someone who
/// is not hunting for it, and the reader is where the thought "I am about to
/// lose signal" actually occurs.
Future<void> showOfflineLibrarySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (_) => const _OfflineLibrary(),
  );
}

class _OfflineLibrary extends ConsumerWidget {
  const _OfflineLibrary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(readerLocationProvider);
    final bookRef = BookRef(location.versionId, location.book);
    final chapters = ref.watch(bibleChaptersProvider(bookRef)).value ?? const <int>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Align(alignment: Alignment.centerLeft, child: Eyebrow('Offline lezen')),
          ),
          const RuleLine(),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(location.book, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                BookDownloadButton(
                  versionId: location.versionId,
                  book: location.book,
                  chapters: chapters,
                ),
                if (chapters.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'De hoofdstukkenlijst van dit boek is nog niet geladen. '
                    'Maak verbinding om het boek te kunnen downloaden.',
                    style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                  ),
                ],
                const SizedBox(height: 24),
                const SectionHeader(eyebrow: 'Op dit apparaat', title: 'Opgeslagen boeken'),
                const SizedBox(height: 12),
                OfflineBooksList(
                  onOpen: (offline) {
                    ref
                        .read(readerLocationProvider.notifier)
                        .openChapter(versionId: offline.sourceId, book: offline.book, chapter: 1);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every downloaded book with what it costs and a way to get that space back.
///
/// The chapter count comes out of the cache on every read, so a book that lost
/// chapters to eviction is shown as the partial thing it now is instead of
/// keeping the label it earned on the day it was downloaded.
class OfflineBooksList extends ConsumerWidget {
  const OfflineBooksList({super.key, this.onOpen});

  final void Function(OfflineBook book)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(offlineBooksProvider);
    final versions = ref.watch(bibleVersionsProvider).value ?? const <BibleSource>[];

    return booksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SkeletonText(lines: 4, lineHeight: 12, gap: 14),
      ),
      error: (_, __) => Text(
        'Opgeslagen boeken konden niet worden gelezen.',
        style: AppTheme.bodyMuted.copyWith(fontSize: 12),
      ),
      data: (books) {
        if (books.isEmpty) {
          return Text(
            'Je hebt nog geen boeken gedownload. Gedownloade boeken blijven bewaard, '
            'ook als de cache wordt geleegd.',
            style: AppTheme.bodyMuted.copyWith(fontSize: 12),
          );
        }
        return RuleGrid(
          children: [
            for (var i = 0; i < books.length; i++)
              _OfflineBookTile(
                book: books[i],
                versionName: versions
                        .where((v) => v.id == books[i].sourceId)
                        .map((v) => v.name)
                        .firstOrNull ??
                    books[i].sourceId,
                showRule: i < books.length - 1,
                onOpen: onOpen == null ? null : () => onOpen!(books[i]),
              ),
          ],
        );
      },
    );
  }
}

class _OfflineBookTile extends ConsumerWidget {
  const _OfflineBookTile({
    required this.book,
    required this.versionName,
    required this.showRule,
    this.onOpen,
  });

  final OfflineBook book;
  final String versionName;
  final bool showRule;
  final VoidCallback? onOpen;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${book.book} verwijderen?'),
        content: Text(
          'De opgeslagen tekst wordt van dit apparaat gewist. '
          'Je kunt het boek opnieuw downloaden zolang je verbinding hebt.',
          style: AppTheme.bodyMuted.copyWith(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(bibleRepositoryProvider).removeOfflineBook(book.sourceId, book.book);
    ref.invalidate(offlineBooksProvider);
    ref.invalidate(bookOfflineStatusProvider(BookRef(book.sourceId, book.book)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RuleListTile(
      showRule: showRule,
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.book, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  // Chapters, not "downloaded": the number is whatever the
                  // cache holds right now.
                  '$versionName · ${book.chapterCount} hoofdstuk'
                  '${book.chapterCount == 1 ? '' : 'ken'} · ${formatCacheBytes(book.bytes)}',
                  style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '${book.book} verwijderen',
            onPressed: () => _remove(context, ref),
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

String formatCacheBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
