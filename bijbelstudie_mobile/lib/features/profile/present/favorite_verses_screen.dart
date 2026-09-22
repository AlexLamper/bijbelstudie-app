import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/timed_snack_bar.dart';
import '../../bible/present/bible_providers.dart';
import '../../dashboard/data/daily_verse_store.dart';
import '../../dashboard/present/dashboard_providers.dart';
import '../../notes/present/note_row.dart';

/// The hearted daily verses, newest like first.
///
/// Derived rather than stored: the hearts live in [dailyVerseStoreProvider]
/// with the rest of the "Tekst van de dag" memory, and this only gives the
/// screen the one slice of it that it draws.
final favoriteVersesProvider = Provider<List<LikedVerse>>((ref) {
  final likes = ref.watch(dailyVerseStoreProvider).likes;
  final sorted = [...likes]..sort((a, b) => b.likedAt.compareTo(a.likedAt));
  return List.unmodifiable(sorted);
});

/// "Favoriete teksten": every daily verse the reader has hearted.
///
/// The heart on the Tekst van de dag card used to go nowhere visible - this is
/// where it lands. Rows are the same edge-to-edge [NoteListRow] the Notities
/// screen uses, so a favourite reads like a note: reference and the day it was
/// hearted on top, the verse itself under a hairline. Tapping one opens the
/// reader at that chapter; the row menu shares or un-hearts it.
class FavoriteVersesScreen extends ConsumerWidget {
  const FavoriteVersesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final memory = ref.watch(dailyVerseStoreProvider);
    final favorites = ref.watch(favoriteVersesProvider);

    final Widget body;
    if (!memory.loaded) {
      // The likes come off disk on launch; until they have, an empty list is
      // indistinguishable from "none yet".
      body = const SkeletonList(rows: 5);
    } else if (favorites.isEmpty) {
      body = const AppEmptyState(
        icon: Icons.favorite_border,
        title: 'Nog geen favorieten',
        description:
            'Tik op het hartje bij de tekst van de dag om hem hier te '
            'bewaren.',
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: favorites.length,
        itemBuilder: (context, index) =>
            _FavoriteVerseRow(like: favorites[index]),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Favoriete teksten')),
      body: body,
    );
  }
}

/// One favourite: reference and the day it was hearted, then the verse.
class _FavoriteVerseRow extends ConsumerWidget {
  const _FavoriteVerseRow({required this.like});

  final LikedVerse like;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);

    // A like migrated from the old store knows only its reference, so there is
    // no chapter to open and no date to print.
    final canOpen = like.book.isNotEmpty;
    final known = like.likedAt.millisecondsSinceEpoch > 0;

    return NoteListRow(
      onMenu: () => _menu(context, ref),
      onTap: canOpen
          ? () {
              ref
                  .read(readerLocationProvider.notifier)
                  .openChapter(book: like.book, chapter: like.chapter);
              context.go('/read');
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NoteMetaLine(
            reference: like.referenceWithVersion,
            date: known ? dutchRelativeDate(like.likedAt) : 'eerder bewaard',
          ),
          if (like.text.trim().isNotEmpty) ...[
            const SizedBox(height: 9),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 2, color: AppTheme.tealSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(like.text, style: AppTheme.verseFragment),
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

    if (picked == NoteRowAction.share) {
      final text = [like.text.trim(), like.referenceWithVersion]
          .where((part) => part.isNotEmpty)
          .join('\n\n');
      await shareRowText(context, text: text, subject: like.reference);
      return;
    }

    final confirmed = await confirmNoteDelete(
      context,
      title: 'Favoriet verwijderen',
      message:
          'Weet je zeker dat je ${like.reference} uit je favorieten wilt '
          'halen?',
    );
    if (!confirmed || !context.mounted) return;

    // Captured before the row disappears with the like it was drawn from -
    // "Ongedaan maken" is tapped when this ref is already disposed.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final removed = like;

    await ref.read(dailyVerseStoreProvider.notifier).removeLike(like.reference);
    await HapticFeedback.selectionClick();
    showTimedSnackBar(
      messenger,
      SnackBar(
        content: const Text('Favoriet verwijderd'),
        duration: kActionSnackBarDuration,
        action: SnackBarAction(
          label: 'Ongedaan maken',
          onPressed: () => container
              .read(dailyVerseStoreProvider.notifier)
              .restoreLike(removed),
        ),
      ),
    );
  }
}
