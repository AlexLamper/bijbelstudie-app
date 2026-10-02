import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/plan_calendar.dart';

/// Routes of the reading plan. `/leesplan` sits inside the shell (bottom nav
/// visible, Start active); setup and the plan reader are full screen.
abstract final class PlanRoutes {
  /// `?tab=schema&day=22` opens Schema on that plan day.
  static const plan = '/leesplan';

  /// `?edit=1` opens the steps prefilled for the running plan (the gear).
  static const setup = '/leesplan/instellen';

  /// `?day=23&part=0` - the reader with the plan bar, on that part of the day.
  static const reader = '/leesplan/lezen';

  static String schema({int? day}) => day == null ? '$plan?tab=schema' : '$plan?tab=schema&day=$day';
  static String read(int day, {int part = 0}) => '$reader?day=$day&part=$part';
}

/// State of one part (chapter, uitleg, vraag) in a list row.
enum PlanPartMark { todo, done, current }

/// The status circle in front of a part: empty, filled with a check, or
/// ringed with a dot for "hier ben je". Display only - parts tick themselves
/// in the reader, never by a tap here.
class PlanPartCircle extends StatelessWidget {
  const PlanPartCircle({super.key, required this.mark, this.size = 24});

  final PlanPartMark mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final teal = AppTheme.teal;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: mark == PlanPartMark.done ? teal : null,
          border: mark == PlanPartMark.done
              ? null
              : Border.all(
                  color: mark == PlanPartMark.current ? teal : AppTheme.ruleStrong,
                  width: mark == PlanPartMark.current ? 2 : 1.5,
                ),
        ),
        child: switch (mark) {
          PlanPartMark.done => Icon(Icons.check_rounded, size: size * 0.62, color: AppTheme.inkInverted),
          PlanPartMark.current => Center(
            child: SizedBox.square(
              dimension: size * 0.33,
              child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: teal)),
            ),
          ),
          PlanPartMark.todo => null,
        },
      ),
    );
  }
}

/// Which surface draws a [PlanDayCircle]: the week strip fills a done day
/// with the accent and a check; the month calendar tints it and keeps the number.
enum PlanDayCircleStyle { strip, calendar }

/// A day as a ~36 px circle. Done, open (grey, dashed ring - neutral, never a
/// warning colour), today (accent ring, bold number), future (thin ring in the
/// strip, number only in the calendar), outside the plan (number only).
class PlanDayCircle extends StatelessWidget {
  const PlanDayCircle({
    super.key,
    required this.dayOfMonth,
    required this.state,
    this.style = PlanDayCircleStyle.strip,
    this.selected = false,
    this.size = 36,
  });

  final int dayOfMonth;
  final PlanDayState state;
  final PlanDayCircleStyle style;

  /// The calendar's chosen day: a ring in ink around whatever it shows.
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final teal = AppTheme.teal;
    final strip = style == PlanDayCircleStyle.strip;
    Color? fill;
    Color textColor = AppTheme.ink;
    FontWeight weight = FontWeight.w500;
    Border? border;
    var dashed = false;
    Widget? child;

    switch (state) {
      case PlanDayState.done:
        if (strip) {
          fill = teal;
          child = Icon(Icons.check_rounded, size: size * 0.5, color: AppTheme.inkInverted);
        } else {
          fill = AppTheme.tealTint;
          textColor = teal;
          weight = FontWeight.w600;
        }
      case PlanDayState.open:
        fill = AppTheme.paperSunken;
        textColor = AppTheme.inkMuted;
        dashed = true;
      case PlanDayState.today:
        border = Border.all(color: teal, width: 2);
        weight = FontWeight.w700;
        textColor = AppTheme.ink;
      case PlanDayState.future:
        if (strip) border = Border.all(color: AppTheme.rule, width: 1);
        textColor = strip ? AppTheme.inkSoft : AppTheme.ink;
      case PlanDayState.outside:
        textColor = AppTheme.inkFaint;
    }
    if (selected && state != PlanDayState.today) {
      border = Border.all(color: AppTheme.ink, width: 1.5);
      dashed = false;
    }

    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: border),
      child:
          child ??
          Text(
            '$dayOfMonth',
            style: TextStyle(fontSize: 14, fontWeight: weight, color: textColor, height: 1),
          ),
    );
    if (!dashed) return circle;
    return CustomPaint(
      foregroundPainter: _DashedRingPainter(color: AppTheme.ruleStrong),
      child: circle,
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashes = 14;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    final r = rect.deflate(0.75);
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(r, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

/// The plan card's progress ring (~68 px) with the percentage in the middle.
class PlanProgressRing extends StatelessWidget {
  const PlanProgressRing({super.key, required this.percent, this.size = 68});

  /// 0-100.
  final double percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = (percent / 100).clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: size <= 50 ? 4.5 : 6,
              strokeCap: StrokeCap.round,
              color: AppTheme.teal,
              backgroundColor: AppTheme.paperSunken,
            ),
          ),
          Text(
            '${percent.floor()}%',
            // Proportional so the Start tab's small ring still fits "100%";
            // 68 (the plan screen's size) keeps its original 16.
            style: TextStyle(
              fontSize: size * 0.235,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Op schema" / "1 dag achter" - neutral pill, never a warning colour.
class PlanStatusPill extends StatelessWidget {
  const PlanStatusPill({super.key, required this.openDays});

  final int openDays;

  @override
  Widget build(BuildContext context) {
    final onSchedule = openDays == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onSchedule ? AppTheme.tealTint : AppTheme.paperSunken,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        onSchedule ? 'Op schema' : '$openDays ${openDays == 1 ? 'dag' : 'dagen'} achter',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: onSchedule ? AppTheme.tealStrong : AppTheme.inkSoft,
        ),
      ),
    );
  }
}
