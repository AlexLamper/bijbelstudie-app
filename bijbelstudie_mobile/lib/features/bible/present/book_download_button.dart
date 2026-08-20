import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../profile/present/profile_provider.dart';
import '../data/bible_repository.dart';

/// "Bewaar dit boek offline".
///
/// Per book, never per translation: a whole translation is hundreds of requests
/// and tens of megabytes, and a progress bar that runs for ten minutes is a
/// feature nobody finishes. Cancelling stops the loop; chapters already fetched
/// stay cached, so a cancelled download is still progress.
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

  void _start() {
    final stream = ref.read(bibleRepositoryProvider).downloadBook(
          versionId: widget.versionId,
          book: widget.book,
          chapters: widget.chapters,
        );

    setState(() => _progress = BookDownloadProgress(done: 0, total: widget.chapters.length));

    _subscription = stream.listen(
      (progress) {
        if (mounted) setState(() => _progress = progress);
      },
      onDone: () {
        if (mounted) setState(() => _progress = null);
        _subscription = null;
      },
      onError: (_) {
        if (mounted) setState(() => _progress = null);
      },
    );
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
    setState(() => _progress = null);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final isPro = ref.watch(profileProvider).value?.isPro ?? false;

    if (!isPro && !_lockedImpressionReported && widget.chapters.isNotEmpty) {
      _lockedImpressionReported = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
          'surface': 'offline',
        });
      });
    }

    if (progress == null) {
      return SiteOutlineButton(
        label: isPro ? 'Bewaar dit boek offline' : 'Offline lezen met Pro',
        icon: isPro ? Icons.download_outlined : Icons.workspace_premium_outlined,
        height: 40,
        expand: false,
        onPressed: widget.chapters.isEmpty
            ? null
            : (isPro ? _start : _openPaywall),
      );
    }

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
}
