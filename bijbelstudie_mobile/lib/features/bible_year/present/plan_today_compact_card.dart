import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../data/bible_year_models.dart';
import '../domain/bible_year_display.dart';
import '../domain/plan_calendar.dart';
import 'bible_year_parts.dart';
import 'bible_year_providers.dart';
import 'plan_widgets.dart';

/// One reading portion as the Start tab's main card shows it: a tickable chip.
class PlanChip {
  const PlanChip({
    required this.label,
    required this.minutes,
    required this.done,
    required this.partIndex,
    this.refs = const [],
    this.study = false,
  });

  final String label;
  final int minutes;
  final bool done;

  /// Which part of the plan reader this chip opens (`?part=`).
  final int partIndex;

  /// The chapters behind the chip, for the tick. Empty for the study chip.
  final List<BibleYearChapterKey> refs;

  /// The 'studeren' chip (uitleg + vraag), which ticks through [markStudy].
  final bool study;
}

/// Today's plan, read off [today] and the schedule, as the Start tab needs it:
/// the chips, whether the day is finished, and the oldest day still open.
///
/// Shared by [PlanTodayCompactCard] and by the Start tab's choice between the
/// two main cards - "vandaag al afgerond" has to mean the same in both.
class PlanTodayView {
  PlanTodayView({required this.today, required this.enrollment, this.calendar});

  final BibleYearToday today;
  final BibleYearEnrollment enrollment;
  final PlanCalendar? calendar;

  /// The plan day this is about: day 1 before the start (read ahead).
  int get day => today.dayNumber > 0 ? today.dayNumber : 1;

  bool _read(BibleYearRef ref) => ref.read || (calendar?.isRead(ref) ?? false);

  BibleYearDayStudy? get _study =>
      enrollment.mode == BibleYearMode.studeren ? today.study : null;

  bool _studyPartDone(BibleYearDayStudy study, BibleYearStudyPart part) {
    final local = part == BibleYearStudyPart.uitleg ? study.uitlegDone : study.vraagDone;
    return local || (calendar?.studyPartDone(day, part) ?? false);
  }

  late final List<PlanChip> chips = _chips();

  List<PlanChip> _chips() {
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

    final out = <PlanChip>[];
    var part = 0;
    for (final p in today.portions) {
      out.add(
        PlanChip(
          label: p.label,
          minutes: minutesOf(p),
          done: p.refs.isNotEmpty && p.refs.every(_read),
          partIndex: part,
          refs: [for (final r in p.refs) BibleYearChapterKey(r.code, r.chapter)],
        ),
      );
      part += p.refs.length;
    }
    final study = _study;
    if (study != null) {
      out.add(
        PlanChip(
          label: 'Uitleg en vraag',
          minutes: 8,
          done: _studyPartDone(study, BibleYearStudyPart.uitleg) &&
              _studyPartDone(study, BibleYearStudyPart.vraag),
          partIndex: part,
          study: true,
        ),
      );
    }
    return out;
  }

  /// Everything today asks for is ticked. False on a day with nothing in it,
  /// so an empty day never reads as "done".
  bool get dayDone => chips.isNotEmpty && chips.every((c) => c.done);

  /// The part the "Lezen" button opens: the first chip still open.
  int get firstOpenPart {
    final cal = calendar;
    if (cal != null) {
      final part = cal.firstOpenPart(day);
      if (part != null) return part;
    }
    for (final chip in chips) {
      if (!chip.done) return chip.partIndex;
    }
    return 0;
  }

  /// The oldest day still open before today, for "Dag 2 inhalen". Null when
  /// the reader is on schedule, or while the schedule has not loaded.
  int? get catchUpDay {
    final open = calendar?.openDays();
    return open == null || open.isEmpty ? null : open.last;
  }

  int get behindDays => calendar?.openDays().length ?? today.behindDays;
}

/// The Start tab's main card while a reading plan runs and today is not
/// finished (design 28a): two rows, so the tekst van de dag stays in view.
///
/// Row 1 is the ring, "Dag 3 van 365" with either the catch-up link or the
/// plan name, and "Lezen". Row 2 is today's portions as tickable chips - the
/// circle ticks, the label opens. A tap elsewhere opens Leesplan.
class PlanTodayCompactCard extends ConsumerWidget {
  const PlanTodayCompactCard({
    super.key,
    required this.view,
    this.onNavigate,
    this.showChips = true,
  });

  final PlanTodayView view;

  /// Overrides navigation (tests). Defaults to `context.push`.
  final void Function(String location)? onNavigate;

  /// False at large text sizes: the card drops to one row so the verse card
  /// cannot be pushed under the fold.
  final bool showChips;

  Future<void> _tick(WidgetRef ref, PlanChip chip) async {
    final notifier = ref.read(bibleYearProvider.notifier);
    if (chip.study) {
      await notifier.markStudy(view.day, BibleYearStudyPart.uitleg, done: !chip.done);
      await notifier.markStudy(view.day, BibleYearStudyPart.vraag, done: !chip.done);
      return;
    }
    if (chip.refs.isEmpty) return;
    await notifier.markRefs(chip.refs, !chip.done);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    void go(String location) => (onNavigate ?? (l) => context.push(l))(location);

    final today = view.today;
    final catchUp = view.catchUpDay;
    final behind = view.behindDays;
    final percent = view.enrollment.percentBible > 0
        ? view.enrollment.percentBible
        : today.percentBible;
    final title = today.notStarted
        ? view.enrollment.startDate.isNotEmpty
              ? 'Je begint op ${formatDutchDate(view.enrollment.startDate, weekday: true)}'
              : 'Je leesplan begint binnenkort'
        : dayOfPlanLabel(today.dayNumber, today.totalDays);

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => go(PlanRoutes.plan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PlanProgressRing(percent: percent.isFinite ? percent : 0, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyStrong.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _SubLine(
                      behindDays: behind,
                      catchUpDay: catchUp,
                      onCatchUp: catchUp == null
                          ? null
                          : () => go(
                              PlanRoutes.read(
                                catchUp,
                                part: view.calendar?.firstOpenPart(catchUp) ?? 0,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              BibleYearPrimaryButton(
                label: 'Lezen',
                height: 44,
                onPressed: () => go(PlanRoutes.read(view.day, part: view.firstOpenPart)),
              ),
            ],
          ),
          if (showChips && view.chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in view.chips)
                  _PortionChip(
                    chip: chip,
                    onTick: () => _tick(ref, chip),
                    onOpen: () => go(PlanRoutes.read(view.day, part: chip.partIndex)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "2 dagen achter · Dag 2 inhalen", or the plan name when on schedule. Never
/// a warning colour: being behind is not an error.
class _SubLine extends StatelessWidget {
  const _SubLine({
    required this.behindDays,
    required this.catchUpDay,
    required this.onCatchUp,
  });

  final int behindDays;
  final int? catchUpDay;
  final VoidCallback? onCatchUp;

  @override
  Widget build(BuildContext context) {
    final day = catchUpDay;
    if (day == null || behindDays <= 0) {
      return Text(
        'Bijbel in een jaar',
        style: AppTheme.caption.copyWith(fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      children: [
        Text(
          '$behindDays ${behindDays == 1 ? 'dag' : 'dagen'} achter · ',
          style: AppTheme.caption.copyWith(fontSize: 13, color: AppTheme.inkSoft),
        ),
        Flexible(
          child: InkWell(
            onTap: onCatchUp,
            child: Text(
              'Dag $day inhalen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                fontSize: 13,
                color: AppTheme.teal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Genesis 5-7" / "Psalmen 3-4 · 5 min": the circle ticks the portion off,
/// the label opens it. Done reads as a filled check with the label dimmed and
/// struck through.
class _PortionChip extends StatelessWidget {
  const _PortionChip({required this.chip, required this.onTick, required this.onOpen});

  final PlanChip chip;
  final VoidCallback onTick;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paperSunken,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 44x44 around a 20px circle: the tick is the smallest target here,
          // so it gets the full one.
          Semantics(
            button: true,
            label: chip.done
                ? '${chip.label} afvinken ongedaan maken'
                : '${chip.label} afvinken',
            child: InkWell(
              onTap: onTick,
              customBorder: const CircleBorder(),
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: PlanPartCircle(
                    mark: chip.done ? PlanPartMark.done : PlanPartMark.todo,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(right: 14),
              alignment: Alignment.center,
              child: Text(
                chip.done ? chip.label : '${chip.label} · ${chip.minutes} min',
                style: AppTheme.bodyStrong.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: chip.done ? AppTheme.inkMuted : AppTheme.ink,
                  decoration: chip.done ? TextDecoration.lineThrough : null,
                  decorationColor: AppTheme.inkMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
