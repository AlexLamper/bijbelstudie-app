import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/bible_year_display.dart';
import '../domain/plan_calendar.dart';
import 'bible_year_parts.dart';
import 'bible_year_providers.dart';
import 'plan_today_tab.dart';
import 'plan_widgets.dart';

/// Leesplan · Schema: a month calendar and the chosen day with its parts,
/// "inhalen" and "opschuiven".
class PlanSchemaTab extends ConsumerStatefulWidget {
  const PlanSchemaTab({
    super.key,
    required this.calendar,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final PlanCalendar calendar;
  final int selectedDay;
  final ValueChanged<int> onSelectDay;

  @override
  ConsumerState<PlanSchemaTab> createState() => _PlanSchemaTabState();
}

class _PlanSchemaTabState extends ConsumerState<PlanSchemaTab> {
  /// First of the month on show.
  late DateTime _month;
  bool _shifting = false;

  @override
  void initState() {
    super.initState();
    _month = _monthOf(widget.calendar.dateOf(widget.selectedDay));
  }

  @override
  void didUpdateWidget(PlanSchemaTab old) {
    super.didUpdateWidget(old);
    if (old.selectedDay != widget.selectedDay) {
      _month = _monthOf(widget.calendar.dateOf(widget.selectedDay));
    }
  }

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  DateTime get _firstMonth => _monthOf(widget.calendar.dateOf(1));
  DateTime get _lastMonth => _monthOf(widget.calendar.dateOf(widget.calendar.totalDays));

  void _moveMonth(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  Future<void> _confirmShift(int days) async {
    final today = ref.read(bibleYearProvider).value?.today;
    final end = today == null ? null : formatDutchDate(shiftedEndDate(today));
    final ok = await showBibleYearConfirm(
      context,
      title: 'Schema opschuiven',
      confirmLabel: 'Opschuiven',
      content: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text:
                  'Je schema schuift ${daysWord(days)} op, zodat je vandaag verder leest waar je gebleven bent.',
            ),
            if (end != null) ...[
              const TextSpan(text: ' Je bent dan klaar op '),
              TextSpan(text: end, style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(text: '.'),
            ],
          ],
        ),
      ),
    );
    if (!ok || !mounted) return;
    setState(() => _shifting = true);
    final error = await ref.read(bibleYearProvider.notifier).shift();
    if (!mounted) return;
    setState(() => _shifting = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final cal = widget.calendar;
    final today = ref.watch(bibleYearProvider.select((s) => s.value?.today));
    final openCount = cal.openDays().length;
    final behind = today?.behindDays ?? 0;
    // Shift by what the server will shift by; fall back to the open days.
    final shiftDays = behind > 0 ? behind : openCount;

    return RefreshIndicator(
      color: AppTheme.teal,
      onRefresh: () => ref.read(bibleYearProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _MonthCard(
            calendar: cal,
            month: _month,
            selectedDay: widget.selectedDay,
            canBack: _month.isAfter(_firstMonth),
            canForward: _month.isBefore(_lastMonth),
            onMove: _moveMonth,
            onSelectDay: widget.onSelectDay,
          ),
          const SizedBox(height: 12),
          _DayCard(
            calendar: cal,
            day: widget.selectedDay,
            shiftDays: shiftDays,
            shifting: _shifting,
            onShift: () => _confirmShift(shiftDays),
          ),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.calendar,
    required this.month,
    required this.selectedDay,
    required this.canBack,
    required this.canForward,
    required this.onMove,
    required this.onSelectDay,
  });

  final PlanCalendar calendar;
  final DateTime month;
  final int selectedDay;
  final bool canBack;
  final bool canForward;
  final ValueChanged<int> onMove;
  final ValueChanged<int> onSelectDay;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = month.weekday - 1;
    final cells = lead + daysInMonth;
    final weeks = (cells / 7).ceil();

    Widget arrow(IconData icon, String label, bool enabled, int by) => Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: enabled ? () => onMove(by) : null,
        icon: Icon(icon, size: 24),
        color: AppTheme.inkSoft,
        disabledColor: AppTheme.inkFaint.withValues(alpha: 0.4),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );

    Widget cell(int index) {
      final dayOfMonth = index - lead + 1;
      if (dayOfMonth < 1 || dayOfMonth > daysInMonth) return const SizedBox(height: 44);
      final date = DateTime(month.year, month.month, dayOfMonth);
      final day = calendar.dayOn(date);
      final state = day == null ? PlanDayState.outside : calendar.stateOf(day);
      final circle = PlanDayCircle(
        dayOfMonth: dayOfMonth,
        state: state,
        style: PlanDayCircleStyle.calendar,
        selected: day != null && day == selectedDay,
      );
      return SizedBox(
        height: 44,
        child: day == null
            ? Center(child: circle)
            : Semantics(
                button: true,
                selected: day == selectedDay,
                label: 'Dag $day, ${planDateLong(date)}',
                excludeSemantics: true,
                child: InkResponse(
                  onTap: () => onSelectDay(day),
                  radius: 22,
                  child: Center(child: circle),
                ),
              ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
      child: Column(
        children: [
          Row(
            children: [
              arrow(Icons.chevron_left_rounded, 'Vorige maand', canBack, -1),
              Expanded(
                child: Text(
                  planMonthTitle(month),
                  textAlign: TextAlign.center,
                  style: AppTheme.displayTitle,
                ),
              ),
              arrow(Icons.chevron_right_rounded, 'Volgende maand', canForward, 1),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final name in planWeekdayShort)
                Expanded(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600, color: AppTheme.inkFaint),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var w = 0; w < weeks; w++)
            Row(children: [for (var c = 0; c < 7; c++) Expanded(child: cell(w * 7 + c))]),
          const SizedBox(height: 10),
          const _Legend(),
        ],
      ),
    );
  }
}

/// Gelezen · Open · Vandaag with tiny swatches.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    Widget item(BoxDecoration swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: swatch),
        const SizedBox(width: 6),
        Text(label, style: AppTheme.caption),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        item(BoxDecoration(shape: BoxShape.circle, color: AppTheme.tealTint), 'Gelezen'),
        item(
          BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.paperSunken,
            border: Border.all(color: AppTheme.ruleStrong),
          ),
          'Open',
        ),
        item(
          BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.teal, width: 2)),
          'Vandaag',
        ),
      ],
    );
  }
}

/// The chosen day: date, state, minutes, its parts, and for an open day
/// "Dag 22 inhalen" + "Schema een dag opschuiven".
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.calendar,
    required this.day,
    required this.shiftDays,
    required this.shifting,
    required this.onShift,
  });

  final PlanCalendar calendar;
  final int day;
  final int shiftDays;
  final bool shifting;
  final VoidCallback onShift;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final state = calendar.stateOf(day);
    final parts = calendar.partsOf(day);
    final current = state == PlanDayState.open || state == PlanDayState.today
        ? calendar.firstOpenPart(day)
        : null;
    final status = switch (state) {
      PlanDayState.done => 'gelezen',
      PlanDayState.open => 'nog niet gelezen',
      PlanDayState.today => 'vandaag',
      PlanDayState.future || PlanDayState.outside => 'komt nog',
    };

    void open(int part) => context.push(PlanRoutes.read(day, part: part));

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(planDateTitle(calendar.dateOf(day)), style: AppTheme.displayTitle),
                      const SizedBox(height: 2),
                      Text('Dag $day · $status', style: AppTheme.caption.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
                Text('${calendar.minutesOf(day)} min', style: AppTheme.caption.copyWith(fontSize: 13)),
              ],
            ),
          ),
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 54, color: AppTheme.rule),
            PlanPartRow(
              height: 48,
              mark: planPartMark(parts[i], i, current),
              title: planPartName(parts[i]),
              onTap: () => open(i),
            ),
          ],
          if (state == PlanDayState.open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SiteButton(label: 'Dag $day inhalen', onPressed: () => open(current ?? 0)),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: shifting ? null : onShift,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.tealStrong,
                      minimumSize: const Size.fromHeight(44),
                      textStyle: AppTheme.buttonLabel,
                    ),
                    child: Text(
                      shiftDays > 1 ? 'Schema $shiftDays dagen opschuiven' : 'Schema een dag opschuiven',
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}
