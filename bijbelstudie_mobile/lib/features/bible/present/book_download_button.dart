import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
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

    if (progress == null) {
      return SiteOutlineButton(
        label: 'Bewaar dit boek offline',
        icon: Icons.download_outlined,
        height: 40,
        expand: false,
        onPressed: widget.chapters.isEmpty ? null : _start,
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
