import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/lazy_scroll.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/domain/bible_models.dart';
import '../../bible/present/bible_providers.dart';
import '../../premium/present/upgrade_prompt.dart';
import '../../settings/data/reading_settings.dart';
import 'commentary_body.dart';
import 'commentary_jump.dart';
import 'verse_jump_sheet.dart';

/// The Commentaar tab of the study page, locked to whatever the reader shows.
///
/// Its source picker stands in for the site's commentary `<select>`; the choice
/// is persisted so reopening the app keeps the same commentator.
///
/// A chapter of Matthew Henry runs to many screens, so the pane can jump to a
/// verse: from the "Vers N" chip beside the source, and - when
/// [followReader] is set - from [pendingCommentaryVerseProvider], which the
/// verse action sheet and the Bijbel -> Studie switch write to.
class CommentaryPane extends ConsumerStatefulWidget {
  const CommentaryPane({
    super.key,
    required this.location,
    required this.settings,
    this.onSourceSelected,
    this.followReader = false,
  });

  final ReaderLocation location;
  final ReadingSettings settings;

  /// Fired after the choice is persisted, for callers that pin the source
  /// themselves - the lesson seeds it from the payload, so it has to hear
  /// about a pick to stop re-applying that seed.
  final ValueChanged<String>? onSourceSelected;

  /// True for the one pane that sits beside the reader in `/studie`. Only that
  /// pane consumes [pendingCommentaryVerseProvider]; the lesson and the
  /// standalone commentary screen would otherwise swallow a target meant for it.
  final bool followReader;

  @override
  ConsumerState<CommentaryPane> createState() => _CommentaryPaneState();
}

class _CommentaryPaneState extends ConsumerState<CommentaryPane> {
  final ScrollController _scrollController = ScrollController();

  /// One [GlobalKey] per entry's verse number, so a jump can find its row.
  /// Reset whenever the source or chapter changes: verse numbers repeat
  /// between chapters and a key must never sit on two live elements.
  final Map<int, GlobalKey> _entryKeys = {};
  String? _entryKeysFor;

  /// The chapter [_entries] was filtered from, so the filter runs once per
  /// chapter rather than on every build.
  ChapterContent? _entriesOf;
  List<Verse> _entries = const [];

  /// The entry at the top of the list once scrolling last came to rest. Null
  /// until then, which reads as the first entry.
  int? _topEntry;

  /// The entry a jump just landed on, while its label is still pulsing.
  int? _pulsingEntry;
  Timer? _pulseTimer;

  /// True between accepting a pending target and the post-frame callback that
  /// clears it, so a second build in between does not act on it twice.
  bool _consumingPending = false;

  static const double _listTopPadding = 16;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String get _chapterKey =>
      '${widget.settings.lastCommentaryId}/${widget.location.book}/${widget.location.chapter}';

  /// Forgets the keys, chip label and pulse of the previous chapter. Called at
  /// the top of every build, before anything reads them.
  void _resetForChapter() {
    final chapterKey = _chapterKey;
    if (_entryKeysFor == chapterKey) return;
    _entryKeys.clear();
    _entryKeysFor = chapterKey;
    _topEntry = null;
    _pulsingEntry = null;
    _pulseTimer?.cancel();
  }

  GlobalKey _keyFor(int verseNumber) =>
      _entryKeys.putIfAbsent(verseNumber, () => GlobalKey());

  List<Verse> _entriesFor(ChapterContent chapter) {
    if (!identical(chapter, _entriesOf)) {
      _entriesOf = chapter;
      // Empty entries were always skipped when rendering; filtering them out
      // up front keeps list index and entry index the same thing.
      _entries = [
        for (final verse in chapter.verses)
          if (verse.text.trim().isNotEmpty) verse,
      ];
    }
    return _entries;
  }

  @override
  Widget build(BuildContext context) {
    _resetForChapter();
    final commentaryId = widget.settings.lastCommentaryId;
    final chapterAsync = ref.watch(
      commentaryChapterProvider(
        ChapterRef(commentaryId, widget.location.book, widget.location.chapter),
      ),
    );
    final sources =
        ref.watch(commentarySourcesProvider).value ?? const <BibleSource>[];
    // Watched so a target set while this pane is already on screen (the
    // Bijbel/Studie switch) still gets a rebuild to act on.
    final pending = widget.followReader
        ? ref.watch(pendingCommentaryVerseProvider)
        : null;

    final chapter = chapterAsync.value;
    final entries = chapter == null ? const <Verse>[] : _entriesFor(chapter);
    if (chapterAsync.hasValue && chapter != null && pending != null) {
      _schedulePendingJump(entries);
    }

    final topEntry = entries.isEmpty
        ? null
        : (_topEntry != null && entries.any((e) => e.number == _topEntry))
        ? _topEntry
        : entries.first.number;

    return Column(
      children: [
        if (sources.isNotEmpty || topEntry != null)
          _SourceBar(
            sources: sources,
            selectedId: sources.any((s) => s.id == commentaryId)
                ? commentaryId
                : (sources.isEmpty ? commentaryId : sources.first.id),
            onSelected: (value) {
              ref
                  .read(readingSettingsProvider.notifier)
                  .setLastCommentary(value);
              widget.onSourceSelected?.call(value);
            },
            currentEntry: topEntry,
            onVerseChipTap: topEntry == null
                ? null
                : () => _openVerseSheet(entries, topEntry),
          ),
        Expanded(
          child: chapterAsync.when(
            loading: () => const ReaderSkeleton(),
            error: (error, _) => AppEmptyState(
              icon: error is ContentNotLicensedException
                  ? Icons.gavel_outlined
                  : Icons.menu_book_outlined,
              title: error is ContentNotLicensedException
                  ? 'Niet beschikbaar in de app'
                  : 'Geen commentaar gevonden',
              description: error is ContentNotLicensedException
                  ? 'Dit commentaar mag alleen op de website worden aangeboden.'
                  : 'Voor dit hoofdstuk is geen commentaar beschikbaar in deze bron.',
            ),
            data: (chapter) => _buildList(chapter, _entriesFor(chapter)),
          ),
        ),
      ],
    );
  }

  Widget _buildList(ChapterContent chapter, List<Verse> entries) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget entry(int index) {
      final verse = entries[index];
      return _CommentaryEntry(
        key: _keyFor(verse.number),
        entry: verse,
        settings: widget.settings,
        isLast: index == entries.length - 1,
        pulse: _pulsingEntry == verse.number,
        reduceMotion: reduceMotion,
      );
    }

    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chapter.locked) const _CommentaryPaywall(),
        const SizedBox(height: 20),
        const RuleLine(),
        const SizedBox(height: 12),
        Text(
          chapter.attribution,
          style: AppTheme.bodyMuted.copyWith(fontSize: 11),
        ),
      ],
    );

    // Locked: the free excerpt is a handful of entries under one fade, so it
    // stays a single item - every entry is built and a jump resolves at once.
    final itemCount = chapter.locked ? 2 : entries.length + 1;

    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _updateTopEntry(entries);
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, _listTopPadding, 20, 48),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == itemCount - 1) return footer;
          if (!chapter.locked) return entry(index);
          // Mirrors CommentaryComponent.tsx lines ~503-508: the server
          // already withholds everything past the free excerpt, so this
          // mask is cosmetic - it makes the truncation read as "the text
          // trails off" rather than "the text stops dead".
          return ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0.0, 0.82, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (var i = 0; i < entries.length; i++) entry(i)],
            ),
          );
        },
      ),
    );
  }

  void _schedulePendingJump(List<Verse> entries) {
    if (_consumingPending) return;
    _consumingPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Consumed here, not in build: writing a provider this widget watches
      // during its own build is a modify-during-build.
      _consumingPending = false;
      if (!mounted) return;
      final target = ref.read(pendingCommentaryVerseProvider);
      if (target == null) return;
      ref.read(pendingCommentaryVerseProvider.notifier).consume();
      // The location is the reader's, so a target for another chapter is
      // stale - left behind by a chapter change before it could be used.
      if (!target.sameChapter(widget.location.book, widget.location.chapter)) {
        return;
      }
      unawaited(_jumpToVerse(_entries, target.verse));
    });
  }

  /// Scrolls to the entry covering [verse] and pulses its label.
  Future<void> _jumpToVerse(List<Verse> entries, int verse) async {
    final index = commentaryEntryIndexFor([
      for (final e in entries) e.number,
    ], verse);
    if (index == null || !_scrollController.hasClients) return;
    final number = entries[index].number;
    // A pane that is not on screen (the other half of `/studie`) has its
    // tickers muted, and an animation there would never finish.
    final animate =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        TickerMode.of(context);

    final landed = await scrollToLazyItem(
      controller: _scrollController,
      index: index,
      itemCount: entries.length,
      contextFor: (i) => i < entries.length
          ? _entryKeys[entries[i].number]?.currentContext
          : null,
      leadingPadding: 12,
      animate: animate,
    );
    if (!mounted) return;
    if (!landed) {
      // Should not happen, but a pane that cannot find the entry must still
      // end up somewhere sensible rather than mid-chapter.
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      return;
    }
    _pulseTimer?.cancel();
    setState(() {
      _pulsingEntry = number;
      _topEntry = number;
    });
    _pulseTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _pulsingEntry = null);
    });
  }

  /// Which entry is at the top of the viewport, for the chip's label. Runs
  /// when a scroll comes to rest, not on every frame.
  void _updateTopEntry(List<Verse> entries) {
    if (!_scrollController.hasClients || entries.isEmpty) return;
    final pixels = _scrollController.position.pixels;
    int? top;
    for (final entry in entries) {
      final box = _entryKeys[entry.number]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final entryTop = viewport.getOffsetToReveal(box, 0).offset;
      // The first entry still showing more than a sliver below the top edge.
      if (entryTop + box.size.height > pixels + 48) {
        top = entry.number;
        break;
      }
    }
    if (top == null || top == _topEntry) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _topEntry = top);
      });
    } else {
      setState(() => _topEntry = top);
    }
  }

  Future<void> _openVerseSheet(List<Verse> entries, int currentEntry) async {
    final numbers = [for (final e in entries) e.number];
    // The Bible chapter knows how many verses there are; commentators often
    // stop short of the last one. Only used if it is already loaded - the
    // lesson's pane must not start a fetch just to size a grid.
    final bibleRef = widget.location.ref;
    var verseCount = numbers.isEmpty ? 0 : numbers.last;
    if (ref.exists(chapterContentProvider(bibleRef))) {
      final bible = ref.read(chapterContentProvider(bibleRef)).value;
      if (bible != null &&
          bible.book == widget.location.book &&
          bible.chapter == widget.location.chapter &&
          bible.verses.isNotEmpty) {
        verseCount = bible.verses.last.number > verseCount
            ? bible.verses.last.number
            : verseCount;
      }
    }

    final picked = await showVerseJumpSheet(
      context: context,
      entryNumbers: numbers,
      verseCount: verseCount,
      currentEntry: currentEntry,
    );
    if (picked == null || !mounted) return;
    await _jumpToVerse(_entries, picked);
  }
}

/// Which commentator is being read and where in the chapter, and the ways to
/// change either.
///
/// Was a `DropdownButtonFormField`: a Material outlined form field, with its
/// own border, its own floating-label metrics and a grey pop-up menu, sitting
/// on top of a page built out of rules and flat paper. It read as a control
/// borrowed from another app. This is the picker the reader already knows from
/// the Bijbel tab instead - a quiet line naming the current source, and a sheet
/// to change it - so the commentary pane reads as one surface again.
///
/// Two tap targets share the line: the source on the left, the "Vers N" chip
/// on the right.
class _SourceBar extends StatelessWidget {
  const _SourceBar({
    required this.sources,
    required this.selectedId,
    required this.onSelected,
    this.currentEntry,
    this.onVerseChipTap,
  });

  final List<BibleSource> sources;
  final String selectedId;
  final ValueChanged<String> onSelected;

  /// Verse number of the entry at the top of the list (0 is the introduction),
  /// or null when there is nothing to jump between.
  final int? currentEntry;
  final VoidCallback? onVerseChipTap;

  @override
  Widget build(BuildContext context) {
    final current =
        sources.where((source) => source.id == selectedId).firstOrNull ??
        sources.firstOrNull;
    final entry = currentEntry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: current == null
                      ? const SizedBox.shrink()
                      : Semantics(
                          button: sources.length > 1,
                          label: sources.length > 1
                              ? 'Commentaar: ${current.name}. Kies een andere bron'
                              : 'Commentaar: ${current.name}',
                          // Excluding the row's own semantics drops the
                          // InkWell's tap action too, so it is restated here.
                          onTap: sources.length < 2
                              ? null
                              : () => _openSheet(context, current.id),
                          excludeSemantics: true,
                          child: InkWell(
                            // One source is not a choice; the line then only
                            // says whose commentary this is.
                            onTap: sources.length < 2
                                ? null
                                : () => _openSheet(context, current.id),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 9, 8, 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppTheme.tealWash,
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusXs,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.menu_book_outlined,
                                      size: 13,
                                      color: AppTheme.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      current.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.pillLabel,
                                    ),
                                  ),
                                  if (sources.length > 1) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      'WISSEL',
                                      style: AppTheme.overline.copyWith(
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 14,
                                      color: AppTheme.inkFaint,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
                if (entry != null) ...[
                  VerticalDivider(width: 1, thickness: 1, color: AppTheme.rule),
                  Semantics(
                    button: true,
                    label: '${_entryLabel(entry)}. Ga naar een ander vers',
                    onTap: onVerseChipTap,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: onVerseChipTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 9, 16, 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_entryLabel(entry), style: AppTheme.pillLabel),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: 14,
                              color: AppTheme.inkFaint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const RuleLine(),
      ],
    );
  }

  static String _entryLabel(int number) =>
      number == 0 ? 'Inleiding' : 'Vers $number';

  Future<void> _openSheet(BuildContext context, String currentId) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      builder: (sheetContext) =>
          _SourceSheet(sources: sources, selectedId: currentId),
    );
    if (picked != null && picked != currentId) onSelected(picked);
  }
}

/// The source list, in the same sheet the translation picker uses.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.sources, required this.selectedId});

  final List<BibleSource> sources;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Eyebrow('Commentaar'),
              ),
            ),
            const RuleLine(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final source in sources)
                    RuleListTile(
                      onTap: () => Navigator.of(context).pop(source.id),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  source.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                if (source.attribution.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    source.attribution,
                                    style: AppTheme.bodyMuted.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (source.id == selectedId)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.check,
                                size: 18,
                                color: AppTheme.teal,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentaryEntry extends StatelessWidget {
  const _CommentaryEntry({
    super.key,
    required this.entry,
    required this.settings,
    required this.isLast,
    this.pulse = false,
    this.reduceMotion = false,
  });

  final Verse entry;
  final ReadingSettings settings;
  final bool isLast;

  /// True right after a jump landed here.
  final bool pulse;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    // Matthew Henry keys the chapter introduction as verse 0 - confirmed
    // against the live API. Labelling it "Vers 0" would be nonsense.
    final label = entry.number == 0 ? 'Inleiding' : 'Vers ${entry.number}';
    if (entry.text.trim().isEmpty) return const SizedBox.shrink();

    // `border-b border-gray-100 ... pb-6 last:border-0 mb-6 last:mb-0` on the
    // entry wrapper in `CommentaryComponent.tsx` (around line 519).
    return Container(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 20),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VerseLabel(label, pulse: pulse, reduceMotion: reduceMotion),
          const SizedBox(height: 10),
          CommentaryBody(text: entry.text, settings: settings),
        ],
      ),
    );
  }
}

/// The `Inleiding` / `Vers N` pill.
///
/// Mirrors the label span in `CommentaryComponent.tsx` (around lines 517-524):
/// `text-[11px] font-semibold tracking-wider uppercase`, teal on an eight
/// percent teal wash, `rounded-full`. The website only pills the HTML sources
/// and gives the plain-text ones a bare heading; the app pills both, because
/// the plain-text source is Matthew Henry - the one the reader spends nearly
/// all of their time in, and the one that most needs its entries to look like
/// entries rather than like one unbroken column of prose.
///
/// A heading for screen readers, so the entries can be skimmed by heading.
/// After a jump it briefly glows, so it reads as the target rather than just
/// where the scroll happened to stop; under reduced motion the glow is a
/// plain tint that is simply removed again.
class _VerseLabel extends StatelessWidget {
  const _VerseLabel(
    this.label, {
    this.pulse = false,
    this.reduceMotion = false,
  });

  final String label;
  final bool pulse;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);

    Widget pill(double glow) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Color.lerp(
          AppTheme.tealWash,
          AppTheme.teal.withValues(alpha: 0.32),
          glow,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        boxShadow: glow <= 0
            ? null
            : [
                BoxShadow(
                  color: AppTheme.teal.withValues(alpha: 0.35 * glow),
                  blurRadius: 10 * glow,
                  spreadRadius: 2 * glow,
                ),
              ],
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.overline.copyWith(
          fontSize: 10.5,
          letterSpacing: 0.9,
          color: AppTheme.tealStrong,
        ),
      ),
    );

    final Widget child;
    if (!pulse) {
      child = pill(0);
    } else if (reduceMotion) {
      child = pill(1);
    } else {
      child = TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 1300),
        curve: Curves.easeIn,
        builder: (context, t, _) => pill(t),
      );
    }

    return Semantics(header: true, child: child);
  }
}

/// The Grondtekst tab: the STEPBible Hebrew/Greek, word by word.
///
/// The server already truncates this chapter to the free allowance and
/// reports `locked` when it did (see `gateOriginal` in `lib/proContent.ts`),
/// so the pane never gates on the client - it renders whatever verses arrived
/// and, when locked, fades the tail and shows the upgrade prompt beneath it.
/// Mirrors how [CommentaryPane] above handles its own `locked` flag.
///
/// The CC BY 4.0 attribution at the foot is a licence condition, not a
/// footnote, so it renders even when the word list is short, including in
/// the free preview.
class OriginalTextPane extends ConsumerWidget {
  const OriginalTextPane({super.key, required this.location});

  final ReaderLocation location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final originalAsync = ref.watch(
      originalChapterProvider(
        ChapterRef('stepbible', location.book, location.chapter),
      ),
    );

    return originalAsync.when(
      loading: () => const ReaderSkeleton(),
      error: (_, __) => const AppEmptyState(
        icon: Icons.translate_outlined,
        title: 'Geen grondtekst',
        description:
            'De Hebreeuwse/Griekse tekst is voor dit hoofdstuk niet beschikbaar.',
      ),
      data: (original) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [
          // Mirrors CommentaryPane above: the server already withholds
          // everything past the free preview, so this mask is cosmetic - it
          // makes the truncation read as "the text trails off" rather than
          // "the text stops dead".
          if (original.locked)
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0.0, 0.82, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final verse in original.verses)
                    _OriginalVerseBlock(verse: verse),
                ],
              ),
            )
          else
            for (final verse in original.verses)
              _OriginalVerseBlock(verse: verse),
          if (original.locked) const _OriginalTextPaywall(),
          const SizedBox(height: 20),
          const RuleLine(),
          const SizedBox(height: 12),
          Text(
            original.attribution,
            style: AppTheme.bodyMuted.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _OriginalVerseBlock extends StatelessWidget {
  const _OriginalVerseBlock({required this.verse});

  final OriginalVerse verse;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Vers ${verse.number}'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final word in verse.words)
                Semantics(
                  label:
                      '${word.transliteration}, ${word.gloss}, Strong ${word.strongs}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        word.original,
                        style: const TextStyle(fontSize: 20, height: 1.4),
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        word.transliteration,
                        style: AppTheme.bodyMuted.copyWith(fontSize: 11),
                      ),
                      if (word.gloss.isNotEmpty)
                        Text(
                          word.gloss,
                          style: AppTheme.caption.copyWith(fontSize: 11),
                        ),
                      if (word.strongs.isNotEmpty)
                        Text(
                          word.strongs,
                          style: AppTheme.bodyMuted.copyWith(fontSize: 10),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown under the preview when the server withheld the rest of the chapter.
///
/// The entries above are real commentary, not a teaser: the free allowance is
/// the opening of the chapter, so the reader can see what they would be buying
/// before being asked to buy it.
///
/// Mirrors how `CommentaryComponent.tsx` invokes `UpgradePrompt` (around
/// lines 536-546): same title, body and CTA copy, same `commentary` surface.
class _CommentaryPaywall extends StatelessWidget {
  const _CommentaryPaywall();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: UpgradePrompt(
        surface: 'commentary',
        title: 'Lees het volledige commentaar',
        body:
            'Je leest nu het begin. Met Pro lees je elk commentaar bij elk '
            'hoofdstuk volledig.',
        cta: 'Verder lezen met Pro',
      ),
    );
  }
}

/// Shown under the preview when the server withheld the rest of the chapter.
///
/// The verses above are the real grondtekst, not a teaser: the free allowance
/// is the opening of the chapter, so the reader sees what they would be
/// buying before being asked to buy it.
///
/// Mirrors `_CommentaryPaywall` above and how `OriginalText.tsx` invokes
/// `UpgradePrompt`, on the same `original_text` surface.
class _OriginalTextPaywall extends StatelessWidget {
  const _OriginalTextPaywall();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: UpgradePrompt(
        surface: 'original_text',
        title: 'Bekijk de volledige grondtekst',
        body:
            'Je ziet nu het begin van het hoofdstuk. Met Pro open je het hele '
            'hoofdstuk woord voor woord, in het Hebreeuws en Grieks, met '
            'transliteratie en Strong-nummers.',
        cta: 'Verder lezen met Pro',
      ),
    );
  }
}
