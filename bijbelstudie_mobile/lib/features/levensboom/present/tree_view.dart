import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/palette.dart';
import '../domain/rng.dart';
import '../domain/tree_generator.dart';

/// The Levensboom, painted.
///
/// Two layers, for the same reason as the website's `TreeCanvas.tsx`. The
/// branches barely move, so they are recorded once into a [ui.Picture] and
/// re-drawn each frame under one small rotation about the trunk base - that is
/// the whole-canopy sway, for the cost of one `drawPicture`. Everything that
/// moves on its own phase (leaves, fireflies, motes) is painted live on top.
/// Without the split, a level-20 tree means re-tessellating ~300 tapered bezier
/// outlines sixty times a second on a phone, for no visible gain.
///
/// Honours `MediaQuery.disableAnimations` and the account's own
/// "minder beweging" pref: one static frame, no particles, no sway.
class TreeView extends StatefulWidget {
  const TreeView({
    super.key,
    required this.seed,
    required this.level,
    required this.frac,
    this.health = 1,
    this.reveal = 1,
    this.reducedMotion = false,
    this.palette,
    this.celebration = false,
    this.bloomFruit,
  });

  final String seed;
  final int level;

  /// xpIntoLevel / xpForNextLevel.
  final double frac;

  /// 0.3..1; below 1 the tree droops and sheds.
  final double health;

  /// 0..1. Below 1 the tree is mid grow-in - the celebration drives this.
  final double reveal;

  final bool reducedMotion;

  /// Overrides the device clock. Only the celebration uses it (night).
  final TreePalette? palette;

  /// Adds the rising column of light motes the level-up sequence calls for.
  final bool celebration;

  /// Index of a fruit to swell with a soft bloom, when a level-up unlocked one.
  final int? bloomFruit;

  @override
  State<TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends State<TreeView> with SingleTickerProviderStateMixin {
  /// One clock for everything, so the layers cannot drift apart. A minute per
  /// turn keeps the value coarse enough to avoid float noise in the sines.
  static const Duration _period = Duration(seconds: 60);

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _period,
  );

  final _BranchLayer _layer = _BranchLayer();

  late TreeScene _scene;
  late _Decor _decor;

  @override
  void initState() {
    super.initState();
    _scene = _build();
    _decor = _Decor(widget.seed);
  }

  @override
  void didUpdateWidget(TreeView old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed ||
        old.level != widget.level ||
        old.frac != widget.frac ||
        old.health != widget.health) {
      _scene = _build();
    }
    if (old.seed != widget.seed) _decor = _Decor(widget.seed);
    _syncClock();
  }

  TreeScene _build() => generateTree(
    seed: widget.seed,
    level: widget.level,
    frac: widget.frac,
    health: widget.health,
  );

  bool get _still =>
      widget.reducedMotion || MediaQuery.maybeDisableAnimationsOf(context) == true;

  void _syncClock() {
    if (_still) {
      if (_clock.isAnimating) _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void dispose() {
    _clock.dispose();
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        widget.palette ?? paletteForNow(health: widget.health);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          return CustomPaint(
            painter: _TreePainter(
              scene: _scene,
              palette: palette,
              decor: _decor,
              layer: _layer,
              reveal: widget.reveal,
              timeMs: _still ? 0 : _clock.value * _period.inMilliseconds,
              still: _still,
              level: widget.level,
              celebration: widget.celebration,
              bloomFruit: widget.bloomFruit,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

/// Motes and stars, drawn from their own stream so adding one can never shift
/// the tree's own random draws.
class _Decor {
  _Decor(String seed) {
    final rand = seededRng('$seed:decor');
    motes = [
      for (var i = 0; i < 18; i++)
        (
          x: rand() * 100,
          y: rand() * 100,
          r: 0.25 + rand() * 0.45,
          speed: 0.6 + rand() * 1.2,
          phase: rand(),
        ),
    ];
    stars = [
      for (var i = 0; i < 60; i++)
        (x: rand() * 100, y: rand() * 62, r: 0.15 + rand() * 0.3, phase: rand()),
    ];
    // Autumn's falling leaves and the level-25 blossom storm are the same
    // handful of drifters wearing different colours.
    drifters = [
      for (var i = 0; i < 14; i++)
        (
          x: rand() * 100,
          y: rand() * 100,
          size: 0.7 + rand() * 0.9,
          speed: 0.5 + rand() * 1.1,
          drift: 0.6 + rand() * 1.6,
          phase: rand(),
        ),
    ];
  }

  late final List<({double x, double y, double r, double speed, double phase})> motes;
  late final List<({double x, double y, double r, double phase})> stars;
  late final List<
    ({double x, double y, double size, double speed, double drift, double phase})
  >
  drifters;
}

/// The recorded branch layer plus the key it was recorded for.
class _BranchLayer {
  ui.Picture? picture;
  String? key;

  void dispose() {
    picture?.dispose();
    picture = null;
  }
}

const double _deg = math.pi / 180;

class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.scene,
    required this.palette,
    required this.decor,
    required this.layer,
    required this.reveal,
    required this.timeMs,
    required this.still,
    required this.level,
    required this.celebration,
    required this.bloomFruit,
  });

  final TreeScene scene;
  final TreePalette palette;
  final _Decor decor;
  final _BranchLayer layer;
  final double reveal;
  final double timeMs;
  final bool still;
  final int level;
  final bool celebration;
  final int? bloomFruit;

  /// The `seasons` trait (docs/levensboom-spec.md §6) arrives here.
  static const int _seasonsTraitLevel = 25;

  /// How much of a branch at [depth] is grown, for the celebration sequence.
  double _revealAt(int depth) {
    if (reveal >= 1) return 1;
    final t = reveal * (scene.maxDepth + 1) - depth;
    return t.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Frame what the tree actually occupies rather than the design box: a
    // sapling and a level-30 tree are wildly different heights, and a fixed box
    // leaves one a speck in an empty sky and the other cramped.
    final bounds = scene.bounds;
    final scale = math.min(
      size.width / bounds.width,
      size.height / bounds.height,
    );
    final originX = (size.width - bounds.width * scale) / 2 - bounds.minX * scale;
    // Bottom-anchored, so the ground line sits on the bottom edge.
    final originY = size.height - bounds.height * scale - bounds.minY * scale;
    final pivot = Offset(originX + kTrunkX * scale, originY + kGroundY * scale);

    _paintSky(canvas, size, originX, originY, scale);
    _paintGround(canvas, size, pivot, scale);

    final sway = still
        ? 0.0
        : math.sin(timeMs * 0.00042) * 0.85 + math.sin(timeMs * 0.00097) * 0.255;

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(sway * _deg);
    canvas.translate(-pivot.dx, -pivot.dy);

    _paintBranches(canvas, size, originX, originY, scale);
    _paintLeaves(canvas, originX, originY, scale);
    _paintOrnaments(canvas, originX, originY, scale);

    canvas.restore();

    _paintForeground(canvas, size, originX, originY, scale);
  }

  void _paintSky(
    Canvas canvas,
    Size size,
    double originX,
    double originY,
    double scale,
  ) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          [palette.skyTop, palette.skyBottom],
        ),
    );

    if (palette.night) {
      final star = Paint()..color = palette.light;
      for (final s in decor.stars) {
        final twinkle =
            0.45 + 0.55 * math.sin(timeMs * 0.0008 + s.phase * 6.283).abs();
        // Sky decoration is placed in viewport fractions, not tree space: the
        // tree is framed to its own bounds, so following it would bunch the
        // stars around the canopy instead of filling the sky.
        canvas.drawCircle(
          Offset(s.x / 100 * size.width, s.y / 100 * size.height),
          math.max(0.5, s.r * scale),
          star..color = palette.light.withValues(alpha: twinkle * 0.8),
        );
      }
    }

    // The glow, centred on the canopy wherever it happens to be for this level.
    final glowCentre = Offset(
      originX + kTrunkX * scale,
      originY + (scene.bounds.minY + kGroundY) / 2 * scale,
    );
    final glowRadius =
        math.max(30.0, (kGroundY - scene.bounds.minY) * 0.7) * scale;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(glowCentre, glowRadius, [
          palette.glow.withValues(alpha: 0.4),
          palette.glow.withValues(alpha: 0),
        ]),
    );
  }

  /// A band of earth the tree stands on, plus a soft shadow at the foot of the
  /// trunk. An opaque mound here reads as a brown lens floating in the sky,
  /// which is what the first pass drew.
  void _paintGround(Canvas canvas, Size size, Offset pivot, double scale) {
    final top = pivot.dy + 1.5 * scale;
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, size.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, size.height), [
          palette.ground,
          Color.lerp(palette.ground, palette.bark, 0.7)!,
        ]),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(pivot.dx, top + 0.8 * scale),
        width: 26 * scale,
        height: 3.6 * scale,
      ),
      Paint()..color = palette.bark.withValues(alpha: 0.28),
    );
  }

  void _paintBranches(
    Canvas canvas,
    Size size,
    double originX,
    double originY,
    double scale,
  ) {
    final key =
        '${scene.level}:${scene.health}:${size.width}x${size.height}:'
        '${palette.bark.toARGB32()}:${reveal.toStringAsFixed(3)}';

    if (layer.picture == null || layer.key != key) {
      final recorder = ui.PictureRecorder();
      final scratch = Canvas(recorder);
      _recordBranches(scratch, originX, originY, scale);
      layer.picture?.dispose();
      layer.picture = recorder.endRecording();
      layer.key = key;
    }
    canvas.drawPicture(layer.picture!);
  }

  void _recordBranches(
    Canvas canvas,
    double originX,
    double originY,
    double scale,
  ) {
    for (final branch in scene.branches) {
      final t = _revealAt(branch.depth);
      if (t <= 0) continue;

      final x0 = originX + branch.x0 * scale;
      final y0 = originY + branch.y0 * scale;
      final cx = originX + _lerp(branch.x0, branch.cx, t) * scale;
      final cy = originY + _lerp(branch.y0, branch.cy, t) * scale;
      final x1 = originX + _lerp(branch.x0, branch.x1, t) * scale;
      final y1 = originY + _lerp(branch.y0, branch.y1, t) * scale;

      final w0 = math.max(0.6, branch.w0 * scale / 2);
      final w1 = math.max(0.4, branch.w1 * scale * t / 2);

      final n0 = _normal(cx - x0, cy - y0);
      final n1 = _normal(x1 - cx, y1 - cy);
      final nm = Offset(
        (n0.dx + n1.dx) / 2 * ((w0 + w1) / 2),
        (n0.dy + n1.dy) / 2 * ((w0 + w1) / 2),
      );

      final path = Path()
        ..moveTo(x0 + n0.dx * w0, y0 + n0.dy * w0)
        ..quadraticBezierTo(cx + nm.dx, cy + nm.dy, x1 + n1.dx * w1, y1 + n1.dy * w1)
        ..lineTo(x1 - n1.dx * w1, y1 - n1.dy * w1)
        ..quadraticBezierTo(cx - nm.dx, cy - nm.dy, x0 - n0.dx * w0, y0 - n0.dy * w0)
        ..close();

      // Lit from the upper left, like the glow behind the canopy.
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x0 - w0, y0),
            Offset(x0 + w0, y0),
            [palette.barkLit, palette.bark],
          ),
      );
    }
  }

  void _paintLeaves(Canvas canvas, double originX, double originY, double scale) {
    final leafScale = (1.1 + 0.8 * scene.growth) * scale;
    final paint = Paint();

    for (final leaf in scene.leaves) {
      if (!leaf.visible) continue;
      final grown = _revealAt(leaf.depth);
      if (grown <= 0) continue;

      final shimmer =
          still ? 0.0 : math.sin(timeMs * 0.0021 + leaf.phase * 6.283);
      final x = originX + (leaf.x + shimmer * 0.35) * scale;
      final y = originY + leaf.y * scale;
      // A bud is a smaller, tighter version of the same leaf, so unfurling is a
      // size change rather than a pop-in.
      final size = leaf.size * leafScale * grown * (leaf.open ? 1 : 0.45);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((leaf.angle + shimmer * 6) * _deg);
      paint.color = (leaf.phase > 0.5 ? palette.leafAlt : palette.leaf)
          .withValues(alpha: leaf.open ? 1 : 0.75);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size * 0.6, 0),
          width: size * 2,
          height: size * 1.1,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintOrnaments(
    Canvas canvas,
    double originX,
    double originY,
    double scale,
  ) {
    final leafScale = (1.1 + 0.8 * scene.growth) * scale;

    final blossomColor = palette.blossom;
    if (blossomColor != null) {
      final paint = Paint()..color = blossomColor;
      for (final blossom in scene.blossoms) {
        canvas.drawCircle(
          Offset(originX + blossom.x * scale, originY + blossom.y * scale),
          blossom.size * leafScale * 0.8,
          paint,
        );
      }
    }

    final fruitPaint = Paint()..color = palette.fruit;
    final shinePaint = Paint()..color = palette.light.withValues(alpha: 0.5);
    for (final fruit in scene.fruits) {
      final centre = Offset(originX + fruit.x * scale, originY + fruit.y * scale);
      // The fruit a level-up just unlocked swells and carries a soft bloom, so
      // the eye is told which one is new.
      final blooming = bloomFruit != null && fruit.index == bloomFruit;
      final swell = blooming && !still
          ? 1 + 0.28 * (0.5 + 0.5 * math.sin(timeMs * 0.0026))
          : 1.0;
      final size = math.max(1.4, fruit.size * leafScale * 1.15) * swell;

      if (blooming) {
        canvas.drawCircle(
          centre,
          size * 4.5,
          Paint()
            ..shader = ui.Gradient.radial(centre, size * 4.5, [
              palette.light.withValues(alpha: 0.53),
              palette.light.withValues(alpha: 0),
            ]),
        );
      }

      canvas.drawCircle(centre, size, fruitPaint);
      // One highlight dot: enough to read as round rather than as a sticker.
      canvas.drawCircle(centre.translate(-size * 0.3, -size * 0.3), size * 0.3, shinePaint);
    }

    // Snow on the branches (level 25+, winter). Drawn inside the swaying
    // transform so the load rides with the tree.
    if (level >= _seasonsTraitLevel && palette.season == Season.winter) {
      final snow = Paint()..color = const Color(0xE6F2F6FA);
      for (final branch in scene.branches) {
        if (branch.depth < scene.maxDepth - 2) continue;
        if (_revealAt(branch.depth) <= 0) continue;
        final n = _normal(branch.x1 - branch.cx, branch.y1 - branch.cy);
        // Only the upward-facing side carries snow.
        final side = n.dy < 0 ? 1.0 : -1.0;
        final w = math.max(0.7, branch.w0 * scale * 0.75);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              originX + branch.cx * scale + n.dx * side * w,
              originY + branch.cy * scale + n.dy * side * w,
            ),
            width: w * 3,
            height: w * 1.4,
          ),
          snow,
        );
      }
    }

    final bird = scene.bird;
    if (bird != null) {
      final x = originX + bird.x * scale;
      final y = originY + bird.y * scale;
      final s = math.max(2.0, 2.6 * scale);
      canvas.drawPath(
        Path()
          ..moveTo(x - s, y)
          ..quadraticBezierTo(x - s * 0.4, y - s * 0.7, x, y)
          ..quadraticBezierTo(x + s * 0.4, y - s * 0.7, x + s, y),
        Paint()
          ..color = palette.bark
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.0, 0.45 * scale),
      );
    }
  }

  void _paintForeground(
    Canvas canvas,
    Size size,
    double originX,
    double originY,
    double scale,
  ) {
    if (palette.night && scene.fireflies.isNotEmpty) {
      final paint = Paint();
      for (final fly in scene.fireflies) {
        final pulse =
            0.25 + 0.75 * math.sin(timeMs * 0.0013 + fly.phase * 6.283).abs();
        final drift =
            still ? 0.0 : math.sin(timeMs * 0.0005 + fly.phase * 6.283) * 1.6;
        canvas.drawCircle(
          Offset(originX + (fly.x + drift) * scale, originY + fly.y * scale),
          0.6 * scale,
          paint..color = const Color(0xFFFFE9A8).withValues(alpha: pulse),
        );
      }
    }

    // Drifting petals and falling leaves. Autumn drops the occasional leaf for
    // everyone; the blossom storm is the level-25 `seasons` trait and only
    // blows in spring. Both are the same drifters, so a season change costs a
    // colour and nothing else.
    final hasSeasons = level >= _seasonsTraitLevel;
    final blossom = palette.blossom;
    final drifterColor = palette.season == Season.autumn
        ? palette.leafAlt
        : (hasSeasons && palette.season == Season.spring && blossom != null)
        ? blossom
        : null;
    if (drifterColor != null) {
      // Three at a time in autumn - "occasional" is the point, and a constant
      // fall reads as the tree dying rather than as the season.
      final shown = palette.season == Season.autumn ? 3 : decor.drifters.length;
      final drifterPaint = Paint()..color = drifterColor.withValues(alpha: 0.75);
      for (var i = 0; i < shown; i++) {
        final d = decor.drifters[i];
        final fall = still ? 0.0 : (timeMs * 0.0055 * d.speed) % 130;
        final y = ((d.y + fall) % 130 + 130) % 130 - 15;
        if (y > 100 || y < 0) continue;
        final swayX =
            still ? 0.0 : math.sin(timeMs * 0.0012 + d.phase * 6.283) * d.drift * 3;
        canvas.save();
        canvas.translate((d.x + swayX) / 100 * size.width, y / 100 * size.height);
        canvas.rotate(still ? 0 : timeMs * 0.0016 + d.phase * 6.283);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: d.size * 2 * scale,
            height: d.size * scale,
          ),
          drifterPaint,
        );
        canvas.restore();
      }
    }

    // The level-up column of light.
    if (celebration && !still) {
      final columnX = originX + kTrunkX * scale;
      final groundY = originY + kGroundY * scale;
      final column = Paint();
      for (var i = 0; i < 22; i++) {
        final phase = (i / 22 + timeMs * 0.00022) % 1;
        final y = groundY - phase * (groundY - originY);
        final spread = (1 - phase) * 9 * scale;
        canvas.drawCircle(
          Offset(columnX + math.sin(timeMs * 0.0015 + i) * spread, y),
          math.max(0.7, 0.7 * scale),
          column
            ..color = palette.light.withValues(
              alpha: (0.5 * math.sin(phase * math.pi)).clamp(0.0, 1.0),
            ),
        );
      }
    }

    // Pollen in the sunbeam. Cheap, and most of what makes a still image read
    // as a living scene.
    final paint = Paint();
    for (final mote in decor.motes) {
      final rise = still ? 0.0 : (timeMs * 0.004 * mote.speed) % 100;
      final y = ((mote.y - rise) % 100 + 100) % 100;
      final wobble =
          still ? 0.0 : math.sin(timeMs * 0.0009 + mote.phase * 6.283) * 1.2;
      final alpha =
          0.16 + 0.14 * math.sin(timeMs * 0.001 + mote.phase * 6.283);
      // Viewport space, like the stars: pollen belongs to the air, not to the
      // tree's own framed bounds.
      canvas.drawCircle(
        Offset((mote.x + wobble) / 100 * size.width, y / 100 * size.height),
        math.max(0.6, mote.r * scale),
        paint..color = palette.light.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.timeMs != timeMs ||
      old.scene != scene ||
      old.reveal != reveal ||
      old.palette != palette ||
      old.celebration != celebration ||
      old.bloomFruit != bloomFruit;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

Offset _normal(double dx, double dy) {
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return const Offset(0, 0);
  return Offset(-dy / length, dx / length);
}
