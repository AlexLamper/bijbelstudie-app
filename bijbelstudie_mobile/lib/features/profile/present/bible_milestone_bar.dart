import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The Bible-progress bar with ticks at 25, 50 and 75% and labels under it.
///
/// Shared by the "Je Bijbel" card on Start and the Bijbelvoortgang page, so the
/// two never drift apart. It lives next to the Bijbelvoortgang page rather than
/// in `core/ui/` because it is not a generic bar: it knows about the four
/// milestones and nothing else uses them.
///
/// [intro] drives the whole reveal (0 = empty, 1 = settled); the fill grows
/// between 0.15 and 0.75 of it and a tick the fill passes pulses once. [glow]
/// and [glowAt] are the one-off halo for a milestone just crossed. [cut] is the
/// colour the passed ticks are cut out in, i.e. whatever sits behind the bar.
class BibleMilestoneBar extends StatelessWidget {
  const BibleMilestoneBar({
    super.key,
    required this.fraction,
    this.intro = 1,
    this.glow = 0,
    this.glowAt,
    this.cut,
  });

  /// 0-1 share of all chapters read.
  final double fraction;
  final double intro;
  final double glow;
  final double? glowAt;
  final Color? cut;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final textScaler = MediaQuery.textScalerOf(context);

    return SizedBox(
      height: _MilestoneBarPainter.heightFor(textScaler),
      child: CustomPaint(
        painter: _MilestoneBarPainter(
          fraction: fraction,
          intro: intro,
          glow: glow,
          glowAt: glowAt,
          track: AppTheme.paperSunkenStrong,
          fill: AppTheme.teal,
          cut: cut ?? Theme.of(context).colorScheme.surface,
          tickIdle: AppTheme.inkFaint.withValues(alpha: 0.45),
          labelColor: AppTheme.inkFaint,
          textScaler: textScaler,
        ),
      ),
    );
  }
}

/// The bar with ticks at 25, 50 and 75% and labels under it. A tick the fill
/// has passed is cut into the fill in the card colour; while the fill grows
/// past a tick, the tick pulses once. [glowAt] marks a milestone just reached.
class _MilestoneBarPainter extends CustomPainter {
  _MilestoneBarPainter({
    required this.fraction,
    required this.intro,
    required this.glow,
    required this.glowAt,
    required this.track,
    required this.fill,
    required this.cut,
    required this.tickIdle,
    required this.labelColor,
    required this.textScaler,
  });

  static const _barHeight = 8.0;
  static const _labelGap = 6.0;
  static const _labelSize = 10.0;
  static const _ticks = [0.25, 0.5, 0.75];
  static const _fillInterval = Interval(0.15, 0.75, curve: Curves.easeOutCubic);
  static const _pulse = 0.14;

  static double heightFor(TextScaler scaler) =>
      _barHeight + _labelGap + scaler.scale(_labelSize) * 1.3 + 1;

  final double fraction;
  final double intro;
  final double glow;
  final double? glowAt;
  final Color track;
  final Color fill;
  final Color cut;
  final Color tickIdle;
  final Color labelColor;
  final TextScaler textScaler;

  double _fillAt(double t) => fraction * _fillInterval.transform(t.clamp(0.0, 1.0));

  /// The intro value at which the growing fill reaches [x].
  double _crossingTime(double x) {
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (_fillAt(mid) < x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = _barHeight / 2;
    final shown = _fillAt(intro);
    final halo = Paint();

    // Halos sit behind the bar so only their soft edge shows around it.
    for (final x in _ticks) {
      if (fraction < x || intro >= 1) continue;
      final t = (intro - _crossingTime(x)) / _pulse;
      if (t <= 0 || t >= 1) continue;
      final a = math.sin(math.pi * t);
      halo.color = fill.withValues(alpha: 0.22 * a);
      canvas.drawCircle(Offset(w * x, cy), 4 + 4 * a, halo);
    }
    final at = glowAt;
    if (at != null && glow > 0 && glow < 1) {
      final a = math.sin(math.pi * glow);
      halo.color = fill.withValues(alpha: 0.32 * a);
      canvas.drawCircle(Offset(w * at, cy), 6 + 8 * a, halo);
    }

    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, _barHeight),
      const Radius.circular(_barHeight / 2),
    );
    canvas.drawRRect(bar, Paint()..color = track);
    if (shown > 0) {
      canvas.save();
      canvas.clipRRect(bar);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, math.max(w * shown, _barHeight), _barHeight),
          const Radius.circular(_barHeight / 2),
        ),
        Paint()..color = fill,
      );
      canvas.restore();
    }

    for (final x in _ticks) {
      final passed = w * shown >= w * x + 1;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(w * x, cy), width: 2, height: _barHeight),
        Paint()..color = passed ? cut : tickIdle,
      );
    }

    final style = TextStyle(
      fontFamily: AppTheme.sansFontName,
      fontSize: _labelSize,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: labelColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (final x in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final painter = TextPainter(
        text: TextSpan(text: x == 0 ? '0' : '${(x * 100).round()}%', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final dx = (w * x - painter.width / 2)
          .clamp(0.0, math.max(0.0, w - painter.width))
          .toDouble();
      painter.paint(canvas, Offset(dx, _barHeight + _labelGap));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_MilestoneBarPainter old) =>
      old.fraction != fraction ||
      old.intro != intro ||
      old.glow != glow ||
      old.glowAt != glowAt ||
      old.track != track ||
      old.fill != fill ||
      old.cut != cut ||
      old.tickIdle != tickIdle ||
      old.labelColor != labelColor ||
      old.textScaler != textScaler;
}
