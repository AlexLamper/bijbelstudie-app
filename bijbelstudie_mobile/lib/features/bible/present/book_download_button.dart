import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../profile/present/profile_provider.dart';
import '../data/bible_repository.dart';
import 'bible_providers.dart';

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
  StreamSubscription<BookDownloadProgress>? _subscription;
  BookDownloadProgress? _progress;
  bool _lockedImpressionReported = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Offline reading is one of the four things the paywall sells.
  ///
  /// Unlike the commentaries and the grondtekst this gate can only live in the
  /// client, and that is not a compromise: the bible text itself is free and
  /// has to stay reachable for the reader to work at all. What Pro buys here is
  /// the bulk download, which is a feature rather than a body of text, so the
  /// button is the honest place to gate it.
  void _openPaywall() {
    ref.read(analyticsProvider).track(AnalyticsEvents.paywallCtaClicked, {
      'surface': 'offline',
    });
    context.push('/premium?source=app_study');
  }

  /// Whatever the download changed is on disk now, so anything showing the
  /// stored state has to be asked again.
  void _refreshOfflineState() {
    ref.invalidate(offlineBooksProvider);
    ref.invalidate(bookOfflineStatusProvider(BookRef(widget.versionId, widget.book)));
  }

  void _start(List<int> chapters) {
    final stream = ref.read(bibleRepositoryProvider).downloadBook(
          versionId: widget.versionId,
          book: widget.book,
          chapters: chapters,
        );

    setState(() => _progress = BookDownloadProgress(done: 0, total: chapters.length));

    _subscription = stream.listen(
      (progress) {
        if (mounted) setState(() => _progress = progress);
      },
      onDone: () {
        final failed = _progress?.failed ?? 0;
        if (mounted) setState(() => _progress = null);
        _subscription = null;
        _refreshOfflineState();
        if (mounted && failed > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$failed hoofdstuk${failed == 1 ? '' : 'ken'} kon niet worden opgehaald. '
                'Probeer het later opnieuw.',
              ),
            ),
          );
        }
      },
      onError: (_) {
        if (mounted) setState(() => _progress = null);
        _refreshOfflineState();
      },
    );
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
    setState(() => _progress = null);
    _refreshOfflineState();
  }

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
    final progress = _progress;
    final isPro = ref.watch(profileProvider).value?.isPro ?? false;
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
