import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../bible/present/read_screen.dart' show pendingVerseAnchorProvider;
import '../domain/crossref_models.dart';
import 'crossref_providers.dart';

/// References shown before "Toon alle" is offered.
const int crossRefVisibleCount = 8;

/// Rows whose preview text is fetched straight away. Each one costs a chapter
/// request the first time it is read, so the rest wait until the reader has
/// said they want to see them.
const int crossRefPreviewBatch = 5;

/// "Kruisverwijzingen" for one verse: the passages that speak about the same
/// thing, previewed in the translation the reader is already in.
///
/// Navigation is done *here*, after the sheet has closed, rather than inside
/// it — the same rule `showVerseActionSheet` follows. The sheet pops with the
/// reference it was asked to follow; [context] and [ref] belong to the reader,
/// which is still mounted, so the reader location and the "terug" snackbar are
/// set from a scope that outlives the sheet.
Future<void> showCrossRefSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterContent chapter,
  required Verse verse,
}) async {
  final analytics = ref.read(analyticsProvider);
  analytics.track(AnalyticsEvents.crossRefOpened, {'surface': 'app_sheet'});

  final messenger = ScaffoldMessenger.maybeOf(context);
  // The snackbar action can be pressed seconds after this function returned,
  // long after the widget that opened the sheet may have been rebuilt away.
  // The container is what stays; `ref` is not safe to close over.
  final container = ProviderScope.containerOf(context, listen: false);

  final target = await showModalBottomSheet<CrossRef>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
    ),
    builder: (_) => _CrossRefSheet(chapter: chapter, verse: verse),
  );

  if (target == null || !context.mounted) return;

  final reference = '${chapter.book} ${chapter.chapter}:${verse.number}';
  final origin = ref.read(readerLocationProvider);

  ref.read(pendingVerseAnchorProvider.notifier).set(target.verse);
  ref
      .read(readerLocationProvider.notifier)
      .openChapter(book: target.book, chapter: target.chapter);
  context.go('/read');

  analytics.track(AnalyticsEvents.crossRefFollowed, {
    'surface': 'app_sheet',
    'action': 'navigate',
    'testament': crossRefTestamentPair(chapter.book, target.book),
  });

  messenger?.showSnackBar(
    SnackBar(
      content: const Text('Kruisverwijzing geopend.'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Terug naar $reference',
        onPressed: () {
          container.read(pendingVerseAnchorProvider.notifier).set(verse.number);
          container.read(readerLocationProvider.notifier).openChapter(
                versionId: origin.versionId,
                book: origin.book,
                chapter: origin.chapter,
              );
          analytics.track(AnalyticsEvents.crossRefFollowed, {
            'surface': 'app_sheet',
            'action': 'back',
            'testament': crossRefTestamentPair(target.book, chapter.book),
          });
        },
      ),
    ),
  );
}

class _CrossRefSheet extends ConsumerStatefulWidget {
  const _CrossRefSheet({required this.chapter, required this.verse});

  final ChapterContent chapter;
  final Verse verse;

  @override
  ConsumerState<_CrossRefSheet> createState() => _CrossRefSheetState();
}

class _CrossRefSheetState extends ConsumerState<_CrossRefSheet> {
  bool _showAll = false;

  ChapterRef get _chapterRef => ChapterRef(
        widget.chapter.sourceId,
        widget.chapter.book,
        widget.chapter.chapter,
      );

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final reference =
        '${widget.chapter.book} ${widget.chapter.chapter}:${widget.verse.number}';
    final async = ref.watch(crossRefChapterProvider(_chapterRef));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Kruisverwijzingen'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        reference,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Meest relevante eerst', style: AppTheme.caption),
                  ],
                ),
              ],
            ),
          ),
          const RuleLine(),
          Expanded(
            child: async.when(
              loading: () => _Padded(
                controller: controller,
                children: const [SkeletonText(lines: 6, lineHeight: 14)],
              ),
              error: (error, _) => _Padded(
                controller: controller,
                children: [_ErrorBlock(error: error, onRetry: _retry)],
              ),
              data: (data) => _body(controller, data),
            ),
          ),
        ],
      ),
    );
  }

  void _retry() => ref.invalidate(crossRefChapterProvider(_chapterRef));

  Widget _body(ScrollController controller, CrossRefChapter data) {
    final refs = data.refsFor(widget.verse.number);

    if (refs.isEmpty) {
      return _Padded(
        controller: controller,
        children: [
          Text(
            'Geen kruisverwijzingen bij dit vers.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          _Attribution(data.attribution),
        ],
      );
    }

    final visible = _showAll ? refs : refs.take(crossRefVisibleCount).toList();
    final previewLimit = _showAll ? visible.length : crossRefPreviewBatch;

    return _Padded(
      controller: controller,
      children: [
        if (data.numberingMayDiffer) ...[
          Text(
            'Versnummering kan in deze vertaling afwijken.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 12),
        ],
        RuleGrid(
          children: [
            for (var i = 0; i < visible.length; i++)
              _CrossRefRow(
                key: ValueKey('${visible[i].osis}-${visible[i].chapter}-${visible[i].verse}'),
                versionId: widget.chapter.sourceId,
                fromBook: widget.chapter.book,
                target: visible[i],
                showPreview: i < previewLimit,
                isLast: i == visible.length - 1,
              ),
          ],
        ),
        if (refs.length > crossRefVisibleCount) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll ? 'Minder tonen' : 'Toon alle ${refs.length}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Attribution(data.attribution),
      ],
    );
  }
}

/// The scrolling body of the sheet. [DraggableScrollableSheet] only drags when
/// the scrollable it builds uses the controller it handed out, so every state
/// of the sheet — loading, error, empty, full — has to scroll through this.
class _Padded extends StatelessWidget {
  const _Padded({required this.controller, required this.children});

  final ScrollController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  /// Nothing reached the server, as opposed to the server answering badly.
  /// Worth telling apart: one is solved by moving, the other is not.
  bool get _offline {
    final e = error;
    if (e is! DioException) return false;
    return e.type != DioExceptionType.badResponse;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RuleGrid(
          children: [
            RuleListTile(
              showRule: false,
              child: Text(
                _offline
                    ? 'Niet offline beschikbaar'
                    : 'Kruisverwijzingen konden niet worden geladen.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SiteButton(label: 'Opnieuw proberen', onPressed: onRetry),
      ],
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution(this.attribution);

  final String attribution;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    if (attribution.isEmpty) return const SizedBox.shrink();
    // Rendered exactly as the server sent it. The CC BY credit is part of the
    // payload precisely so it is never retyped, drifted or shortened here.
    return Text(attribution, style: AppTheme.bodyMuted.copyWith(fontSize: 11));
  }
}

/// One reference. Tapping opens the full preview and the "Ga naar tekst"
/// button; the reference alone is never enough to decide whether it is worth
/// following.
class _CrossRefRow extends ConsumerStatefulWidget {
  const _CrossRefRow({
    super.key,
    required this.versionId,
    required this.fromBook,
    required this.target,
    required this.showPreview,
    required this.isLast,
  });

  final String versionId;
  final String fromBook;
  final CrossRef target;
  final bool showPreview;
  final bool isLast;

  @override
  ConsumerState<_CrossRefRow> createState() => _CrossRefRowState();
}

class _CrossRefRowState extends ConsumerState<_CrossRefRow> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (!_open) return;
    ref.read(analyticsProvider).track(AnalyticsEvents.crossRefFollowed, {
      'surface': 'app_sheet',
      'action': 'preview',
      'testament': crossRefTestamentPair(widget.fromBook, widget.target.book),
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return RuleListTile(
      showRule: !widget.isLast,
      onTap: _toggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.target.label,
            style: AppTheme.caption.copyWith(
              color: AppTheme.teal,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.showPreview || _open) ...[
            const SizedBox(height: 4),
            _VersePreview(
              versionId: widget.versionId,
              target: widget.target,
              maxLines: _open ? null : 2,
            ),
          ],
          if (_open) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(widget.target),
                child: const Text('Ga naar tekst'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The target passage in the translation the reader is already using.
///
/// Read through [chapterContentProvider], so several references into the same
/// chapter share one request and one sqflite row, and a chapter that is
/// already on the device costs nothing at all. When it cannot be had — no
/// network and nothing cached — the row falls back to the reference label,
/// which still says where to look.
class _VersePreview extends ConsumerWidget {
  const _VersePreview({
    required this.versionId,
    required this.target,
    required this.maxLines,
  });

  final String versionId;
  final CrossRef target;
  final int? maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final async = ref.watch(
      chapterContentProvider(ChapterRef(versionId, target.book, target.chapter)),
    );

    return async.when(
      loading: () => const Skeleton(height: 12, width: 180),
      // Label only: an error row per reference would drown the list in noise
      // about a chapter the reader never asked to open.
      error: (_, __) => const SizedBox.shrink(),
      data: (content) {
        final text = _previewText(content);
        if (text.isEmpty) {
          return Text(
            'Dit vers ontbreekt in deze vertaling.',
            style: AppTheme.caption,
          );
        }
        return Text(
          text,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: AppTheme.bodyMuted,
        );
      },
    );
  }

  String _previewText(ChapterContent content) {
    final wanted = target.versesInStartChapter().toSet();
    final parts = [
      for (final verse in content.verses)
        if (wanted.contains(verse.number)) verse.text.trim(),
    ]..removeWhere((t) => t.isEmpty);
    if (parts.isEmpty) return '';
    final joined = parts.join(' ');
    // A cross-chapter range keeps reading past what the preview shows.
    return target.endChapter != null ? '$joined …' : joined;
  }
}
