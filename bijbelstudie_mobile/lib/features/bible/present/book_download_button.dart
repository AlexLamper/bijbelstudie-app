import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../premium/present/paywall_route.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../premium/present/pro_access_provider.dart';
import '../data/bible_repository.dart';
import '../domain/copy_policy.dart';
import 'bible_providers.dart';

/// The book downloads that are running right now, by book.
///
/// Held here rather than in the widget that started one: the reader's "meer"
/// menu and the book picker both start downloads, and both are gone the moment
/// they close. The download carries on regardless, and whichever of them is
/// opened next shows the same progress instead of starting a second run.
class BookDownloads extends Notifier<Map<BookRef, BookDownloadProgress>> {
  final _subscriptions = <BookRef, StreamSubscription<BookDownloadProgress>>{};
  final _results = <BookRef, Completer<int?>>{};

  @override
  Map<BookRef, BookDownloadProgress> build() {
    ref.onDispose(() {
      for (final subscription in _subscriptions.values) {
        subscription.cancel();
      }
      _subscriptions.clear();
    });
    return const {};
  }

  /// Fetches [chapters] of [book] into the cache.
  ///
  /// Completes with the number of chapters that could not be fetched, or null
  /// when the run was cancelled, failed outright or was already running.
  Future<int?> start(BookRef book, List<int> chapters) {
    if (_subscriptions.containsKey(book)) return Future.value(null);
    final result = Completer<int?>();
    _results[book] = result;
    _set(book, BookDownloadProgress(done: 0, total: chapters.length));

    _subscriptions[book] = ref
        .read(bibleRepositoryProvider)
        .downloadBook(versionId: book.sourceId, book: book.book, chapters: chapters)
        .listen(
          (progress) => _set(book, progress),
          onDone: () => _finish(book, state[book]?.failed ?? 0),
          onError: (_) => _finish(book, null),
          cancelOnError: true,
        );
    return result.future;
  }

  /// Stops the loop. Chapters already fetched stay cached.
  void cancel(BookRef book) {
    _subscriptions[book]?.cancel();
    _finish(book, null);
  }

  void _set(BookRef book, BookDownloadProgress progress) {
    state = {...state, book: progress};
  }

  /// Whatever the download changed is on disk now, so anything showing the
  /// stored state has to be asked again.
  void _finish(BookRef book, int? failed) {
    _subscriptions.remove(book);
    state = {...state}..remove(book);
    ref.invalidate(offlineBooksProvider);
    ref.invalidate(bookOfflineStatusProvider(book));
    final result = _results.remove(book);
    if (result != null && !result.isCompleted) result.complete(failed);
  }
}

final bookDownloadsProvider =
    NotifierProvider<BookDownloads, Map<BookRef, BookDownloadProgress>>(BookDownloads.new);

/// Starts a download of [chapters] and reports chapters that could not be
/// fetched through [messenger] - captured before the caller can go away, so the
/// message still lands after the sheet or menu that started it has closed.
Future<void> runBookDownload(
  ScaffoldMessengerState? messenger,
  BookDownloads downloads,
  BookRef book,
  List<int> chapters,
) async {
  final failed = await downloads.start(book, chapters);
  if (failed == null || failed == 0) return;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        '$failed hoofdstuk${failed == 1 ? '' : 'ken'} kon niet worden opgehaald. '
        'Probeer het later opnieuw.',
      ),
    ),
  );
}

/// Offline reading is a Pro feature; this is the way to Pro from wherever a
/// download was offered. Counted under the same surface everywhere.
///
/// A reader here has already said what they want by tapping a download, so
/// this goes straight to the price rather than through the pitch.
void openOfflinePaywall(BuildContext context, WidgetRef ref) {
  ref.read(analyticsProvider).track(AnalyticsEvents.paywallCtaClicked, {
    'surface': 'offline',
  });
  openPaywall(context, gate: PaywallGate.offline);
}

/// "Bewaar dit boek offline".
///
/// Per book, never per translation: a whole translation is hundreds of requests
/// and tens of megabytes, and a progress bar that runs for ten minutes is a
/// feature nobody finishes. Cancelling stops the loop; chapters already fetched
/// stay cached, so a cancelled download is still progress.
///
/// Whatever it says about the book is read back out of the cache rather than
/// remembered from the last download. A cancelled run, a chapter the server
/// refused and an eviction all look the same from here - fewer chapters on
/// disk - and all three have to read as "not finished" rather than as a stored
/// book that silently is not one.
class BookDownloadButton extends ConsumerStatefulWidget {
  const BookDownloadButton({
    super.key,
    required this.versionId,
    required this.book,
    required this.chapters,
  });

  final String versionId;
  final String book;
  final List<int> chapters;

  @override
  ConsumerState<BookDownloadButton> createState() => _BookDownloadButtonState();
}

class _BookDownloadButtonState extends ConsumerState<BookDownloadButton> {
  bool _lockedImpressionReported = false;

  BookRef get _bookRef => BookRef(widget.versionId, widget.book);

  /// Offline reading is one of the four things the paywall sells.
  ///
  /// Unlike the commentaries and the grondtekst this gate can only live in the
  /// client, and that is not a compromise: the bible text itself is free and
  /// has to stay reachable for the reader to work at all. What Pro buys here is
  /// the bulk download, which is a feature rather than a body of text, so the
  /// button is the honest place to gate it.
  void _openPaywall() => openOfflinePaywall(context, ref);

  /// Whatever the download changed is on disk now, so anything showing the
  /// stored state has to be asked again.
  void _refreshOfflineState() {
    ref.invalidate(offlineBooksProvider);
    ref.invalidate(bookOfflineStatusProvider(BookRef(widget.versionId, widget.book)));
  }

  void _start(List<int> chapters) {
    runBookDownload(
      ScaffoldMessenger.maybeOf(context),
      ref.read(bookDownloadsProvider.notifier),
      _bookRef,
      chapters,
    );
  }

  void _cancel() => ref.read(bookDownloadsProvider.notifier).cancel(_bookRef);

  Future<void> _remove() async {
    await ref.read(bibleRepositoryProvider).removeOfflineBook(widget.versionId, widget.book);
    _refreshOfflineState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.book} is van dit apparaat verwijderd')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A copy-restricted translation is not downloadable as a whole book. The
    // reader may keep a verse (a note, a bookmark, the clipboard); putting
    // every chapter of a licensed translation on the device is the bulk copy
    // the licence does not cover. See features/bible/domain/copy_policy.dart.
    if (isCopyRestricted(widget.versionId)) {
      return Text(
        copyRestrictedOfflineNotice,
        style: AppTheme.bodyMuted.copyWith(fontSize: 11),
      );
    }

    final progress = ref.watch(bookDownloadsProvider)[_bookRef];
    // Store or server: flips the moment a purchase completes.
    final isPro = ref.watch(hasProProvider);
    final status = ref
        .watch(bookOfflineStatusProvider(BookRef(widget.versionId, widget.book)))
        .value;

    if (!isPro && !_lockedImpressionReported && widget.chapters.isNotEmpty) {
      _lockedImpressionReported = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
          'surface': 'offline',
        });
      });
    }

    if (progress != null) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${progress.done} van ${progress.total} hoofdstukken',
                  style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 4,
                    backgroundColor: AppTheme.rule,
                    color: AppTheme.lapis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: _cancel, child: const Text('Stoppen')),
        ],
      );
    }

    final stored = status?.stored ?? const <int>[];
    final complete = status?.isComplete ?? false;
    // Only the chapters that are not on disk yet, so "de rest" really is the
    // rest and a resumed download does not refetch what it already has.
    final missing = widget.chapters.where((c) => !stored.contains(c)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stored.isNotEmpty) ...[
          BookOfflineStatusLine(status: status),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (!complete)
              SiteOutlineButton(
                label: isPro
                    ? (stored.isEmpty ? 'Bewaar dit boek offline' : 'Rest opslaan')
                    : 'Offline lezen met Pro',
                icon: isPro ? Icons.download_outlined : Icons.workspace_premium_outlined,
                height: 40,
                expand: false,
                onPressed: widget.chapters.isEmpty
                    ? null
                    : (isPro ? () => _start(missing.isEmpty ? widget.chapters : missing) : _openPaywall),
              ),
            if (stored.isNotEmpty)
              TextButton(
                onPressed: _remove,
                child: const Text('Verwijderen'),
              ),
          ],
        ),
      ],
    );
  }
}

/// One line saying what of a book is genuinely on the device.
///
/// Says nothing at all when the chapter list is unknown beyond the bare count,
/// because "12 hoofdstukken opgeslagen" is true and "12 van 50" would be a
/// guess whenever the translation's own chapter list has not been loaded.
class BookOfflineStatusLine extends StatelessWidget {
  const BookOfflineStatusLine({super.key, required this.status});

  final BookOfflineStatus? status;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final status = this.status;
    if (status == null || status.isEmpty) {
      return Text(
        'Nog niets van dit boek opgeslagen',
        style: AppTheme.bodyMuted.copyWith(fontSize: 11),
      );
    }

    final complete = status.isComplete;
    final total = status.total;
    final label = complete
        ? 'Volledig offline beschikbaar'
        : total == null
            ? '${status.stored.length} hoofdstukken offline beschikbaar'
            : '${status.stored.length} van $total hoofdstukken offline beschikbaar';

    return Row(
      children: [
        Icon(
          complete ? Icons.offline_pin_outlined : Icons.downloading_outlined,
          size: 14,
          color: complete ? AppTheme.lapis : AppTheme.inkMuted,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTheme.bodyMuted.copyWith(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
