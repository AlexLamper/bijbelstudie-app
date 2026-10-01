import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/notifications/notification_scheduler.dart';
import '../../../core/notifications/retention_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../../bible/present/bible_providers.dart';
import '../../bible/present/chapter_end_detector.dart';
import '../../bible/present/read_screen.dart';
import '../../bible/present/reader_more_menu.dart';
import '../../commentary/present/commentary_pane.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/data/resume_link.dart' show resolveBookName;
import '../../notes/present/verse_action_sheet.dart';
import '../../settings/data/reading_settings.dart';
import '../data/bible_year_models.dart';
import '../domain/plan_book_codes.dart';
import '../domain/plan_calendar.dart';
import 'bible_year_parts.dart';
import 'bible_year_providers.dart';
import 'plan_widgets.dart';

/// The reader with the plan bar: walks the parts of one plan day. Full screen.
///
/// Each part opens in place - a chapter in the reader's own text view, the
/// uitleg in the commentary pane, the vraag on a quiet page - without moving
/// the normal reader's position. A chapter or the uitleg ticks once it is
/// scrolled to its end ([ChapterEndDetector]); the vraag as soon as it shows.
/// "Volgende" always moves on, read or not.
class PlanReaderScreen extends ConsumerStatefulWidget {
  const PlanReaderScreen({super.key, required this.day, this.part = 0});

  final int day;

  /// Index into `PlanCalendar.partsOf(day)`.
  final int part;

  @override
  ConsumerState<PlanReaderScreen> createState() => _PlanReaderScreenState();
}

class _PlanReaderScreenState extends ConsumerState<PlanReaderScreen> {
  late int _part = widget.part;

  /// How far the current part is scrolled, 0..1, for its segment.
  double _progress = 0;

  /// Study parts already sent this visit, so a rebuild never sends twice.
  final Set<String> _studySent = {};
  String? _recordedFor;

  String get _dayLabel => 'Bijbel in een jaar · dag ${widget.day}';

  void _goTo(int index) {
    setState(() {
      _part = index;
      _progress = 0;
    });
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(PlanRoutes.plan);
    }
  }

  /// Back to Vandaag; the ticks are already in the plan state, so it shows
  /// the day done without a refetch.
  void _finishDay() => context.go(PlanRoutes.plan);

  void _onProgress(double progress) {
    if (mounted && progress != _progress) setState(() => _progress = progress);
  }

  Future<void> _report(Future<String?> mutation) async {
    final error = await mutation;
    if (error == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(error)));
  }

  void _chapterRead(BibleYearRef chapter) => unawaited(
    _report(ref.read(bibleYearProvider.notifier).chapterReadToEnd(chapter.code, chapter.chapter)),
  );

  /// Marks a study part once per visit, after the frame (this runs from build).
  void _markStudyOnce(BibleYearStudyPart part) {
    final key = bibleYearStudyKey(widget.day, part);
    if (!_studySent.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_report(ref.read(bibleYearProvider.notifier).markStudy(widget.day, part)));
    });
  }

  /// Opening a chapter here counts for the reading stats like the normal
  /// reader's (`/last-read`, never a plan tick), once per chapter.
  void _recordChapterOpen(String versionId, String book, int chapter) {
    if (PreviewConfig.enabled) return;
    final key = '$versionId/$book/$chapter';
    if (_recordedFor == key) return;
    _recordedFor = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(dashboardRepositoryProvider).recordRead(version: versionId, book: book, chapter: chapter),
      );
      unawaited(
        ref.read(retentionStoreProvider.notifier).markCompleted().then((_) {
          if (!mounted) return;
          ref.read(notificationReschedulerProvider).requestReschedule(throttle: true);
        }, onError: (_) {}),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final calendarAsync = ref.watch(planCalendarProvider);
    final location = ref.watch(readerLocationProvider);
    final calendar = calendarAsync.value;

    if (calendar == null || !location.restored) {
      final loading = calendarAsync.isLoading || !location.restored;
      return _frame(
        loading
            ? const ReaderSkeleton()
            : _NoPlan(onBack: () => context.go(PlanRoutes.plan)),
      );
    }

    final parts = calendar.partsOf(widget.day);
    if (parts.isEmpty) return _frame(_NoPlan(onBack: () => context.go(PlanRoutes.plan)));

    final index = _part.clamp(0, parts.length - 1);
    final part = parts[index];
    final settings = ref.watch(readingSettingsProvider);
    final versionId = location.versionId;
    final book = planBookName(part.ref.code) ?? resolveBookName(part.ref.book) ?? part.ref.book;
    final partKey = '${widget.day}/$index';

    final Widget content;
    switch (part.kind) {
      case PlanPartKind.chapter:
        content = _chapterContent(part.ref, versionId, book, settings, partKey);
      case PlanPartKind.uitleg:
        content = _uitlegContent(versionId, book, part.ref.chapter, settings, partKey);
      case PlanPartKind.vraag:
        if (!part.done) _markStudyOnce(BibleYearStudyPart.vraag);
        content = _PlanQuestion(
          key: ValueKey(partKey),
          question: part.question ?? '',
          chapterLabel: chapterLabel(part.ref),
          settings: settings,
          onWriteNote: () => showAddNoteDialog(
            context: context,
            ref: ref,
            book: book,
            chapter: part.ref.chapter,
            verseText: part.question ?? '',
            translation: versionId,
          ),
        );
    }

    final isLast = index == parts.length - 1;
    final next = isLast ? null : parts[index + 1];
    final minutesLeft = calendar.minutesLeft(widget.day);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          PlanReaderBar(
            dayLabel: _dayLabel,
            title: switch (part.kind) {
              PlanPartKind.chapter => chapterLabel(part.ref),
              PlanPartKind.uitleg => 'Uitleg bij ${chapterLabel(part.ref)}',
              PlanPartKind.vraag => 'Vraag van vandaag',
            },
            fills: [
              for (var i = 0; i < parts.length; i++)
                parts[i].done ? 1.0 : (i == index ? _progress : 0.0),
            ],
            position: '${index + 1} van ${parts.length}',
            minutes: minutesLeft > 0 ? 'nog ± $minutesLeft min' : 'alles gelezen',
            onClose: _close,
            more: ReaderMoreButton(
              planMode: true,
              location: ReaderLocation(
                versionId: versionId,
                book: book,
                chapter: part.ref.chapter,
                restored: true,
              ),
              child: SizedBox.square(
                dimension: 44,
                child: Icon(Icons.more_horiz, size: 22, color: AppTheme.inkSoft),
              ),
            ),
          ),
          RuleLine(color: AppTheme.rule),
          Expanded(child: content),
          PlanReaderFooter(
            hint: switch (part.kind) {
              PlanPartKind.chapter => part.done
                  ? 'Dit hoofdstuk is afgevinkt'
                  : 'Lees tot het einde om dit hoofdstuk af te vinken',
              PlanPartKind.uitleg => part.done
                  ? 'De uitleg is afgevinkt'
                  : 'Lees tot het einde om de uitleg af te vinken',
              PlanPartKind.vraag => null,
            },
            label: next == null ? 'Dag afronden' : 'Volgende: ${_partName(next)}',
            onPressed: next == null ? _finishDay : () => _goTo(index + 1),
          ),
        ],
      ),
    );
  }

  Widget _frame(Widget child) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: Column(
      children: [
        PlanReaderBar(dayLabel: _dayLabel, title: '', fills: const [], onClose: _close),
        RuleLine(color: AppTheme.rule),
        Expanded(child: child),
      ],
    ),
  );

  Widget _chapterContent(
    BibleYearRef chapterRef,
    String versionId,
    String book,
    ReadingSettings settings,
    String partKey,
  ) {
    final chapterAsync = ref.watch(chapterContentProvider(ChapterRef(versionId, book, chapterRef.chapter)));
    return chapterAsync.when(
      loading: () => const ReaderSkeleton(),
      error: (error, _) => ReaderChapterError(error: error),
      data: (chapter) {
        _recordChapterOpen(versionId, book, chapterRef.chapter);
        return ChapterEndDetector(
          key: ValueKey(partKey),
          onEnd: () => _chapterRead(chapterRef),
          onProgress: _onProgress,
          child: ReaderChapterBody(
            chapter: chapter,
            book: book,
            chapterNumber: chapterRef.chapter,
            settings: settings,
            showStudyLink: false,
            onVerseLongPress: (verse) async {
              await HapticFeedback.selectionClick();
              if (!mounted) return;
              await showVerseActionSheet(context: context, ref: ref, chapter: chapter, verse: verse);
            },
          ),
        );
      },
    );
  }

  Widget _uitlegContent(
    String versionId,
    String book,
    int chapter,
    ReadingSettings settings,
    String partKey,
  ) {
    // The same family entry the pane watches, to know when its text is in:
    // the loading skeleton must not count as read.
    final commentary = ref.watch(
      commentaryChapterProvider(ChapterRef(settings.lastCommentaryId, book, chapter)),
    );
    // No uitleg in this source for this chapter: nothing to scroll, so it
    // cannot hold the day open.
    if (commentary.hasError && !commentary.isLoading) _markStudyOnce(BibleYearStudyPart.uitleg);
    return ChapterEndDetector(
      key: ValueKey(partKey),
      enabled: commentary.hasValue && !commentary.isLoading,
      onEnd: () => unawaited(
        _report(ref.read(bibleYearProvider.notifier).markStudy(widget.day, BibleYearStudyPart.uitleg)),
      ),
      onProgress: _onProgress,
      child: CommentaryPane(
        location: ReaderLocation(versionId: versionId, book: book, chapter: chapter, restored: true),
        settings: settings,
      ),
    );
  }
}

/// "Mattheüs 15", "uitleg", "vraag van vandaag" - after "Volgende: ".
String _partName(PlanPart part) => switch (part.kind) {
  PlanPartKind.chapter => chapterLabel(part.ref),
  PlanPartKind.uitleg => 'uitleg',
  PlanPartKind.vraag => 'vraag van vandaag',
};

/// The plan bar that stands in for the reader header: close, where you are
/// in the plan, one segment per part of the day, and the time left.
class PlanReaderBar extends StatelessWidget {
  const PlanReaderBar({
    super.key,
    required this.dayLabel,
    required this.title,
    required this.fills,
    this.position,
    this.minutes,
    required this.onClose,
    this.more,
  });

  final String dayLabel;
  final String title;

  /// One per part, 0..1.
  final List<double> fills;

  /// "2 van 4".
  final String? position;

  /// "nog ± 11 min".
  final String? minutes;
  final VoidCallback onClose;
  final Widget? more;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final meta = AppTheme.caption.copyWith(fontSize: 12, color: AppTheme.inkMuted);
    // Painted behind the status bar too, so the bar joins it seamlessly.
    return ColoredBox(
      color: AppTheme.paperRaised,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onClose,
                      tooltip: 'Terug naar Vandaag',
                      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.close, size: 22, color: AppTheme.inkSoft),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption.copyWith(fontSize: 11.5, color: AppTheme.inkMuted),
                          ),
                          if (title.isNotEmpty)
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyStrong.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ),
                    more ?? const SizedBox(width: 44),
                  ],
                ),
              ),
              if (fills.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    children: [
                      PlanPartSegments(fills: fills),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (position != null) Text(position!, style: meta),
                          const Spacer(),
                          if (minutes != null) Text(minutes!, style: meta),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thin bar per part: full when done, filled to the scroll position for
/// the current part, empty for what comes.
class PlanPartSegments extends StatelessWidget {
  const PlanPartSegments({super.key, required this.fills});

  final List<double> fills;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final done = fills.where((f) => f >= 1).length;
    return Semantics(
      label: '$done van ${fills.length} onderdelen klaar',
      child: Row(
        children: [
          for (var i = 0; i < fills.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                key: ValueKey('plan-segment-$i'),
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: AppTheme.rule),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fills[i].clamp(0.0, 1.0),
                        child: ColoredBox(color: AppTheme.teal),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Under the text: how a part gets ticked, and the way onward.
class PlanReaderFooter extends StatelessWidget {
  const PlanReaderFooter({super.key, this.hint, required this.label, required this.onPressed});

  final String? hint;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: AppTheme.rule)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hint != null) ...[
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(color: AppTheme.inkMuted),
              ),
              const SizedBox(height: 8),
            ],
            BibleYearPrimaryButton(label: label, height: 48, onPressed: onPressed),
          ],
        ),
      ),
    );
  }
}

/// The vraag: the question on its own, in the reading font, and a note.
class _PlanQuestion extends StatelessWidget {
  const _PlanQuestion({
    super.key,
    required this.question,
    required this.chapterLabel,
    required this.settings,
    required this.onWriteNote,
  });

  final String question;
  final String chapterLabel;
  final ReadingSettings settings;
  final VoidCallback onWriteNote;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      children: [
        const BibleYearEyebrow('Vraag van vandaag'),
        const SizedBox(height: 14),
        Text(
          question,
          style: TextStyle(
            fontFamily: settings.fontFamily.fontName,
            fontSize: settings.fontSize.points * 1.15 * textScale,
            height: settings.lineHeight.factor,
            letterSpacing: settings.letterSpacing.points,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 10),
        Text('Bij $chapterLabel', style: AppTheme.caption.copyWith(color: AppTheme.inkMuted)),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: BibleYearSecondaryButton(
            label: 'Schrijf een notitie',
            height: 44,
            onPressed: onWriteNote,
          ),
        ),
      ],
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: Icons.menu_book_outlined,
    title: 'Deze dag is niet te openen',
    description: 'Er loopt geen leesplan, of deze dag hoort er niet bij.',
    action: BibleYearPrimaryButton(label: 'Naar het leesplan', height: 44, onPressed: onBack),
  );
}
