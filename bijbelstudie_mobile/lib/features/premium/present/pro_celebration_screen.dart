import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/pro_benefits.dart';

/// `/pro-welkom` - the moment right after Pro is bought or restored.
///
/// It replaces the paywall in the stack (`PremiumScreen` navigates here with
/// `pushReplacement`), so "Aan de slag" and the system back both return to
/// wherever the reader opened the paywall from, never to the paywall itself.
/// A reader who arrived by deep link, with nothing underneath, lands on Start.
///
/// The motion is one burst, not a loop: the badge pops in with a glow and a
/// ring, a spray of confetti in the brand colours falls through the screen,
/// and the unlocked benefits settle in one after another. With reduced motion
/// on, everything is simply there - the confetti is skipped entirely.
class ProCelebrationScreen extends StatefulWidget {
  const ProCelebrationScreen({super.key});

  @override
  State<ProCelebrationScreen> createState() => _ProCelebrationScreenState();
}

class _ProCelebrationScreenState extends State<ProCelebrationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  /// Seeded, so the burst has the same shape every time - it is decoration,
  /// and a fixed arrangement is one that was actually looked at.
  final List<_Particle> _particles = _Particle.scatter(math.Random(20260916), 64);

  final GlobalKey _badgeKey = GlobalKey();
  final GlobalKey _layerKey = GlobalKey();

  bool _started = false;
  bool _landed = false;

  /// Icons for the benefits the paywall names; anything added to
  /// [kProBenefits] later still gets a check mark.
  static const Map<String, IconData> _benefitIcons = {
    'Offline lezen': Icons.download_for_offline_outlined,
    'Alle commentaren': Icons.chat_bubble_outline,
    'Grondtekst': Icons.translate,
    'Meer AI-vragen': Icons.auto_awesome_outlined,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      // Everything in its final place, no confetti. One tap still marks the
      // moment - haptics are not motion.
      _intro.value = 1;
      _burst.value = 1;
      _haptic(HapticFeedback.mediumImpact);
      return;
    }

    _haptic(HapticFeedback.heavyImpact);
    _intro
      ..addListener(_onIntroTick)
      ..forward();
    _burst.forward();
  }

  /// A second, lighter tap as the badge lands, so the arrival is felt as well
  /// as seen. Driven by the controller rather than a timer so nothing is left
  /// pending if the screen closes early.
  void _onIntroTick() {
    if (_landed || _intro.value < 0.2) return;
    _landed = true;
    _haptic(HapticFeedback.mediumImpact);
  }

  /// Haptics are decoration: a device or test host without the platform
  /// handler must not turn them into an error.
  void _haptic(Future<void> Function() impact) {
    unawaited(impact().catchError((Object _) {}));
  }

  void _done() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  /// Where the burst starts: the badge's centre, in the confetti layer's own
  /// coordinates. Resolved at paint time, after layout, so it follows the
  /// badge wherever the column puts it on this screen size.
  Offset? _badgeCentre() {
    final badge = _badgeKey.currentContext?.findRenderObject() as RenderBox?;
    final layer = _layerKey.currentContext?.findRenderObject() as RenderBox?;
    if (badge == null || layer == null || !badge.hasSize || !badge.attached || !layer.attached) {
      return null;
    }
    return layer.globalToLocal(badge.localToGlobal(badge.size.center(Offset.zero)));
  }

  @override
  void dispose() {
    _intro.removeListener(_onIntroTick);
    _intro.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final confetti = [
      AppTheme.teal,
      AppTheme.lapis,
      AppTheme.flame,
      AppTheme.vermilion,
      AppTheme.positive,
      AppTheme.tealSoft,
    ];

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: Stack(
        children: [
          // A wash of brand colour from the top, fading into the page.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.tealTint, AppTheme.paper],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 28),
                                _ProBadge(key: _badgeKey, progress: _intro),
                                const SizedBox(height: 28),
                                _Reveal(
                                  progress: _intro,
                                  begin: 0.22,
                                  end: 0.5,
                                  child: Column(
                                    children: [
                                      SiteBadge.teal(
                                        'BijbelStudie Pro',
                                        icon: Icons.workspace_premium_outlined,
                                      ),
                                      const SizedBox(height: 14),
                                      Semantics(
                                        header: true,
                                        child: Text(
                                          'Welkom bij Pro',
                                          textAlign: TextAlign.center,
                                          style: AppTheme.displayLarge,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _Reveal(
                                  progress: _intro,
                                  begin: 0.3,
                                  end: 0.58,
                                  child: Text(
                                    'Dank je wel. Je abonnement is actief en dit '
                                    'staat nu allemaal voor je open.',
                                    textAlign: TextAlign.center,
                                    style: AppTheme.bodyLead,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                AppCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < kProBenefits.length; i++)
                                        _Reveal(
                                          progress: _intro,
                                          begin: 0.42 + i * 0.09,
                                          end: 0.72 + i * 0.07,
                                          child: _BenefitRow(
                                            icon: _benefitIcons[kProBenefits[i].$1] ??
                                                Icons.check,
                                            title: kProBenefits[i].$1,
                                            body: kProBenefits[i].$2,
                                            showRule: i < kProBenefits.length - 1,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _Reveal(
                      progress: _intro,
                      begin: 0.7,
                      end: 1,
                      child: SiteButton(
                        label: 'Aan de slag',
                        trailingIcon: Icons.arrow_forward,
                        onPressed: _done,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Above the content, and never in the way of a tap.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: _layerKey,
                painter: _BurstPainter(
                  progress: _burst,
                  particles: _particles,
                  colors: confetti,
                  originOf: _badgeCentre,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Pro medallion: pops in on an elastic scale, with a glow that swells
/// as it lands and a soft halo behind it.
class _ProBadge extends StatelessWidget {
  const _ProBadge({super.key, required this.progress});

  final Animation<double> progress;

  static const double _size = 124;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return SizedBox(
      width: _size + 72,
      height: _size + 72,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, child) {
          final t = progress.value;
          final pop = const Interval(0, 0.45, curve: Curves.elasticOut).transform(t);
          final appear = const Interval(0, 0.12, curve: Curves.easeOut).transform(t);
          final glow = const Interval(0.08, 0.55, curve: Curves.easeOutCubic).transform(t);
          return Opacity(
            opacity: appear,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Halo.
                Container(
                  width: _size + 60 * glow,
                  height: _size + 60 * glow,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.teal.withValues(alpha: 0.12 * glow),
                  ),
                ),
                Transform.scale(scale: pop, child: child),
              ],
            ),
          );
        },
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.teal, AppTheme.tealStrong],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.teal.withValues(alpha: 0.4),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            size: 62,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.showRule,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showRule;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: showRule ? Border(bottom: BorderSide(color: AppTheme.rule)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.tealTint,
            ),
            child: Icon(icon, size: 17, color: AppTheme.teal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.bodyStrong),
                const SizedBox(height: 2),
                Text(body, style: AppTheme.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Icon(Icons.check_rounded, size: 18, color: AppTheme.positive),
          ),
        ],
      ),
    );
  }
}

/// Fades and lifts [child] in over the [begin]-[end] slice of [progress].
///
/// Computes the interval by hand on each tick instead of building a
/// `CurvedAnimation`, which would attach a listener per rebuild.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.progress,
    required this.begin,
    required this.end,
    required this.child,
  });

  final Animation<double> progress;
  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final t = Interval(
          begin.clamp(0.0, 1.0),
          end.clamp(0.0, 1.0),
          curve: Curves.easeOutCubic,
        ).transform(progress.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
        );
      },
    );
  }
}

/// One piece of confetti's launch parameters.
class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.colorIndex,
    required this.round,
    required this.delay,
  });

  /// Launch direction in radians; a wide fan pointing mostly upward.
  final double angle;

  /// Launch speed in logical pixels per second.
  final double speed;
  final double size;

  /// Rotation in radians per second.
  final double spin;
  final int colorIndex;

  /// Dots rather than strips.
  final bool round;

  /// Share of the burst to wait before launching, so it does not leave as
  /// one flat ring.
  final double delay;

  static List<_Particle> scatter(math.Random random, int count) => [
    for (var i = 0; i < count; i++)
      _Particle(
        angle: -math.pi / 2 + (random.nextDouble() * 2 - 1) * math.pi * 0.8,
        speed: 280 + random.nextDouble() * 360,
        size: 5 + random.nextDouble() * 5,
        spin: (random.nextDouble() * 2 - 1) * 9,
        colorIndex: random.nextInt(1 << 16),
        round: random.nextDouble() < 0.3,
        delay: random.nextDouble() * 0.12,
      ),
  ];
}

/// Paints the confetti and the shock ring for one run of [progress].
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.progress,
    required this.particles,
    required this.colors,
    required this.originOf,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final List<_Particle> particles;
  final List<Color> colors;
  final Offset? Function() originOf;

  /// Real time the burst covers, for the physics.
  static const double _seconds = 2.6;
  static const double _drag = 2.4;
  static const double _gravity = 220;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1 || colors.isEmpty) return;
    final origin = originOf() ?? Offset(size.width / 2, size.height * 0.3);

    // The ring: one expanding stroke as the badge lands.
    final ringT = (t / 0.3).clamp(0.0, 1.0);
    if (ringT < 1) {
      final eased = Curves.easeOutCubic.transform(ringT);
      canvas.drawCircle(
        origin,
        66 + 160 * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5 + 3 * (1 - eased)
          ..color = colors.first.withValues(alpha: 0.5 * (1 - ringT)),
      );
    }

    final paint = Paint();
    for (final p in particles) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final secs = local * _seconds;
      // Air drag slows the launch; gravity takes over for the fall.
      final travel = p.speed * (1 - math.exp(-_drag * secs)) / _drag;
      final dx = math.cos(p.angle) * travel;
      final dy = math.sin(p.angle) * travel + 0.5 * _gravity * secs * secs;
      final fade = local < 0.6 ? 1.0 : 1 - Curves.easeIn.transform((local - 0.6) / 0.4);
      if (fade <= 0) continue;

      paint.color = colors[p.colorIndex % colors.length].withValues(alpha: fade);
      canvas
        ..save()
        ..translate(origin.dx + dx, origin.dy + dy)
        ..rotate(p.spin * secs);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.45),
            const Radius.circular(1),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.particles != particles || !_sameColors(oldDelegate.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
