import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/preview_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/ui/skeleton.dart';
import '../data/bible_year_models.dart';
import '../domain/bible_year_display.dart';
import '../domain/plan_calendar.dart';
import 'bible_year_parts.dart';
import 'bible_year_providers.dart';
import 'plan_widgets.dart';

/// The Start tab's reading-plan slot, right under the greeting: the plan card
/// while a plan runs, an invitation to begin one when there is none, nothing
/// while that is unknown (signed out, an error, a slow first load).
class PlanStartSlot extends ConsumerStatefulWidget {
  const PlanStartSlot({super.key, this.planActive, this.bottomSpacing = 16});

  /// What `/dashboard` said (`DashboardData.bibleYearActive`). False: no plan,
  /// so `/bible-year` is not asked at all and the invitation shows at once -
  /// unless the plan state is already loaded (a plan just started shows at
  /// once). Null (an older server): ask.
  final bool? planActive;

  /// The gap below the card, so the slot collapses fully when it is empty.
  final double bottomSpacing;

  @override
  ConsumerState<PlanStartSlot> createState() => _PlanStartSlotState();
}

class _PlanStartSlotState extends ConsumerState<PlanStartSlot> with BibleYearRefreshOnMount {
  bool get _skip => widget.planActive == false && !ref.exists(bibleYearProvider);

  @override
  bool get bibleYearRefreshOnMount => !_skip;

  @override
  bool get bibleYearKnownActive => widget.planActive == true;

  Widget _spaced(Widget child) =>
      Padding(padding: EdgeInsets.only(bottom: widget.bottomSpacing), child: child);

  // The preview build cannot start a plan (its repository refuses), so it
  // gets no invitation, as before.
  Widget _invite() => PreviewConfig.enabled ? const SizedBox.shrink() : _spaced(const PlanStartInvite());

  @override
  Widget build(BuildContext context) {
    if (_skip) return _invite();
    final async = ref.watch(bibleYearProvider);
    final state = async.value;
    if (state == null) {
      // Only hold the space when the dashboard said a plan runs.
      if (async.isLoading && widget.planActive == true) {
        return _spaced(const Skeleton(height: 260, radius: AppTheme.radiusLg));
      }
      return const SizedBox.shrink();
    }
    final today = state.today;
    final enrollment = state.enrollment;
    if (!state.isActive || today == null || enrollment == null) return _invite();
    return _spaced(
      PlanStartCard(
        today: today,
        enrollment: enrollment,
        calendar: ref.watch(planCalendarProvider).value,
      ),
    );
  }
}

/// No plan yet: a short invitation to begin "Bijbel in een jaar".
class PlanStartInvite extends StatelessWidget {
  const PlanStartInvite({super.key, this.onNavigate});

  /// Overrides navigation (tests). Defaults to `context.push`.
  final void Function(String location)? onNavigate;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    void go(String location) => (onNavigate ?? (l) => context.push(l))(location);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bijbel in een jaar', style: AppTheme.displayBase),
                const SizedBox(height: 2),
                Text(
                  'Lees de hele Bijbel, elke dag een paar hoofdstukken.',
                  style: AppTheme.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BibleYearPrimaryButton(
            label: 'Begin',
            height: 44,
            onPressed: () => go(PlanRoutes.setup),
          ),
        ],
      ),
    );
  }
}

/// One row of today on the card: a portion ("Genesis 45-46"), or in
/// 'studeren' the day's uitleg and vraag together.
class _PlanStartRow {
  const _PlanStartRow({required this.label, required this.minutes, required this.done});

  final String label;
  final int minutes;
  final bool done;
}

/// The plan card: progress ring, "Dag 23 van 365" with the status pill,
/// today's portions with their state and minutes, then "Dag 22 inhalen" (only
/// with an open day) and "Lezen". A tap elsewhere opens Leesplan.
///
/// Renders from [today] alone; [calendar] (the schedule, which loads after)
/// adds the open days and the reader's exact part.
class PlanStartCard extends StatelessWidget {
  const PlanStartCard({
    super.key,
    required this.today,
    required this.enrollment,
    this.calendar,
    this.onNavigate,
  });

  final BibleYearToday today;
  final BibleYearEnrollment enrollment;
  final PlanCalendar? calendar;

  /// Overrides navigation (tests). Defaults to `context.push`.
  final void Function(String location)? onNavigate;

  /// The plan day the card is about: day 1 before the start (read ahead).
  int get _day => today.dayNumber > 0 ? today.dayNumber : 1;

  bool _read(BibleYearRef ref) => ref.read || (calendar?.isRead(ref) ?? false);

  bool _studyDone(BibleYearDayStudy study, BibleYearStudyPart part) {
    final local = part == BibleYearStudyPart.uitleg ? study.uitlegDone : study.vraagDone;
    return local || (calendar?.studyPartDone(_day, part) ?? false);
  }

  BibleYearDayStudy? get _study =>
      enrollment.mode == BibleYearMode.studeren ? today.study : null;

  List<_PlanStartRow> _rows() {
    final allRefs = today.portions.fold(0, (n, p) => n + p.refs.length);
    int minutesOf(BibleYearPortion p) {
      if (p.refs.isNotEmpty && p.refs.every((r) => r.minutes > 0)) {
        return p.refs.fold(0, (sum, r) => sum + r.minutes);
      }
      if (today.minutesEstimate > 0 && allRefs > 0) {
        final share = (today.minutesEstimate * p.refs.length / allRefs).round();
        return share < 1 ? 1 : share;
      }
      return p.refs.length * 4;
    }

    final study = _study;
    return [
      for (final p in today.portions)
        _PlanStartRow(
          label: p.label,
          minutes: minutesOf(p),
          done: p.refs.isNotEmpty && p.refs.every(_read),
        ),
      if (study != null)
        _PlanStartRow(
          label: 'Uitleg en vraag',
          minutes: 8,
          done:
              _studyDone(study, BibleYearStudyPart.uitleg) &&
              _studyDone(study, BibleYearStudyPart.vraag),
        ),
    ];
  }

  /// The reader part to open today on: the calendar's answer, or counted
  /// from today's own refs while the schedule loads.
  int _firstOpenPart() {
    final cal = calendar;
    if (cal != null) return cal.firstOpenPart(_day) ?? 0;
    var i = 0;
    for (final p in today.portions) {
      for (final r in p.refs) {
        if (!_read(r)) return i;
        i++;
      }
    }
    final study = _study;
    if (study != null && _studyDone(study, BibleYearStudyPart.uitleg)) i++;
    return study == null ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    void go(String location) => (onNavigate ?? (l) => context.push(l))(location);

    final rows = _rows();
    final currentIndex = rows.indexWhere((r) => !r.done);
    final dayDone = rows.isNotEmpty && currentIndex < 0;
    final openDays = calendar?.openDays();
    final catchUp = openDays == null || openDays.isEmpty ? null : openDays.last;
    // The calendar's read set when it has loaded (the same one the green days
    // and the plan screen's header use); the server's counts until then.
    final percent = calendar?.percentBible ??
        (enrollment.percentBible > 0 ? enrollment.percentBible : today.percentBible);
    final title = today.notStarted
        ? enrollment.startDate.isNotEmpty
              ? 'Je begint op ${formatDutchDate(enrollment.startDate, weekday: true)}'
              : 'Je leesplan begint binnenkort'
        : dayOfPlanLabel(today.dayNumber, today.totalDays);

    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () => go(PlanRoutes.plan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PlanProgressRing(percent: percent.isFinite ? percent : 0),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyStrong.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('Bijbel in een jaar', style: AppTheme.caption.copyWith(fontSize: 13)),
                    const SizedBox(height: 6),
                    PlanStatusPill(openDays: openDays?.length ?? today.behindDays),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            Divider(height: 1, thickness: 1, color: AppTheme.rule),
            SizedBox(
              height: 46,
              child: Row(
                children: [
                  PlanPartCircle(
                    mark: rows[i].done
                        ? PlanPartMark.done
                        : i == currentIndex
                        ? PlanPartMark.current
                        : PlanPartMark.todo,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].label,
                      style: AppTheme.bodyStrong.copyWith(
                        fontWeight: FontWeight.w500,
                        color: rows[i].done ? AppTheme.inkMuted : AppTheme.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${rows[i].minutes} min', style: AppTheme.caption.copyWith(fontSize: 13)),
                ],
              ),
            ),
          ],
          if (rows.isNotEmpty) Divider(height: 1, thickness: 1, color: AppTheme.rule),
          const SizedBox(height: 14),
          Row(
            children: [
              if (catchUp != null) ...[
                Expanded(
                  child: BibleYearSecondaryButton(
                    label: 'Dag $catchUp inhalen',
                    height: 44,
                    onPressed: () =>
                        go(PlanRoutes.read(catchUp, part: calendar!.firstOpenPart(catchUp) ?? 0)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: dayDone
                    ? _DoneButton(label: 'Dag $_day klaar', onPressed: () => go(PlanRoutes.plan))
                    : BibleYearPrimaryButton(
                        label: 'Lezen',
                        height: 44,
                        onPressed: () => go(PlanRoutes.read(_day, part: _firstOpenPart())),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Dag 23 klaar" with a check: the primary button once today is done.
/// Styled as [BibleYearPrimaryButton], which has no icon slot.
class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.check_rounded, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.tealFill,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
        textStyle: AppTheme.pillLabel.copyWith(fontSize: 13),
      ),
    );
  }
}
