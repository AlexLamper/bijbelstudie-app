import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../dashboard/data/resume_link.dart';
import '../data/bible_year_models.dart';
import '../domain/bible_year_display.dart';
import 'bible_year_parts.dart';
import 'bible_year_providers.dart';

typedef BibleYearMarkRefs = Future<String?> Function(List<BibleYearChapterKey> refs, bool read);
typedef BibleYearMarkDay = Future<String?> Function(int day, bool read);

/// The "Vandaag" card of Bijbel in een jaar: today's portions with a tick box
/// and a reader link per chapter, "Gelezen" per portion, the share of the Bible
/// read, and - gently, never in red - how far behind the reader is with the two
/// ways back: "Bijlezen" (the backlog, oldest first) and "Schema verschuiven".
///
/// Presentational, like the website's `BibleYearTodayCard`: the data and the
/// callbacks come from the caller. It holds only its open/closed state and
/// whether a call is in flight. Each callback resolves to null on success or
/// the Dutch message to show.
class BibleYearTodayCard extends StatefulWidget {
  const BibleYearTodayCard({
    super.key,
    required this.today,
    this.compact = false,
    this.startDate,
    this.schedule,
    this.onMarkRefs,
    this.onMarkDay,
    this.onShift,
    this.onOpenChapter,
    this.onOpenPage,
  });

  final BibleYearToday today;

  /// Tighter, with "Naar je leesplan" at the foot (the Start tab).
  final bool compact;

  /// Enrollment start date, for the "Je begint op" line when dayNumber is 0.
  final String? startDate;

  /// When given, backlog days list their chapters as reader links.
  final BibleYearSchedule? schedule;
  final BibleYearMarkRefs? onMarkRefs;
  final BibleYearMarkDay? onMarkDay;
  final Future<String?> Function()? onShift;
  final void Function(BibleYearRef chapter)? onOpenChapter;

  /// "Naar je leesplan"; shown when given.
  final VoidCallback? onOpenPage;

  @override
  State<BibleYearTodayCard> createState() => _BibleYearTodayCardState();
}

class _BibleYearTodayCardState extends State<BibleYearTodayCard> {
  bool _backlogOpen = false;
  bool _pending = false;
  String? _error;

  Future<void> _run(Future<String?> Function() call) async {
    setState(() {
      _pending = true;
      _error = null;
    });
    final error = await call();
    if (!mounted) return;
    setState(() {
      _pending = false;
      _error = error;
    });
  }

  Future<void> _confirmShift() async {
    final today = widget.today;
    final ok = await showBibleYearConfirm(
      context,
      title: 'Schema verschuiven',
      confirmLabel: 'Verschuiven',
      content: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text:
                  'Je schema schuift ${daysWord(today.behindDays)} op, zodat je vandaag verder leest waar je gebleven bent. Je bent dan klaar op ',
            ),
            TextSpan(
              text: formatDutchDate(shiftedEndDate(today)),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
    if (ok && mounted && widget.onShift != null) await _run(widget.onShift!);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final today = widget.today;
    final compact = widget.compact;
    final notStarted = today.notStarted;
    final behind = behindLabel(today.behindDays);
    final ahead = aheadLabel(today.aheadDays);

    final heading = notStarted
        ? widget.startDate != null && widget.startDate!.isNotEmpty
              ? 'Je begint op ${formatDutchDate(widget.startDate!, weekday: true)}'
              : 'Je leesplan begint binnenkort'
        : dayOfPlanLabel(today.dayNumber, today.totalDays);

    Widget? subline;
    if (today.todayDone) {
      subline = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 15, color: AppTheme.teal),
          const SizedBox(width: 5),
          Text(
            'Vandaag gelezen',
            style: AppTheme.caption.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.tealStrong,
            ),
          ),
        ],
      );
    } else if (notStarted) {
      if (today.portions.isNotEmpty) {
        subline = Text(
          'Je mag alvast beginnen: vooruit lezen telt mee.',
          style: AppTheme.caption.copyWith(fontSize: 13),
        );
      }
    } else {
      subline = Text(minutesLabel(today.minutesEstimate), style: AppTheme.caption.copyWith(fontSize: 13));
    }

    return AppCard(
      padding: compact ? const EdgeInsets.all(16) : const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BibleYearEyebrow(compact ? 'Bijbel in een jaar' : 'Vandaag'),
                    const SizedBox(height: 4),
                    Semantics(
                      header: true,
                      child: Text(
                        heading,
                        style: AppTheme.displayTitle.copyWith(
                          fontSize: compact ? 17 : 20,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (subline != null) ...[const SizedBox(height: 3), subline],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatPercent(today.percentBible), style: AppTheme.statNumber.copyWith(fontSize: 18)),
                  Text('van de Bijbel', style: AppTheme.caption.copyWith(fontSize: 11.5, color: AppTheme.inkFaint)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          BibleYearProgressBar(percent: today.percentBible),
          if (today.portions.isNotEmpty) ...[
            SizedBox(height: compact ? 12 : 16),
            for (var i = 0; i < today.portions.length; i++) ...[
              if (i > 0) SizedBox(height: compact ? 8 : 12),
              _PortionRow(
                portion: today.portions[i],
                compact: compact,
                pending: _pending,
                onMarkRefs: widget.onMarkRefs == null
                    ? null
                    : (refs, read) => _run(() => widget.onMarkRefs!(refs, read)),
                onOpenChapter: widget.onOpenChapter,
              ),
            ],
          ],
          if (behind != null || ahead != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppTheme.paperSunken,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: behind != null ? _behindBox(behind) : Text(
                '$ahead. Mooi, dat telt allemaal mee.',
                style: AppTheme.bodyMuted.copyWith(fontSize: 13.5, color: AppTheme.inkSoft),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: AppTheme.caption.copyWith(fontSize: 13)),
            ),
          ],
          if (widget.onOpenPage != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpenPage,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Naar je leesplan',
                          style: AppTheme.pillLabel.copyWith(fontSize: 13, color: AppTheme.tealStrong),
                        ),
                        Icon(Icons.chevron_right, size: 16, color: AppTheme.tealStrong),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _behindBox(String behind) {
    final today = widget.today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$behind. Geen probleem: lees de gemiste dagen bij, of schuif je schema op.',
          style: AppTheme.bodyMuted.copyWith(fontSize: 13.5, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            BibleYearSecondaryButton(
              label: 'Bijlezen',
              onPressed: () => setState(() => _backlogOpen = !_backlogOpen),
              trailing: AnimatedRotation(
                turns: _backlogOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.expand_more, size: 16),
              ),
            ),
            if (widget.onShift != null)
              BibleYearSecondaryButton(
                label: 'Schema verschuiven',
                onPressed: _pending ? null : _confirmShift,
              ),
          ],
        ),
        if (_backlogOpen) ...[
          const SizedBox(height: 8),
          if (today.backlogDays.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Alles is bijgelezen.', style: AppTheme.caption.copyWith(fontSize: 13)),
            ),
          for (var i = 0; i < today.backlogDays.length; i++)
            _BacklogRow(
              day: today.backlogDays[i],
              first: i == 0,
              refs: [
                for (final portion in widget.schedule?.dayAt(today.backlogDays[i].day)?.portions ??
                    const <BibleYearPortion>[])
                  ...portion.refs,
              ],
              pending: _pending,
              onOpenChapter: widget.onOpenChapter,
              onMarkDay: widget.onMarkDay == null
                  ? null
                  : () => _run(() => widget.onMarkDay!(today.backlogDays[i].day, true)),
            ),
        ],
      ],
    );
  }
}

class _BacklogRow extends StatelessWidget {
  const _BacklogRow({
    required this.day,
    required this.first,
    required this.refs,
    required this.pending,
    this.onOpenChapter,
    this.onMarkDay,
  });

  final BibleYearBacklogDay day;
  final bool first;
  final List<BibleYearRef> refs;
  final bool pending;
  final void Function(BibleYearRef chapter)? onOpenChapter;
  final VoidCallback? onMarkDay;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: AppTheme.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dag ${day.day}',
                  style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600, color: AppTheme.inkFaint),
                ),
                Text(day.label, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5)),
                if (refs.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final ref in refs)
                        _ChapterLink(
                          chapter: ref,
                          muted: false,
                          onTap: onOpenChapter == null ? null : () => onOpenChapter!(ref),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onMarkDay != null) ...[
            const SizedBox(width: 12),
            BibleYearSecondaryButton(label: 'Gelezen', onPressed: pending ? null : onMarkDay),
          ],
        ],
      ),
    );
  }
}

class _PortionRow extends StatelessWidget {
  const _PortionRow({
    required this.portion,
    required this.compact,
    required this.pending,
    this.onMarkRefs,
    this.onOpenChapter,
  });

  final BibleYearPortion portion;
  final bool compact;
  final bool pending;
  final void Function(List<BibleYearChapterKey> refs, bool read)? onMarkRefs;
  final void Function(BibleYearRef chapter)? onOpenChapter;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final strand = portion.strand == 'all' ? null : kStrandLabel[portion.strand];
    final unread = [
      for (final r in portion.refs)
        if (!r.read) BibleYearChapterKey(r.code, r.chapter),
    ];

    return Container(
      padding: compact ? const EdgeInsets.fromLTRB(12, 10, 12, 8) : const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (strand != null)
                      Text(
                        strand.toUpperCase(),
                        style: AppTheme.overline.copyWith(fontSize: 10.5, letterSpacing: 0.6),
                      ),
                    Text(
                      portion.label,
                      style: AppTheme.displayBase.copyWith(fontSize: 14.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (portion.done)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 14, color: AppTheme.tealStrong),
                    const SizedBox(width: 4),
                    Text(
                      'Gelezen',
                      style: AppTheme.pillLabel.copyWith(color: AppTheme.tealStrong),
                    ),
                  ],
                )
              else if (onMarkRefs != null)
                BibleYearPrimaryButton(
                  label: 'Gelezen',
                  onPressed: pending || unread.isEmpty ? null : () => onMarkRefs!(unread, true),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 0,
            children: [
              for (final ref in portion.refs)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onMarkRefs != null)
                      BibleYearTickBox(
                        checked: ref.read,
                        label: '${chapterName(ref.book, ref.chapter)} gelezen',
                        onChanged: (next) =>
                            onMarkRefs!([BibleYearChapterKey(ref.code, ref.chapter)], next),
                      ),
                    _ChapterLink(
                      chapter: ref,
                      muted: ref.read,
                      onTap: onOpenChapter == null ? null : () => onOpenChapter!(ref),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChapterLink extends StatelessWidget {
  const _ChapterLink({required this.chapter, required this.muted, this.onTap});

  final BibleYearRef chapter;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final name = chapterName(chapter.book, chapter.chapter);
    final text = Text(
      name,
      style: AppTheme.bodyStrong.copyWith(
        fontSize: 13.5,
        color: muted ? AppTheme.inkMuted : AppTheme.tealStrong,
      ),
    );
    if (onTap == null) return text;
    return Semantics(
      button: true,
      label: 'Lees $name',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: text),
      ),
    );
  }
}

/// The Start tab's compact card: renders only while a plan is active, and
/// nothing at all otherwise (no teaser - the Studies tab carries the offer).
class BibleYearDashboardCard extends ConsumerStatefulWidget {
  const BibleYearDashboardCard({super.key, this.bottomSpacing = 16, this.planActive});

  /// The gap below the card, so the slot collapses fully when it is empty.
  final double bottomSpacing;

  /// What `/dashboard` said (`DashboardData.bibleYearActive`). False: no
  /// plan, so `/bible-year` is not asked at all - unless the plan state is
  /// already loaded (a plan just started on the Studies tab shows at once).
  /// Null (an older server): ask, as before.
  final bool? planActive;

  @override
  ConsumerState<BibleYearDashboardCard> createState() => _BibleYearDashboardCardState();
}

class _BibleYearDashboardCardState extends ConsumerState<BibleYearDashboardCard>
    with BibleYearRefreshOnMount {
  bool get _skip => widget.planActive == false && !ref.exists(bibleYearProvider);

  @override
  bool get bibleYearRefreshOnMount => !_skip;

  @override
  bool get bibleYearKnownActive => widget.planActive == true;

  @override
  Widget build(BuildContext context) {
    if (_skip) return const SizedBox.shrink();
    final state = ref.watch(bibleYearProvider).value;
    final today = state?.today;
    if (state == null || !state.isActive || today == null) return const SizedBox.shrink();
    final controller = ref.read(bibleYearProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSpacing),
      child: BibleYearTodayCard(
        today: today,
        compact: true,
        startDate: state.enrollment?.startDate,
        onMarkRefs: controller.markRefs,
        onMarkDay: controller.markDay,
        onShift: controller.shift,
        onOpenChapter: (chapter) => openBibleYearChapter(context, ref, chapter),
        onOpenPage: () => context.push(bibleYearPath),
      ),
    );
  }
}
