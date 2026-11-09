import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'guide_cues.dart';

/// A hand acting out the gesture the guide asks for, on the spot where it has
/// to happen: a tap, a press-and-hold (a ring fills while the finger stays
/// down) or a swipe across the text.
///
/// Painted over the app and never hit-tested - it shows the reader what to do
/// without ever being in the way of doing it. Under reduced motion it stands
/// still at the spot, with the ring drawn once.
class GuideHand extends StatefulWidget {
  const GuideHand({
    super.key,
    required this.gesture,
    required this.point,
    this.reducedMotion = false,
  });

  final GuideGesture gesture;

  /// Where the fingertip lands, in the coordinates of the enclosing stack.
  final Offset point;
  final bool reducedMotion;

  @override
  State<GuideHand> createState() => _GuideHandState();
}

class _GuideHandState extends State<GuideHand> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _cycleFor(widget.gesture),
  );

  static Duration _cycleFor(GuideGesture gesture) => switch (gesture) {
    GuideGesture.longPress => const Duration(milliseconds: 2200),
    GuideGesture.swipeLeft => const Duration(milliseconds: 2000),
    _ => const Duration(milliseconds: 1600),
  };

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(GuideHand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gesture != widget.gesture || oldWidget.reducedMotion != widget.reducedMotion) {
      _clock.duration = _cycleFor(widget.gesture);
      _run();
    }
  }

  void _run() {
    if (widget.reducedMotion || widget.gesture == GuideGesture.none) {
      _clock.stop();
      _clock.value = widget.gesture == GuideGesture.longPress ? 0.6 : 0.4;
    } else {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gesture == GuideGesture.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final pose = GuideHandPose.at(widget.gesture, _clock.value);
          final tip = widget.point + pose.offset;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TouchPainter(
                    gesture: widget.gesture,
                    point: widget.point,
                    tip: tip,
                    pose: pose,
                  ),
                ),
              ),
              Positioned(
                left: tip.dx - GuideHandPose.tipX,
                top: tip.dy - GuideHandPose.tipY,
                child: Opacity(
                  opacity: pose.opacity,
                  child: Transform.scale(
                    scale: pose.scale,
                    alignment: const Alignment(-0.1, -0.85),
                    child: const _HandGlyph(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HandGlyph extends StatelessWidget {
  const _HandGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: GuideHandPose.size,
      height: GuideHandPose.size,
      child: Stack(
        children: [
          // A dark halo under a white hand reads on the paper of the reader
          // and on a dark sheet alike.
          Icon(
            Icons.pan_tool_alt_rounded,
            size: GuideHandPose.size,
            color: const Color(0xFF0F172A),
            shadows: const [Shadow(color: Color(0x660F172A), blurRadius: 10, offset: Offset(0, 3))],
          ),
          Padding(
            padding: const EdgeInsets.all(2.2),
            child: Icon(
              Icons.pan_tool_alt_rounded,
              size: GuideHandPose.size - 4.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the hand is at time [t] of one cycle. Public and pure so the motion
/// can be checked without pumping frames.
class GuideHandPose {
  const GuideHandPose({
    required this.offset,
    required this.opacity,
    required this.scale,
    required this.ripple,
    required this.ring,
    required this.trail,
  });

  static const double size = 46;

  /// The fingertip inside the glyph, measured on `pan_tool_alt`.
  static const double tipX = size * 0.43;
  static const double tipY = size * 0.10;

  /// How far a swipe travels, either side of its point.
  static const double swipeReach = 72;

  /// From the target point to the fingertip.
  final Offset offset;
  final double opacity;
  final double scale;

  /// 0..1 progress of the expanding ring of a tap; 0 when there is none.
  final double ripple;

  /// 0..1 of the press-and-hold ring that fills; 0 when there is none.
  final double ring;

  /// 0..1 strength of the swipe's trail.
  final double trail;

  static double _seg(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  static GuideHandPose at(GuideGesture gesture, double t) {
    final ease = Curves.easeOutCubic;
    switch (gesture) {
      case GuideGesture.tap:
        final inT = ease.transform(_seg(t, 0, 0.3));
        final press = _seg(t, 0.3, 0.42);
        final lift = _seg(t, 0.42, 0.62);
        return GuideHandPose(
          offset: Offset(14 * (1 - inT), 22 * (1 - inT)) + Offset(0, -6 * lift),
          opacity: _fade(t, 0.15, 0.8),
          scale: 1 - 0.1 * math.sin(math.pi * press),
          ripple: _seg(t, 0.36, 0.86),
          ring: 0,
          trail: 0,
        );
      case GuideGesture.longPress:
        final inT = ease.transform(_seg(t, 0, 0.18));
        final hold = _seg(t, 0.2, 0.72);
        final lift = _seg(t, 0.74, 0.9);
        return GuideHandPose(
          offset: Offset(14 * (1 - inT), 22 * (1 - inT)) + Offset(0, -8 * lift),
          opacity: _fade(t, 0.12, 0.88),
          scale: hold > 0 && lift == 0 ? 0.9 : 1,
          ripple: _seg(t, 0.72, 0.95),
          ring: lift > 0 ? 0 : hold,
          trail: 0,
        );
      case GuideGesture.swipeLeft:
        final move = Curves.easeInOutCubic.transform(_seg(t, 0.15, 0.7));
        return GuideHandPose(
          offset: Offset(swipeReach - 2 * swipeReach * move, 0),
          opacity: _fade(t, 0.12, 0.78),
          scale: t > 0.12 && t < 0.72 ? 0.94 : 1,
          ripple: 0,
          ring: 0,
          trail: t < 0.15 ? 0 : (t <= 0.7 ? 1 : 1 - _seg(t, 0.7, 0.85)),
        );
      case GuideGesture.none:
        return const GuideHandPose(
          offset: Offset.zero,
          opacity: 0,
          scale: 1,
          ripple: 0,
          ring: 0,
          trail: 0,
        );
    }
  }

  /// In by [inBy], out from [outFrom] to the end of the cycle.
  static double _fade(double t, double inBy, double outFrom) {
    if (t < inBy) return _seg(t, 0, inBy);
    if (t > outFrom) return 1 - _seg(t, outFrom, 1);
    return 1;
  }
}

class _TouchPainter extends CustomPainter {
  _TouchPainter({
    required this.gesture,
    required this.point,
    required this.tip,
    required this.pose,
  });

  final GuideGesture gesture;
  final Offset point;
  final Offset tip;
  final GuideHandPose pose;

  @override
  void paint(Canvas canvas, Size size) {
    final teal = AppTheme.teal;

    // A soft spot under the target, so the place itself is marked even
    // between two cycles of the hand.
    if (gesture != GuideGesture.swipeLeft) {
      canvas.drawCircle(
        point,
        20,
        Paint()..color = teal.withValues(alpha: 0.16 * pose.opacity),
      );
    }

    if (pose.ripple > 0 && pose.ripple < 1) {
      final r = 10 + 26 * Curves.easeOut.transform(pose.ripple);
      canvas.drawCircle(
        point,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = teal.withValues(alpha: 0.7 * (1 - pose.ripple)),
      );
    }

    if (pose.ring > 0) {
      final rect = Rect.fromCircle(center: point, radius: 22);
      canvas.drawCircle(
        point,
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.white.withValues(alpha: 0.85),
      );
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * pose.ring,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = teal,
      );
    }

    if (gesture == GuideGesture.swipeLeft && pose.trail > 0) {
      final start = point + const Offset(GuideHandPose.swipeReach, 0);
      final shader = LinearGradient(
        colors: [teal.withValues(alpha: 0), teal.withValues(alpha: 0.55 * pose.trail)],
      ).createShader(Rect.fromPoints(start, tip));
      canvas.drawLine(
        start,
        tip,
        Paint()
          ..shader = shader
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // A new pose every frame of the cycle; nothing to compare it by.
  @override
  bool shouldRepaint(_TouchPainter old) => true;
}
