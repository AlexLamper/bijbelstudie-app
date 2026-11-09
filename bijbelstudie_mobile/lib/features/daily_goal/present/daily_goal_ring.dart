import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../progress_tree/present/progress_tree_avatar.dart' show kGoldRing;

/// Today's goal as a ring: a hairline track, a teal arc from twelve o'clock
/// that fills clockwise, gold and a check once the goal is in. The website
/// draws the same ring (`components/dailyGoal/GoalRing.tsx`).
///
/// The arc animates to its new value, so the ring visibly moves when the
/// reader comes back from reading.
class DailyGoalRing extends StatelessWidget {
  const DailyGoalRing({
    super.key,
    required this.progress,
    this.size = 44,
    this.stroke = 5,
    this.child,
  });

  /// 0..1
  final double progress;
  final double size;
  final double stroke;

  /// Drawn in the middle; a check is drawn instead once [progress] is 1.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final target = progress.clamp(0.0, 1.0);
    final done = target >= 1;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: target),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(
            value: value,
            stroke: stroke,
            track: scheme.outline,
            arc: done ? kGoldRing : AppTheme.teal,
          ),
          child: Center(
            child: done
                ? Icon(Icons.check_rounded, size: size * 0.5, color: kGoldRing)
                : child,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.arc,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    canvas.drawArc(
      ring,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (value <= 0) return;
    canvas.drawArc(
      ring,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.stroke != stroke || old.track != track || old.arc != arc;
}

/// A short burst of dots out of the ring: the goal's celebration. Plays once
/// when built with [play] true; draws nothing otherwise or after it ends.
class GoalBurst extends StatefulWidget {
  const GoalBurst({super.key, required this.size, required this.play});

  final double size;
  final bool play;

  @override
  State<GoalBurst> createState() => _GoalBurstState();
}

class _GoalBurstState extends State<GoalBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.play) _c.forward();
  }

  @override
  void didUpdateWidget(GoalBurst old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _BurstPainter(t: _c.value, colors: [kGoldRing, AppTheme.teal]),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.colors});

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(t);
    final r0 = size.width * 0.42;
    final r = r0 + size.width * 0.38 * eased;
    final alpha = (1 - t).clamp(0.0, 1.0);
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2 - math.pi / 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(
        p,
        size.width * 0.045 * (1 - eased * 0.5),
        Paint()..color = colors[i % colors.length].withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
