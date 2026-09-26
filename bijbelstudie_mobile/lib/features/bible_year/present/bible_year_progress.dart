import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/bible_year_models.dart';
import '../domain/bible_year_display.dart';
import 'bible_year_parts.dart';

/// The plan at a glance: share read, chapters, plan and order, start and end,
/// and "Stoppen met dit leesplan" behind a confirm.
class BibleYearProgressCard extends StatefulWidget {
  const BibleYearProgressCard({
    super.key,
    required this.enrollment,
    this.catalogue = const [],
    this.tracks = const [],
    this.onStop,
  });

  final BibleYearEnrollment enrollment;
  final List<BibleYearCatalogueEntry> catalogue;
  final List<BibleYearTrackEntry> tracks;

  /// Resolves to null on success, else the message to show. Omit to hide.
  final Future<String?> Function()? onStop;

  @override
  State<BibleYearProgressCard> createState() => _BibleYearProgressCardState();
}

class _BibleYearProgressCardState extends State<BibleYearProgressCard> {
  bool _pending = false;
  String? _error;

  Future<void> _confirmStop() async {
    final ok = await showBibleYearConfirm(
      context,
      title: 'Stoppen met dit leesplan',
      confirmLabel: 'Stoppen',
      content: const Text(
        'Je leesplan stopt. Wat je gelezen hebt blijft bewaard, ook in je voortgang. Je kunt later altijd opnieuw beginnen.',
      ),
    );
    if (!ok || !mounted || widget.onStop == null) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    final error = await widget.onStop!();
    if (!mounted) return;
    setState(() {
      _pending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final e = widget.enrollment;

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: AppTheme.bodyMuted.copyWith(fontSize: 13.5))),
          Expanded(child: Text(value, style: AppTheme.bodyStrong.copyWith(fontSize: 13.5))),
        ],
      ),
    );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Je voortgang', style: AppTheme.displayTitle),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatPercent(e.percentBible), style: AppTheme.statNumber.copyWith(fontSize: 25)),
              const SizedBox(width: 8),
              Text('van de Bijbel', style: AppTheme.caption.copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          BibleYearProgressBar(percent: e.percentBible),
          const SizedBox(height: 8),
          Text(
            '${e.chaptersRead} van $kBibleChapterCount hoofdstukken',
            style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 14),
          row('Leesplan', '${planLabel(e.planKey, widget.catalogue)} · ${trackLabel(e.track, widget.tracks)}'),
          row('Begonnen', formatDutchDate(e.startDate)),
          if (e.isActive) row('Klaar op', formatDutchDate(e.expectedEndDate)),
          if (widget.onStop != null && e.isActive) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _pending ? null : _confirmStop,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.inkMuted,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: AppTheme.pillLabel.copyWith(fontSize: 13),
                ),
                child: const Text('Stoppen met dit leesplan'),
              ),
            ),
          ],
          if (_error != null) Text(_error!, style: AppTheme.caption.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

/// The finish: the whole Bible read, and the way to go round again.
class BibleYearCompleteCard extends StatelessWidget {
  const BibleYearCompleteCard({super.key, required this.enrollment, required this.onRestart});

  final BibleYearEnrollment enrollment;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final completed = enrollment.completedAt;
    final on = completed != null && completed.length >= 10
        ? ', afgerond op ${formatDutchDate(completed.substring(0, 10))}'
        : '';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BibleYearEyebrow('Bijbel in een jaar'),
          const SizedBox(height: 4),
          Semantics(
            header: true,
            child: Text(
              'Je hebt de hele Bijbel gelezen',
              style: AppTheme.displayTitle.copyWith(fontSize: 22, letterSpacing: -0.4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Van Genesis tot Openbaring, ${enrollment.chaptersRead} hoofdstukken$on. Wil je nog een keer? Kies opnieuw een duur en een volgorde.',
            style: AppTheme.bodyMuted.copyWith(fontSize: 14.5, height: 1.7, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 14),
          const BibleYearProgressBar(percent: 100),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: BibleYearPrimaryButton(label: 'Opnieuw beginnen', height: 44, onPressed: onRestart),
          ),
        ],
      ),
    );
  }
}

/// Collapsible list of the days after today, with their dates.
class BibleYearScheduleOverview extends StatefulWidget {
  const BibleYearScheduleOverview({
    super.key,
    required this.schedule,
    required this.fromDay,
    required this.startDate,
    required this.shiftDays,
    this.count = 14,
    this.initiallyOpen = false,
  });

  final BibleYearSchedule schedule;

  /// Today's day number; the list starts the day after.
  final int fromDay;
  final String startDate;
  final int shiftDays;
  final int count;
  final bool initiallyOpen;

  @override
  State<BibleYearScheduleOverview> createState() => _BibleYearScheduleOverviewState();
}

class _BibleYearScheduleOverviewState extends State<BibleYearScheduleOverview> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final days = upcomingDays(widget.schedule, widget.fromDay, widget.count);
    if (days.isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                child: Row(
                  children: [
                    Expanded(child: Text('Komende dagen', style: AppTheme.displayTitle.copyWith(fontSize: 15))),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.expand_more, size: 20, color: AppTheme.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            for (final day in days)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.rule))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 108,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dag ${day.day}',
                            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600, color: AppTheme.inkFaint),
                          ),
                          Text(
                            formatDutchDate(
                              scheduleDayDate(widget.startDate, widget.shiftDays, day.day),
                              weekday: true,
                            ),
                            style: AppTheme.caption,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scheduleDaySummary(day),
                        style: AppTheme.bodyMuted.copyWith(fontSize: 13.5, color: AppTheme.inkSoft),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${day.minutes} min', style: AppTheme.caption.copyWith(color: AppTheme.inkFaint)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
