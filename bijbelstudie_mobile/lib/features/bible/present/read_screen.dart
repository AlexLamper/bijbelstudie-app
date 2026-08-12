import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../notes/data/notes_repository.dart';
import '../../notes/domain/note_models.dart';
import '../../notes/present/notes_providers.dart';
import '../../notes/present/verse_action_sheet.dart';
import '../../settings/data/reading_settings.dart';
import '../domain/bible_models.dart';
import 'bible_providers.dart';
import 'source_picker_sheet.dart';

/// The reader. Everything else in the app exists to get someone here.
class ReadScreen extends ConsumerStatefulWidget {
  const ReadScreen({super.key});

  @override
  ConsumerState<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends ConsumerState<ReadScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _positionDebounce;
  String? _restoredFor;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _positionDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// "Verder lezen" needs the scroll offset, but writing it on every frame
  /// would mean hundreds of requests per chapter, so it is debounced.
  void _onScroll() {
    _positionDebounce?.cancel();
    _positionDebounce = Timer(const Duration(seconds: 2), _persistPosition);
  }

  void _persistPosition() {
    if (!mounted || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final progress = max <= 0 ? 0.0 : (_scrollController.offset / max).clamp(0.0, 1.0);
    final location = ref.read(readerLocationProvider);

    unawaited(
      ref
          .read(notesRepositoryProvider)
          .recordReadingPosition(
            version: location.versionId,
            book: location.book,
            chapter: location.chapter,
            scrollProgress: progress,
          )
          .catchError((_) {
            // Offline: the position is not worth surfacing an error for.
          }),
    );
  }

  void _restoreScrollIfNeeded(ReaderLocation location) {
    final key = '${location.versionId}/${location.book}/${location.chapter}';
    if (_restoredFor == key) return;
    _restoredFor = key;

    final positions = ref.read(readingHistoryProvider).value;
    final match = positions?.where(
      (p) =>
          p.version == location.versionId &&
          p.book == location.book &&
          p.chapter == location.chapter,
    );
    final progress = match == null || match.isEmpty ? 0.0 : match.first.scrollProgress;
    if (progress <= 0.01) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(max * progress);
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(readerLocationProvider);
    final settings = ref.watch(readingSettingsProvider);
    final chapterAsync = ref.watch(chapterContentProvider(location.ref));
    final chaptersAsync = ref.watch(
      bibleChaptersProvider(BookRef(location.versionId, location.book)),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ReaderBar(location: location),
            const RuleLine(),
            Expanded(
              child: chapterAsync.when(
                loading: () => const AppLoader(),
                error: (error, _) => _ReaderError(error: error),
                data: (chapter) {
                  _restoreScrollIfNeeded(location);
                  return _ChapterBody(
                    chapter: chapter,
                    settings: settings,
                    scrollController: _scrollController,
                    onVerseLongPress: (verse) => _openVerseActions(chapter, verse),
                  );
                },
              ),
            ),
            const RuleLine(),
            _ChapterNav(
              chapters: chaptersAsync.value ?? const [],
              current: location.chapter,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVerseActions(ChapterContent chapter, Verse verse) async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    await showVerseActionSheet(
      context: context,
      ref: ref,
      chapter: chapter,
      verse: verse,
    );
  }
}

class _ReaderBar extends ConsumerWidget {
  const _ReaderBar({required this.location});

  final ReaderLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(bibleVersionsProvider).value ?? const <BibleSource>[];
    final version = versions
        .where((v) => v.id == location.versionId)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => showBookPickerSheet(context, ref),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${location.book} ${location.chapter}',
                            style: AppTheme.displaySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.expand_more, size: 18, color: AppTheme.inkMuted),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    version?.name ?? location.versionId,
                    style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Vertaling kiezen',
            onPressed: () => showVersionPickerSheet(context, ref),
            icon: const Icon(Icons.translate, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ChapterBody extends StatelessWidget {
  const _ChapterBody({
    required this.chapter,
    required this.settings,
    required this.scrollController,
    required this.onVerseLongPress,
  });

  final ChapterContent chapter;
  final ReadingSettings settings;
  final ScrollController scrollController;
  final void Function(Verse verse) onVerseLongPress;

  @override
  Widget build(BuildContext context) {
    // Dynamic Type: the OS text-size setting scales the reader on top of the
    // user's in-app choice, capped so the layout cannot break outright.
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final fontSize = settings.fontSize.points * textScale;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        if (chapter.fromCache) ...[
          const _OfflineNotice(),
          const SizedBox(height: 16),
        ],
        for (final verse in chapter.verses)
          _VerseRow(
            verse: verse,
            fontSize: fontSize,
            settings: settings,
            onLongPress: () => onVerseLongPress(verse),
          ),
        const SizedBox(height: 28),
        const RuleLine(),
        const SizedBox(height: 12),
        Text(chapter.attribution, style: AppTheme.bodyMuted.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _VerseRow extends ConsumerWidget {
  const _VerseRow({
    required this.verse,
    required this.fontSize,
    required this.settings,
    required this.onLongPress,
  });

  final Verse verse;
  final double fontSize;
  final ReadingSettings settings;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlights = ref.watch(highlightIndexProvider);
    final location = ref.watch(readerLocationProvider);
    final key = VerseKey(location.book, location.chapter, verse.number);
    final highlight = highlights[key];

    return Semantics(
      label: 'Vers ${verse.number}. ${verse.text}',
      button: true,
      child: InkWell(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          decoration: highlight == null
              ? null
              : BoxDecoration(
                  color: highlight.swatch,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
          child: Text.rich(
            TextSpan(
              children: [
                if (settings.showVerseNumbers)
                  TextSpan(
                    text: '${verse.number} ',
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: fontSize * 0.62,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkMuted,
                    ),
                  ),
                TextSpan(text: verse.text),
              ],
            ),
            style: TextStyle(
              fontFamily: settings.fontFamily.fontName,
              fontSize: fontSize,
              height: settings.lineHeight.factor,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    // Deliberately a quiet note, not an error: reading from cache is the
    // feature working, not failing.
    return Row(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 14, color: AppTheme.inkMuted),
        const SizedBox(width: 8),
        Text('Offline gelezen uit je opgeslagen tekst', style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
      ],
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    if (error is ContentNotLicensedException) {
      return const AppEmptyState(
        icon: Icons.gavel_outlined,
        title: 'Niet beschikbaar in de app',
        description:
            'Deze vertaling mag alleen op de website worden aangeboden. '
            'Kies een andere vertaling.',
      );
    }
    return const AppEmptyState(
      icon: Icons.wifi_off_outlined,
      title: 'Hoofdstuk niet geladen',
      description:
          'Controleer je verbinding. Hoofdstukken die je eerder las blijven offline beschikbaar.',
    );
  }
}

class _ChapterNav extends ConsumerWidget {
  const _ChapterNav({required this.chapters, required this.current});

  final List<int> chapters;
  final int current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = chapters.indexOf(current);
    final hasPrevious = index > 0;
    final hasNext = index >= 0 && index + 1 < chapters.length;
    final controller = ref.read(readerLocationProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Flexible on all three: at the largest Dynamic Type setting the two
          // labels plus the counter are wider than a small phone.
          Flexible(
            child: TextButton.icon(
              onPressed: hasPrevious ? () => controller.previousChapter(chapters) : null,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Vorige', overflow: TextOverflow.ellipsis),
            ),
          ),
          Flexible(
            child: Text(
              '$current / ${chapters.isEmpty ? '–' : chapters.last}',
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyMuted.copyWith(fontSize: 12),
            ),
          ),
          Flexible(
            child: TextButton.icon(
              onPressed: hasNext ? () => controller.nextChapter(chapters) : null,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Volgende', overflow: TextOverflow.ellipsis),
              iconAlignment: IconAlignment.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shares a whole chapter through the system share sheet.
Future<void> shareChapter(ChapterContent chapter) {
  return Share.share(chapter.shareText(), subject: chapter.reference);
}
