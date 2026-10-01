import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/plan_calendar.dart';
import 'bible_year_providers.dart';
import 'plan_widgets.dart';

/// Leesplan · Vandaag: the open-day notice, today's parts and tomorrow.
class PlanTodayTab extends ConsumerWidget {
  const PlanTodayTab({super.key, required this.calendar, required this.onShowDay});

  final PlanCalendar calendar;

  /// Switches to Schema with that plan day selected.
  final ValueChanged<int> onShowDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final todayDay = calendar.todayDay;
    final preview = todayDay < 1;
    final day = preview ? 1 : todayDay.clamp(1, calendar.totalDays);
    final open = calendar.openDays();
    final tomorrow = day + 1;

    return RefreshIndicator(
      color: AppTheme.teal,
      onRefresh: () => ref.read(bibleYearProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (preview) ...[
            Text(
              'Je leesplan begint op ${planDateLong(calendar.dateOf(1))}.',
              style: AppTheme.bodyMuted.copyWith(color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 12),
          ],
          if (open.isNotEmpty) ...[
            _OpenDaysCard(calendar: calendar, openDays: open),
            const SizedBox(height: 12),
          ],
          _TodayCard(calendar: calendar, day: day, preview: preview),
          if (!preview && tomorrow <= calendar.totalDays) ...[
            const SizedBox(height: 12),
            _TomorrowCard(calendar: calendar, day: tomorrow, onTap: () => onShowDay(tomorrow)),
          ],
        ],
      ),
    );
  }
}

/// "Dag 22 (gisteren) staat nog open" + Inhalen. Neutral, never a warning.
class _OpenDaysCard extends StatelessWidget {
  const _OpenDaysCard({required this.calendar, required this.openDays});

  final PlanCalendar calendar;

  /// Oldest first.
  final List<int> openDays;

  String get _message {
    if (openDays.length > 1) return '${openDays.length} dagen staan nog open';
    final day = openDays.first;
    final ago = calendar.todayDay - day;
    final long = planDateLong(calendar.dateOf(day));
    final when = ago == 1
        ? 'gisteren'
        : ago < 7
        ? long.split(' ').first
        : long.substring(long.indexOf(' ') + 1);
    return 'Dag $day ($when) staat nog open';
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final oldest = openDays.first;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 20, color: AppTheme.inkMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(_message, style: AppTheme.bodyStrong)),
          TextButton(
            onPressed: () => context.push(
              PlanRoutes.read(oldest, part: calendar.firstOpenPart(oldest) ?? 0),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.tealStrong,
              minimumSize: const Size(44, 44),
              textStyle: AppTheme.buttonLabel,
            ),
            child: const Text('Inhalen'),
          ),
        ],
      ),
    );
  }
}

/// The name of a part as a list row shows it.
String planPartName(PlanPart part) => switch (part.kind) {
  PlanPartKind.chapter => chapterLabel(part.ref),
  PlanPartKind.uitleg => 'Uitleg bij ${chapterLabel(part.ref)}',
  PlanPartKind.vraag => 'Vraag bij ${chapterLabel(part.ref)}',
};

/// The circle a part shows: done, "hier ben je" (the first open part), todo.
PlanPartMark planPartMark(PlanPart part, int index, int? current) => part.done
    ? PlanPartMark.done
    : index == current
    ? PlanPartMark.current
    : PlanPartMark.todo;

/// One part as a tappable row: circle, name, optional subline, chevron.
class PlanPartRow extends StatelessWidget {
  const PlanPartRow({
    super.key,
    required this.mark,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.onTap,
    this.height = 56,
  });

  final PlanPartMark mark;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                PlanPartCircle(mark: mark),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTheme.bodyStrong.copyWith(
                          fontSize: 15,
                          color: mark == PlanPartMark.done ? AppTheme.inkSoft : AppTheme.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppTheme.caption.copyWith(
                            fontSize: 13,
                            color: subtitleColor ?? AppTheme.inkMuted,
                            fontWeight: mark == PlanPartMark.current ? FontWeight.w600 : null,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onTap != null) Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Today's parts, one row each, and the button that carries on.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.calendar, required this.day, required this.preview});

  final PlanCalendar calendar;
  final int day;

  /// Before the start date: day 1 shown ahead of time.
  final bool preview;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final parts = calendar.partsOf(day);
    final current = calendar.firstOpenPart(day);
    final doneCount = parts.where((p) => p.done).length;
    final minutesLeft = calendar.minutesLeft(day);
    final singleStrand = parts
        .where((p) => p.isChapter)
        .every((p) => strandLabel(p.strand) == null);

    void open(int part) => context.push(PlanRoutes.read(day, part: part));

    final rows = <Widget>[];
    Widget? vraag;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final mark = planPartMark(part, i, current);
      if (part.kind == PlanPartKind.vraag) {
        vraag = _QuestionBlock(part: part, onTap: () => open(i));
        continue;
      }
      final String subtitle;
      Color? subColor;
      if (part.done) {
        subtitle = 'Gelezen';
        subColor = AppTheme.inkFaint;
      } else if (mark == PlanPartMark.current) {
        subtitle = 'Hier ben je';
        subColor = AppTheme.tealStrong;
      } else if (part.kind == PlanPartKind.uitleg) {
        subtitle = 'Matthew Henry · ${part.minutes} min';
      } else {
        final strand = singleStrand ? null : strandLabel(part.strand);
        subtitle = strand == null ? '${part.minutes} min' : '$strand · ${part.minutes} min';
      }
      if (rows.isNotEmpty) rows.add(Divider(height: 1, thickness: 1, indent: 54, color: AppTheme.rule));
      rows.add(
        PlanPartRow(
          mark: mark,
          title: planPartName(part),
          subtitle: subtitle,
          subtitleColor: subColor,
          onTap: () => open(i),
        ),
      );
    }

    final done = current == null && parts.isNotEmpty;
    final meta = done
        ? '$doneCount van ${parts.length}'
        : '$doneCount van ${parts.length} · ± $minutesLeft min';

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Text(preview ? 'Dag 1' : 'Vandaag', style: AppTheme.displayTitle),
                if (calendar.studeren) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.tealTint,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    child: Text(
                      'Studeren',
                      style: AppTheme.pillLabel.copyWith(fontSize: 12, color: AppTheme.tealStrong),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    meta,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          ...rows,
          if (vraag != null)
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: vraag),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: done
                ? _DayDone(calendar: calendar, day: day)
                : SiteButton(
                    label: _continueLabel(parts[current!], preview && doneCount == 0),
                    onPressed: () => open(current),
                  ),
          ),
        ],
      ),
    );
  }

  static String _continueLabel(PlanPart part, bool first) => switch (part.kind) {
    PlanPartKind.chapter => '${first ? 'Begin met' : 'Verder met'} ${chapterLabel(part.ref)}',
    PlanPartKind.uitleg => 'Verder met de uitleg',
    PlanPartKind.vraag => 'Verder met de vraag',
  };
}

/// "Vraag van vandaag" in a light accent tint, the question in the reading face.
class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({required this.part, required this.onTap});

  final PlanPart part;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Semantics(
      button: true,
      child: Material(
        color: AppTheme.tealTint,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VRAAG VAN VANDAAG', style: AppTheme.groupLabel),
                      const SizedBox(height: 6),
                      Text(
                        part.question ?? '',
                        style: AppTheme.readerBody.copyWith(fontSize: 16, height: 1.55, color: AppTheme.ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                part.done
                    ? Icon(Icons.check_rounded, size: 20, color: AppTheme.tealStrong)
                    : Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.tealStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Dag 23 klaar" (accent, not a button) and "Morgen alvast lezen".
class _DayDone extends StatelessWidget {
  const _DayDone({required this.calendar, required this.day});

  final PlanCalendar calendar;
  final int day;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final next = day + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.tealTint,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_rounded, size: 18, color: AppTheme.tealStrong),
              const SizedBox(width: 8),
              Text('Dag $day klaar', style: AppTheme.buttonLabel.copyWith(color: AppTheme.tealStrong)),
            ],
          ),
        ),
        if (next <= calendar.totalDays) ...[
          const SizedBox(height: 10),
          SiteOutlineButton(
            label: 'Morgen alvast lezen',
            onPressed: () => context.push(
              PlanRoutes.read(next, part: calendar.firstOpenPart(next) ?? 0),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Morgen · dag 24" with tomorrow's portions on one line.
class _TomorrowCard extends StatelessWidget {
  const _TomorrowCard({required this.calendar, required this.day, required this.onTap});

  final PlanCalendar calendar;
  final int day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final portions = calendar.scheduleDay(day)?.portions ?? const [];
    final labels = portions.map((p) => p.label).where((l) => l.isNotEmpty).join(' · ');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Morgen · dag $day', style: AppTheme.displayBase),
                if (labels.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    labels,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.inkFaint),
        ],
      ),
    );
  }
}
