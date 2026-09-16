import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/permission_moment.dart';
import '../../../core/notifications/retention_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/lazy_scroll.dart';
import '../../../core/ui/skeleton.dart';
import '../../commentary/present/commentary_jump.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../notes/data/notes_repository.dart';
import '../../notes/domain/note_models.dart';
import '../../notes/present/notes_providers.dart';
import '../../notes/present/verse_action_sheet.dart';
import '../../onboarding/present/tour_controller.dart';
import '../../settings/data/reading_settings.dart';
import '../../study/domain/chapter_study_models.dart';
import '../domain/bible_models.dart';
import '../domain/version_catalog.dart';
import 'bible_providers.dart';
import 'chapter_marks_sheet.dart';
import 'offline_library_sheet.dart';
import 'reader_chrome.dart';
import 'reader_header.dart';
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
  const ReadScreen({super.key, this.embedded = false});

  /// True when mounted inside `/studie`, where the Bijbel/Studie switch in
  /// the header only flips panes instead of navigating.
  final bool embedded;

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

  /// True between [_scrollToPendingVerse] accepting an anchor and the frame in
  /// which it clears it, so the anchor is acted on once however many times
  /// build runs in between.
  bool _consumingAnchor = false;

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
      _publishTopVerse(metrics.pixels);
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

  /// Tells [readerTopVerseProvider] which verse is at the top of the text, so
  /// switching to Studie can line the commentary up with it. Runs when a
  /// scroll comes to rest, never per frame.
  void _publishTopVerse(double pixels) {
    final location = ref.read(readerLocationProvider);
    final locationKey =
        '${location.versionId}/${location.book}/${location.chapter}';
    if (_verseKeysFor != locationKey) return;

    final numbers = _verseKeys.keys.toList()..sort();
    for (final number in numbers) {
      final box = _verseKeys[number]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final top = viewport.getOffsetToReveal(box, 0).offset;
      // The first verse with more than a sliver of it still below the top edge.
      if (top + box.size.height > pixels + 12) {
        ref
            .read(readerTopVerseProvider.notifier)
            .set(ChapterVerse(location.book, location.chapter, number));
        return;
      }
    }
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

      // A recorded chapter read is a "completion" for retention purposes
      // (RETENTION_PLAN §2) - mirror it locally and re-derive the ladder so a
      // reminder for today is cancelled.
      unawaited(
        ref.read(retentionStoreProvider.notifier).markCompleted().then(
          (_) {
            if (!mounted) return;
            ref.invalidate(notificationRecomputeProvider);
            // The reader who never opens a study still earns the ask here
            // (`AVATAR_NOTIFICATIONS_PLAN.md` §7). Both moments are no-ops
            // until they are earned, and the ask is only ever spent once.
            unawaited(maybeAskAfterReading(context, ref));
          },
          onError: (_) {},
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
    // Called from inside build, and the anchor is watched there, so a second
    // build before the frame ends would start this over.
    if (_consumingAnchor) return;
    _consumingAnchor = true;

    final key = '${location.versionId}/${location.book}/${location.chapter}';
    _restoredFor = key;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Cleared here rather than above: this runs during build, where writing
      // to a provider this widget also watches is a modify-during-build and
      // Riverpod throws. The frame has ended by the time this fires.
      _consumingAnchor = false;
      if (!mounted) return;
      ref.read(pendingVerseAnchorProvider.notifier).set(null);
      final index = chapter.verses.indexWhere((v) => v.number == verseNumber);
      // `ensureVisible` alone needs the verse's row to be built, and the list
      // only builds rows near the viewport - so a far verse (Psalm 119:150
      // from the top) used to find no context and silently go nowhere.
      final landed = await scrollToLazyItem(
        controller: _scrollController,
        index: index,
        itemCount: chapter.verses.length,
        contextFor: (i) =>
            _verseKeys[chapter.verses[i].number]?.currentContext,
        alignment: 0.2,
        animate: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
        duration: const Duration(milliseconds: 420),
      );
      if (!mounted || !landed) return;
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
    // up under the home indicator. Read from the view, not the context: the
    // shell Scaffold has a bottomNavigationBar, so it strips the bottom padding
    // from its body even while that bar is collapsed - the context says 0 and
    // on Android 15+ edge-to-edge the nav row sat under the system buttons.
    final bottomInset = MediaQueryData.fromView(View.of(context)).padding.bottom;
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
                    child: _ReaderBar(location: location, embedded: widget.embedded),
                  ),
                  RuleLine(color: AppTheme.rule),
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
                      // Watched, not read: the chapter-marks sheet sets this
                      // while this same screen is already on the target
                      // chapter, so a rebuild has to come from the provider
                      // itself rather than from a fresh navigation.
                      if (ref.watch(pendingVerseAnchorProvider) != null) {
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
    await showVerseActionSheet(
      context: context,
      ref: ref,
      chapter: chapter,
      verse: verse,
      // Inside `/studie` the sheet only flips the pane; the standalone reader
      // has no commentary beside it and has to go there.
      onOpenCommentary: widget.embedded ? null : () => context.push('/study'),
    );
  }
}

/// The reader header: where you are and which pane, then the translation and
/// the four reading tools.
///
/// The tool order is the one the design fixed - zoeken, weergave, offline,
/// meer - and it is deliberately not the order the buttons grew in. Choosing
/// a translation moved from a fifth tool into the pill on the left, and the
/// chapter's note and highlight counts moved behind "meer".
class _ReaderBar extends ConsumerWidget {
  const _ReaderBar({required this.location, required this.embedded});

  final ReaderLocation location;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final versions = ref.watch(bibleVersionsProvider).value ?? const <BibleSource>[];
    final version = versions.where((v) => v.id == location.versionId).firstOrNull;

    // A translation can leave the app between releases - Luther 1912 was
    // dropped from the mobile allowlist - and the id the reader last used is
    // stored on the device. Without this, such a device opens on "Niet
    // beschikbaar in de app" every launch and stays there until the reader
    // works out that the answer is hidden behind the translation pill. Falling
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

    final versionName = version?.name ?? location.versionId;

    return ColoredBox(
      color: AppTheme.paperRaised,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, embedded ? 0 : 6, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Inside `/studie` the screen above owns this row for both panes.
            // Standalone `/read` IS the bible, so it never reads
            // `studyPaneProvider` here - see ReaderTitleBar.embedded.
            if (!embedded)
              const ReaderTitleBar(showMaterials: false, embedded: false),
            // 10 above and 9 below a 34px tool box. The row is 44 tall so each
            // tool gets a full 44px of tap height; the padding gives the
            // difference back.
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 4),
              child: SizedBox(
                height: _ToolButton.tapHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _VersionPill(
                          code: VersionCatalog.shortCodeFor(
                            id: location.versionId,
                            name: versionName,
                          ),
                          name: versionName,
                          onTap: () => showVersionPickerSheet(context, ref),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ToolButton(
                      icon: Icons.search,
                      tooltip: 'Zoeken in de Bijbel',
                      onTap: () => context.push(
                        '/search?book=${Uri.encodeComponent(location.book)}',
                      ),
                    ),
                    _ToolButton(
                      glyph: 'Aa',
                      tooltip: 'Weergave',
                      onTap: () => showReaderSettingsSheet(context, ref),
                    ),
                    if (canStudyChapter(location.book))
                      _ToolButton(
                        icon: Icons.school_outlined,
                        tooltip: 'Bestudeer dit hoofdstuk',
                        onTap: () => context.push(
                          chapterStudyRoute(location.book, location.chapter),
                        ),
                      ),
                    _OfflineButton(location: location),
                    _MoreButton(location: location),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active translation as a rounded pill: code, full name, chevron.
///
/// The code never shrinks - it is what a reader scans for - so only the name
/// gives way, with an ellipsis, when the row runs out of width.
class _VersionPill extends StatelessWidget {
  const _VersionPill({
    required this.code,
    required this.name,
    required this.onTap,
  });

  final String code;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    return Semantics(
      button: true,
      label: 'Vertaling: $name. Vertaling kiezen',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // The pill is 30 tall; the gesture area takes the row's full 44.
        child: SizedBox(
          height: _ToolButton.tapHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 30,
              padding: const EdgeInsets.fromLTRB(12, 0, 9, 0),
              decoration: BoxDecoration(
                color: AppTheme.paperRaised,
                border: Border.all(color: AppTheme.ruleStrong),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      height: 1.2,
                      color: AppTheme.tealStrong,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.sansFontName,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_down, size: 12, color: AppTheme.inkMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One 34x34 tool in the header row, on a 36px pitch (34 plus the 2px gap).
///
/// Not an [IconButton]: that one insists on 48x48 of layout, which would push
/// the four boxes apart. The tap area is the whole slot - 36 wide, 44 tall -
/// so there is no dead strip between neighbours; it cannot be wider than the
/// pitch without two buttons claiming the same point.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    this.icon,
    this.glyph,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  }) : assert(icon != null || glyph != null);

  static const double tapHeight = 44;

  final IconData? icon;

  /// Drawn as text instead of [icon] - the "Aa" of weergave, which no Material
  /// icon matches.
  final String? glyph;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final color = active ? AppTheme.teal : AppTheme.inkSoft;
    final label = glyph;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: _ToolSlot(
            active: active,
            child: label != null
                ? Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: AppTheme.sansFontName,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      height: 1,
                      color: color,
                    ),
                  )
                : Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}

/// The 36x44 slot a tool sits in, its 34x34 box flush right so the last box
/// lines up with the header's 16px edge and every gap is exactly 2.
class _ToolSlot extends StatelessWidget {
  const _ToolSlot({required this.child, this.active = false});

  final Widget child;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: _ToolButton.tapHeight,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppTheme.tealWash : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The reader's way into "Offline lezen".
///
/// The download used to live only inside the book picker's expanded chapter
/// grid, three taps deep and below the fold - which is why offline reading
/// could look unimplemented to someone who had paid for it. It sits in the
/// header tool row instead, and its icon reports the current book's real
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

    return _ToolButton(
      icon: complete ? Icons.offline_pin : Icons.download_outlined,
      tooltip: complete
          ? '${location.book} is offline beschikbaar'
          : 'Offline lezen',
      active: complete,
      onTap: () => showOfflineLibrarySheet(context),
    );
  }
}

/// "Meer": what the reader already has in this chapter.
///
/// Counts come from the notes and highlights lists the app loads anyway - see
/// [chapterMarkCountsProvider] - and both always show, zeros included. Both
/// entries open [showChapterMarksSheet], the chapter's one list of notes and
/// highlights. A plain [PopupMenuButton] until the menu gets its own design.
class _MoreButton extends ConsumerWidget {
  const _MoreButton({required this.location});

  final ReaderLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final counts = ref.watch(
      chapterMarkCountsProvider(ChapterKey(location.book, location.chapter)),
    );

    return PopupMenuButton<_MarksEntry>(
      tooltip: 'Meer',
      color: AppTheme.surface,
      onSelected: (_) => showChapterMarksSheet(
        context,
        ref,
        book: location.book,
        chapter: location.chapter,
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _MarksEntry.notes,
          child: Text(_plural(counts.notes, 'notitie', 'notities')),
        ),
        PopupMenuItem(
          value: _MarksEntry.highlights,
          child: Text(_plural(counts.highlights, 'markering', 'markeringen')),
        ),
      ],
      child: _ToolSlot(
        child: Icon(Icons.more_vert, size: 19, color: AppTheme.inkSoft),
      ),
    );
  }

  static String _plural(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';
}

enum _MarksEntry { notes, highlights }

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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
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
        // The end of the chapter is the natural moment to go deeper into it.
        if (canStudyChapter(chapter.book)) ...[
          // A plain OutlinedButton rather than SiteOutlineButton: its label
          // must be free to wrap at large text sizes instead of overflowing.
          OutlinedButton(
            onPressed: () => context.push(
              chapterStudyRoute(chapter.book, chapter.chapter),
            ),
            child: const Text('Bestudeer dit hoofdstuk', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
        ],
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
    final noteMarkers = ref.watch(
      chapterNoteMarkersProvider(ChapterKey(location.book, location.chapter)),
    );
    final hasNote = noteMarkers.contains(verse.number);

    final verseTextStyle = TextStyle(
      fontFamily: settings.fontFamily.fontName,
      fontSize: fontSize,
      height: settings.lineHeight.factor,
      letterSpacing: settings.letterSpacing.points,
      color: Theme.of(context).textTheme.bodyLarge?.color,
    );

    // Margin mark, not inline text: it used to sit inside the running text
    // right after the verse number, shifting the words after it. A
    // full-width Stack lets it float top-right of the first line instead,
    // like marginalia beside the text rather than part of it - the
    // SizedBox(width: infinity) is what makes that "full width" hold even on
    // a one-line verse, where Text.rich alone would only be as wide as the
    // words in it. Still tied to the verse-number setting, as it always was.
    final showNoteMarker = hasNote && settings.showVerseNumbers;
    final firstLineHeight = fontSize * settings.lineHeight.factor;

    Widget body = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: highlight == null
          ? null
          : BoxDecoration(
              color: highlight.fill(Theme.of(context).brightness),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                children: [
                  if (settings.showVerseNumbers) ...[
                    TextSpan(
                      text: '${verse.number}',
                      style: TextStyle(
                        fontFamily: AppTheme.sansFontName,
                        fontSize: fontSize * 0.62,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                    const TextSpan(text: ' '),
                  ],
                  TextSpan(text: verse.text),
                ],
              ),
              style: verseTextStyle,
            ),
          ),
          if (showNoteMarker)
            Positioned(
              top: 0,
              right: 0,
              child: SizedBox(
                height: firstLineHeight,
                child: Align(
                  alignment: Alignment.center,
                  child: Semantics(
                    button: true,
                    label: 'Notitie bij dit vers bekijken',
                    child: GestureDetector(
                      onTap: onLongPress,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.edit_note,
                          size: fontSize * 0.68,
                          color: AppTheme.teal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
      label: hasNote
          ? 'Vers ${verse.number}. ${verse.text} Heeft een notitie.'
          : 'Vers ${verse.number}. ${verse.text}',
      button: true,
      child: InkWell(onLongPress: onLongPress, child: body),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
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
    AppTheme.dependOn(context);
    final index = chapters.indexOf(current);
    final hasPrevious = index > 0;
    final hasNext = index >= 0 && index + 1 < chapters.length;
    final controller = ref.read(readerLocationProvider.notifier);

    // Deliberately not bold: this is a way out of the chapter, not the thing
    // the screen is for, and at 600 it competed with the text above it.
    TextStyle label(bool enabled) => AppTheme.caption.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: enabled ? AppTheme.teal : AppTheme.ruleStrong,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Flexible on all three: at the largest Dynamic Type setting the two
          // labels plus the counter are wider than a small phone.
          Flexible(
            child: Semantics(
              button: true,
              enabled: hasPrevious,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: hasPrevious
                    ? () => controller.previousChapter(chapters)
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: hasPrevious ? AppTheme.teal : AppTheme.ruleStrong,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Vorige',
                        style: label(hasPrevious),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Flexible(
            child: Text(
              '$current / ${chapters.isEmpty ? '–' : chapters.last}',
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                fontSize: 11,
                color: AppTheme.inkFaint,
              ),
            ),
          ),
          Flexible(
            child: Semantics(
              button: true,
              enabled: hasNext,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: hasNext ? () => controller.nextChapter(chapters) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Volgende',
                        style: label(hasNext),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: hasNext ? AppTheme.teal : AppTheme.ruleStrong,
                    ),
                  ],
                ),
              ),
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
