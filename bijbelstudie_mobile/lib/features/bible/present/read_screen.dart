import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../notes/data/notes_repository.dart';
import '../../notes/domain/note_models.dart';
import '../../notes/present/notes_providers.dart';
import '../../notes/present/verse_action_sheet.dart';
import '../../onboarding/present/tour_controller.dart';
import '../../settings/data/reading_settings.dart';
import '../domain/bible_models.dart';
import 'bible_providers.dart';
import 'offline_library_sheet.dart';
import 'reader_chrome.dart';
import 'reader_settings_sheet.dart';
import 'source_picker_sheet.dart';

/// Set by [DailyVerseCard] immediately before it navigates here, naming the
/// verse this screen should scroll to and briefly highlight once its chapter
/// has rendered - instead of always landing at the top of the chapter.
///
/// Consumed (reset to null) the moment it is acted on, so a later chapter
/// change (next-chapter button, book picker) never re-triggers it.
final pendingVerseAnchorProvider =
    NotifierProvider<PendingVerseAnchor, int?>(PendingVerseAnchor.new);

class PendingVerseAnchor extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? verse) => state = verse;
}

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
  String? _recordedFor;

  /// One [GlobalKey] per verse number in the chapter currently on screen, so
  /// [_scrollToPendingVerse] can find its target's [BuildContext]. Cleared
  /// whenever the chapter changes - verse numbers repeat between chapters and
  /// a [GlobalKey] must never be attached to more than one live element.
  final Map<int, GlobalKey> _verseKeys = {};
  String? _verseKeysFor;

  /// The verse [_scrollToPendingVerse] most recently landed on, while its
  /// highlight is still fading. Null the rest of the time.
  int? _pulsingVerse;
  Timer? _pulseTimer;

  GlobalKey _verseKey(String locationKey, int number) {
    if (_verseKeysFor != locationKey) {
      _verseKeys.clear();
      _verseKeysFor = locationKey;
    }
    return _verseKeys.putIfAbsent(number, () => GlobalKey());
  }

  /// Scrolled distance in one direction since the chrome last changed. The
  /// bars only move once it passes [_chromeDeadzone], so a few pixels of
  /// jitter, a bounce, or a fingertip wobble cannot flicker them.
  double _scrollAccum = 0;
  static const double _chromeDeadzone = 28;

  /// Below this the chapter is barely taller than the screen and hiding the
  /// chrome would only cost the reader their navigation.
  static const double _chromeMinExtent = 160;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // The reader always opens with its chrome. Doing it on mount rather than
    // on teardown keeps the provider write out of the dispose path, where
    // notifying listeners would land in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setChromeVisible(true);
    });
  }

  @override
  void dispose() {
    _positionDebounce?.cancel();
    _pulseTimer?.cancel();
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

  void _setChromeVisible(bool visible) {
    _scrollAccum = 0;
    ref.read(readerChromeVisibleProvider.notifier).setVisible(visible);
  }

  /// Hides the top bar and the shell's tab bar while the reader scrolls down
  /// through the chapter, and gives them straight back on the way up.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    if (notification is ScrollEndNotification) {
      // Resting at either end of the chapter always shows the chrome: there is
      // nothing left to read into, and the user needs a way onward.
      if (metrics.pixels <= metrics.minScrollExtent + 4 ||
          metrics.pixels >= metrics.maxScrollExtent - 4) {
        _setChromeVisible(true);
      }
      return false;
    }

    if (notification is! ScrollUpdateNotification) return false;

    if (metrics.maxScrollExtent < _chromeMinExtent) {
      _setChromeVisible(true);
      return false;
    }

    // At the very top, or bouncing past either end: never a deliberate move.
    if (metrics.pixels <= metrics.minScrollExtent + 4) {
      _setChromeVisible(true);
      return false;
    }
    if (metrics.pixels > metrics.maxScrollExtent) return false;

    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    // A change of direction starts the deadzone over.
    if (delta.isNegative != _scrollAccum.isNegative) _scrollAccum = 0;
    _scrollAccum += delta;

    if (_scrollAccum > _chromeDeadzone) {
      _setChromeVisible(false);
    } else if (_scrollAccum < -_chromeDeadzone) {
      _setChromeVisible(true);
    }
    return false;
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

  /// Tells the server the chapter was opened, once per chapter.
  ///
  /// `/reading-history` only carries the scroll offset. `POST /last-read` is
  /// what fills `readChapters` (the 66-book map), writes a `ReadingSession`
  /// (the weekly bars) and moves `lastReadChapter` (the "ga verder" card), so
  /// without this call the whole dashboard stays empty for anyone who only
  /// ever uses the app. It deliberately does *not* touch the streak: that is
  /// earned by finishing the day's task, not by opening a chapter.
  ///
  /// It fires from the rendered chapter on purpose: this is what claims the
  /// chapter as read. Remembering the position is a separate job and belongs to
  /// [ReaderLocationController], which writes it the moment the user navigates,
  /// whether or not the text ever arrives.
  void _recordChapterOpen(ReaderLocation location) {
    // Preview runs on canned data; it must never write a chapter onto whatever
    // account happens to be signed in.
    if (PreviewConfig.enabled) return;

    final key = '${location.versionId}/${location.book}/${location.chapter}';
    if (_recordedFor == key) return;
    _recordedFor = key;

    // This runs from `build` and the call below touches a provider, so the work
    // waits until the frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      unawaited(
        ref
            .read(dashboardRepositoryProvider)
            .recordRead(
              version: location.versionId,
              book: location.book,
              chapter: location.chapter,
            ),
      );
    });
  }

  /// Puts the reader back where they stopped inside the chapter.
  ///
  /// [positions] is fetched over the network, so on the first frames after this
  /// screen mounts it is usually still in flight. Marking the chapter done then
  /// would spend the single attempt this mount gets and leave anyone who tabs
  /// away and back at the top of the chapter, so the key is only recorded once
  /// there is an answer to act on.
  void _restoreScrollIfNeeded(ReaderLocation location, List<ReadingPosition>? positions) {
    if (positions == null) return;

    final key = '${location.versionId}/${location.book}/${location.chapter}';
    if (_restoredFor == key) return;
    _restoredFor = key;

    final match = positions.where(
      (p) =>
          p.version == location.versionId &&
          p.book == location.book &&
          p.chapter == location.chapter,
    );
    final progress = match.isEmpty ? 0.0 : match.first.scrollProgress;
    if (progress <= 0.01) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(max * progress);
    });
  }

  /// Scrolls to the verse [pendingVerseAnchorProvider] names and briefly
  /// highlights it, once the chapter it belongs to has rendered - whether the
  /// chapter came from the sqflite cache or the network, since both arrive
  /// through the same `chapterAsync.data` branch this is called from.
  ///
  /// Takes priority over [_restoreScrollIfNeeded]: an explicit verse target and
  /// a remembered scroll fraction would otherwise fight over the same
  /// controller, so this also marks the chapter as already restored.
  void _scrollToPendingVerse(ReaderLocation location, ChapterContent chapter) {
    final verseNumber = ref.read(pendingVerseAnchorProvider);
    if (verseNumber == null) return;
    if (!chapter.verses.any((v) => v.number == verseNumber)) return;

    ref.read(pendingVerseAnchorProvider.notifier).set(null);
    final key = '${location.versionId}/${location.book}/${location.chapter}';
    _restoredFor = key;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final targetContext = _verseKeys[verseNumber]?.currentContext;
      if (targetContext == null) return;
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
      if (!mounted) return;
      setState(() => _pulsingVerse = verseNumber);
      _pulseTimer?.cancel();
      _pulseTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _pulsingVerse = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(readerLocationProvider);

    // Nothing is painted until the stored location is known. Opening on Genesis
    // 1 and swapping it out a moment later is the reset being fixed here, and a
    // faster version of it would still be one.
    if (!location.restored) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const SafeArea(child: ReaderSkeleton()),
      );
    }

    final settings = ref.watch(readingSettingsProvider);
    final chapterAsync = ref.watch(chapterContentProvider(location.ref));
    final chaptersAsync = ref.watch(
      bibleChaptersProvider(BookRef(location.versionId, location.book)),
    );
    // Watched, not read: the offset arrives after the chapter does, and
    // _restoreScrollIfNeeded needs a rebuild to act on it.
    final positions = ref.watch(readingHistoryProvider).value;

    final chromeVisible = ref.watch(readerChromeVisibleProvider);
    // The tab bar carries the bottom inset while it is there; once it slides
    // away the reader has to carry it itself, in step, or the chapter nav ends
    // up under the home indicator.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Reduced motion: the padding snaps, exactly as the bars themselves do.
    final chromeDuration = MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : ReaderChromeReveal.duration;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ReaderChromeReveal(
              visible: chromeVisible,
              axisAlignment: -1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TourAnchor(
                    id: TourAnchorIds.readerBar,
                    child: _ReaderBar(location: location),
                  ),
                  const RuleLine(),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: TourAnchor(
                  id: TourAnchorIds.readerText,
                  child: chapterAsync.when(
                    loading: () => const ReaderSkeleton(),
                    error: (error, _) => _ReaderError(error: error),
                    data: (chapter) {
                      _recordChapterOpen(location);
                      if (ref.read(pendingVerseAnchorProvider) != null) {
                        _scrollToPendingVerse(location, chapter);
                      } else {
                        _restoreScrollIfNeeded(location, positions);
                      }
                      final locationKey =
                          '${location.versionId}/${location.book}/${location.chapter}';
                      return _ChapterBody(
                        chapter: chapter,
                        settings: settings,
                        scrollController: _scrollController,
                        onVerseLongPress: (verse) => _openVerseActions(chapter, verse),
                        verseKey: (number) => _verseKey(locationKey, number),
                        pulsingVerse: _pulsingVerse,
                      );
                    },
                  ),
                ),
              ),
            ),
            const RuleLine(),
            AnimatedPadding(
              duration: chromeDuration,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: chromeVisible ? 0 : bottomInset),
              child: _ChapterNav(
                chapters: chaptersAsync.value ?? const [],
                current: location.chapter,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVerseActions(ChapterContent chapter, Verse verse) async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    await showVerseActionSheet(context: context, ref: ref, chapter: chapter, verse: verse);
  }
}

class _ReaderBar extends ConsumerWidget {
  const _ReaderBar({required this.location});

  final ReaderLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(bibleVersionsProvider).value ?? const <BibleSource>[];
    final version = versions.where((v) => v.id == location.versionId).firstOrNull;

    // A translation can leave the app between releases - Luther 1912 was
    // dropped from the mobile allowlist - and the id the reader last used is
    // stored on the device. Without this, such a device opens on "Niet
    // beschikbaar in de app" every launch and stays there until the reader
    // works out that the answer is hidden behind the translate icon. Falling
    // back to the first translation the server does offer costs nothing when
    // the stored one is still valid, because then `version` is not null.
    if (versions.isNotEmpty && version == null) {
      // Captured now: a post-frame callback must not reach back through `ref`,
      // which is unsafe the moment this widget is gone.
      final controller = ref.read(readerLocationProvider.notifier);
      final fallback = versions.first.id;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.applyPreferredVersion(fallback),
      );
    }

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
                        Icon(Icons.expand_more, size: 18, color: AppTheme.inkMuted),
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
            tooltip: 'Zoeken in de Bijbel',
            onPressed: () => context.push('/search?book=${Uri.encodeComponent(location.book)}'),
            icon: const Icon(Icons.search, size: 20),
          ),
          _OfflineButton(location: location),
          IconButton(
            tooltip: 'Weergave',
            onPressed: () => showReaderSettingsSheet(context, ref),
            icon: const Icon(Icons.text_fields, size: 20),
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

/// The reader's way into "Offline lezen".
///
/// The download used to live only inside the book picker's expanded chapter
/// grid, three taps deep and below the fold - which is why offline reading
/// could look unimplemented to someone who had paid for it. It sits next to the
/// translation switch instead, and its icon reports the current book's real
/// state: filled once every chapter of the book is genuinely on disk, outlined
/// otherwise. It never anticipates a download that has not finished.
class _OfflineButton extends ConsumerWidget {
  const _OfflineButton({required this.location});

  final ReaderLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref
        .watch(bookOfflineStatusProvider(BookRef(location.versionId, location.book)))
        .value;
    final complete = status?.isComplete ?? false;

    return IconButton(
      tooltip: complete ? '${location.book} is offline beschikbaar' : 'Offline lezen',
      onPressed: () => showOfflineLibrarySheet(context),
      icon: Icon(
        complete ? Icons.offline_pin : Icons.download_outlined,
        size: 20,
        color: complete ? AppTheme.lapis : null,
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
    required this.verseKey,
    required this.pulsingVerse,
  });

  final ChapterContent chapter;
  final ReadingSettings settings;
  final ScrollController scrollController;
  final void Function(Verse verse) onVerseLongPress;

  /// A stable [GlobalKey] for a verse number, used to scroll it into view.
  final GlobalKey Function(int verseNumber) verseKey;

  /// The verse [_scrollToPendingVerse] just landed on, or null.
  final int? pulsingVerse;

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
        if (chapter.fromCache) ...[const _OfflineNotice(), const SizedBox(height: 16)],
        for (final verse in chapter.verses)
          _VerseRow(
            key: verseKey(verse.number),
            verse: verse,
            fontSize: fontSize,
            settings: settings,
            onLongPress: () => onVerseLongPress(verse),
            pulse: verse.number == pulsingVerse,
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
    super.key,
    required this.verse,
    required this.fontSize,
    required this.settings,
    required this.onLongPress,
    this.pulse = false,
  });

  final Verse verse;
  final double fontSize;
  final ReadingSettings settings;
  final VoidCallback onLongPress;

  /// True for one verse, right after the reader has scrolled to it from the
  /// daily-verse card: draws a brief, fading tint so it also reads as the
  /// target rather than just where the scroll happened to stop.
  final bool pulse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlights = ref.watch(highlightIndexProvider);
    final location = ref.watch(readerLocationProvider);
    final key = VerseKey(location.book, location.chapter, verse.number);
    final highlight = highlights[key];

    Widget body = Container(
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
          letterSpacing: settings.letterSpacing.points,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );

    if (pulse) {
      // Independent of the persisted highlight above: this is a transient
      // "you are here" cue, not a saved marking, so it fades to nothing.
      body = TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOut,
        builder: (context, t, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.teal.withValues(alpha: 0.22 * t),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: child,
        ),
        child: body,
      );
    }

    return Semantics(
      label: 'Vers ${verse.number}. ${verse.text}',
      button: true,
      child: InkWell(onLongPress: onLongPress, child: body),
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
        Icon(Icons.cloud_off_outlined, size: 14, color: AppTheme.inkMuted),
        const SizedBox(width: 8),
        Text(
          'Offline gelezen uit je opgeslagen tekst',
          style: AppTheme.bodyMuted.copyWith(fontSize: 12),
        ),
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
    // Reaching this means the chapter is not on the device either - the
    // repository hands back cached text before it ever throws. So it points at
    // the fix rather than claiming the reader already has something offline.
    return const AppEmptyState(
      icon: Icons.wifi_off_outlined,
      title: 'Hoofdstuk niet geladen',
      description:
          'Dit hoofdstuk staat niet op je apparaat. Controleer je verbinding, of bewaar '
          'boeken vooraf via het downloadicoon bovenaan.',
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
