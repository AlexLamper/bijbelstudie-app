import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/segmented_track.dart';
import '../../../core/ui/skeleton.dart';
import '../data/bible_year_repository.dart';
import '../domain/plan_calendar.dart';
import 'bible_year_providers.dart';
import 'plan_schema_tab.dart';
import 'plan_today_tab.dart';
import 'plan_widgets.dart';

/// Chapters in the whole Bible: the "van 1189" of the status line.
const _bibleChapters = 1189;

/// Leesplan: tabs Vandaag | Schema. Inside the shell (bottom nav, Start active).
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, this.initialTab = 0, this.initialDay});

  /// 0 = Vandaag, 1 = Schema.
  final int initialTab;

  /// Schema opens with this plan day selected.
  final int? initialDay;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> with BibleYearRefreshOnMount {
  late int _tab = widget.initialTab.clamp(0, 1);

  /// Schema's chosen day; null = today (or day 1 before the start).
  late int? _selectedDay = widget.initialDay;

  @override
  void didUpdateWidget(PlanScreen old) {
    super.didUpdateWidget(old);
    // The same route again with other query parameters (`?tab=schema&day=`).
    if (old.initialTab != widget.initialTab || old.initialDay != widget.initialDay) {
      _tab = widget.initialTab.clamp(0, 1);
      _selectedDay = widget.initialDay ?? _selectedDay;
    }
  }

  void _showDay(int day) => setState(() {
    _tab = 1;
    _selectedDay = day;
  });

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final async = ref.watch(planCalendarProvider);
    final calendar = async.value;

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: Column(
        children: [
          _Header(
            calendar: calendar,
            tab: _tab,
            onTab: (i) => setState(() => _tab = i),
            onShowDay: _showDay,
          ),
          Expanded(child: _body(async, calendar)),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<PlanCalendar?> async, PlanCalendar? calendar) {
    if (calendar != null) {
      if (_tab == 0) return PlanTodayTab(calendar: calendar, onShowDay: _showDay);
      final fallback = calendar.todayDay < 1 ? 1 : calendar.todayDay;
      final day = (_selectedDay ?? fallback).clamp(1, calendar.totalDays);
      return PlanSchemaTab(
        calendar: calendar,
        selectedDay: day,
        onSelectDay: (d) => setState(() => _selectedDay = d),
      );
    }

    final Widget child;
    if (async.hasError) {
      final error = async.error;
      child = error is BibleYearException && error.isUnauthorized
          ? _MessageCard(
              message: 'Log opnieuw in om je leesplan te zien.',
              actionLabel: 'Inloggen',
              onAction: () => context.go('/login'),
            )
          : _MessageCard(
              message: error is BibleYearException ? error.message : 'Je leesplan kon niet worden geladen.',
              actionLabel: 'Opnieuw proberen',
              onAction: () => ref.invalidate(bibleYearProvider),
            );
    } else if (async.isLoading) {
      child = Semantics(label: 'Leesplan laden', child: const SkeletonCardColumn(count: 2));
    } else {
      final completed = ref.watch(bibleYearProvider.select((s) => s.value?.enrollment?.isCompleted == true));
      child = _InviteCard(completed: completed);
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [child],
    );
  }
}

/// White header joined to the status bar: top bar, Vandaag | Schema, the
/// status line, a thin progress bar and this week.
class _Header extends StatelessWidget {
  const _Header({
    required this.calendar,
    required this.tab,
    required this.onTab,
    required this.onShowDay,
  });

  final PlanCalendar? calendar;
  final int tab;
  final ValueChanged<int> onTab;
  final ValueChanged<int> onShowDay;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final cal = calendar;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        border: Border(bottom: BorderSide(color: AppTheme.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Terug',
                  onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
                  icon: Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.inkSoft),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Bijbel in een jaar',
                      textAlign: TextAlign.center,
                      style: AppTheme.displayTitle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (cal != null)
                  IconButton(
                    tooltip: 'Leesplan instellen',
                    onPressed: () => context.push('${PlanRoutes.setup}?edit=1'),
                    icon: Icon(Icons.settings_outlined, size: 22, color: AppTheme.inkSoft),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  )
                else
                  const SizedBox(width: 48),
                const SizedBox(width: 4),
              ],
            ),
          ),
          if (cal != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: SegmentedTrack(
                segments: const [
                  SegmentedTrackSegment(label: 'Vandaag'),
                  SegmentedTrackSegment(label: 'Schema'),
                ],
                selectedIndex: tab,
                onChanged: onTab,
              ),
            ),
            _StatusLine(calendar: cal),
            _WeekStrip(calendar: cal, onShowDay: onShowDay),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// "Dag 23 / woensdag 30 september" left, "6% / 69 van 1189 hoofdstukken"
/// right, and the thin bar under it.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.calendar});

  final PlanCalendar calendar;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final started = calendar.todayDay >= 1;
    // Off the calendar's own read set, not the enrollment's counts: the same
    // chapters that colour the week strip and the schema, so the number here
    // and the green days can never tell different stories.
    final read = calendar.chaptersRead;
    final raw = calendar.percentBible;
    // Rounded, but never "100%" before the last chapter.
    final percent = read < _bibleChapters ? raw.round().clamp(0, 99) : 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(started ? 'Dag ${calendar.todayDay}' : 'Begint', style: AppTheme.displayMedium),
                    Text(
                      planDateLong(calendar.dateOf(started ? calendar.todayDay : 1)),
                      style: AppTheme.caption.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$percent%', style: AppTheme.statNumber),
                  Text(
                    '$read van $_bibleChapters hoofdstukken',
                    style: AppTheme.caption.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SiteProgressBar(value: raw / 100, height: 4),
        ],
      ),
    );
  }
}

/// Monday to Sunday of this week; a tap opens that day in Schema.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.calendar, required this.onShowDay});

  final PlanCalendar calendar;
  final ValueChanged<int> onShowDay;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    // The plan's own today (the server's time zone), else the device's.
    final now = calendar.todayDay >= 1 ? calendar.dateOf(calendar.todayDay) : DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(child: _stripDay(DateTime(monday.year, monday.month, monday.day + i), i)),
        ],
      ),
    );
  }

  Widget _stripDay(DateTime date, int index) {
    final day = calendar.dayOn(date);
    final state = day == null ? PlanDayState.outside : calendar.stateOf(day);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          planWeekdayShort[index],
          style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600, color: AppTheme.inkFaint),
        ),
        const SizedBox(height: 4),
        PlanDayCircle(dayOfMonth: date.day, state: state),
      ],
    );
    if (day == null) return column;
    return Semantics(
      button: true,
      label: 'Dag $day, ${planDateLong(date)}',
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => onShowDay(day),
        radius: 26,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: column),
      ),
    );
  }
}

/// No plan running: an invitation to set one up.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.completed});

  /// The last plan was read to the end.
  final bool completed;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            completed ? 'Je hebt de hele Bijbel gelezen' : 'Begin met Bijbel in een jaar',
            style: AppTheme.displayTitle,
          ),
          const SizedBox(height: 6),
          Text(
            completed
                ? 'Begin opnieuw, in dezelfde of een andere volgorde.'
                : 'Lees de hele Bijbel in een jaar of in twee jaar. Elke dag een stuk van ongeveer dezelfde lengte, en je ziet steeds hoe ver je bent.',
            style: AppTheme.bodyMuted.copyWith(color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 14),
          SiteButton(
            label: completed ? 'Opnieuw beginnen' : 'Leesplan instellen',
            onPressed: () => context.push(PlanRoutes.setup),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.actionLabel, required this.onAction});

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: AppTheme.bodyMuted.copyWith(fontSize: 14.5, color: AppTheme.inkSoft)),
          const SizedBox(height: 12),
          SiteOutlineButton(label: actionLabel, expand: false, height: 40, onPressed: onAction),
        ],
      ),
    );
  }
}
