import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../domain/palette.dart';
import '../domain/scene_cache.dart';
import '../domain/scenes.dart';
import '../domain/species.dart';
import '../domain/tree_generator.dart';
import 'backdrop_painter.dart';

export 'backdrop_painter.dart' show TreeFrame, TreeFraming, TreeDecor, measureTreeFrame;

/// The Levensboom, painted.
///
/// Two layers, for the same reason as the website's `TreeCanvas.tsx`. The
/// branches barely move, so they are recorded once into a [ui.Picture] and
/// re-drawn each frame under one small rotation about the trunk base - that is
/// the whole-canopy sway, for the cost of one `drawPicture`. Everything that
/// moves on its own phase (leaves, animals, motes) is painted live on top.
///
/// Two framings. [TreeFraming.scene] is the landscape: sky, backdrop, a band
/// of earth the trunk stands *in*, animals. [TreeFraming.portrait] is the
/// avatar: the tree alone on a sky disc, cropped to its own bounds, for the
/// tab bar and every other place a 24 px face has to read.
///
/// Honours `MediaQuery.disableAnimations`, the account's own "minder beweging"
/// pref and [TreeView.still]: one static frame, no particles, no sway. Species,
/// scene and animal never touch the generator - they are paint.

class TreeView extends StatefulWidget {
  const TreeView({
    super.key,
    required this.seed,
    required this.level,
    required this.frac,
    this.health = 1,
    this.species = kDefaultSpecies,
    this.scene = kDefaultScene,
    this.animal = kDefaultAnimal,
    this.framing = TreeFraming.scene,
    this.reveal = 1,
    this.reducedMotion = false,
    this.still = false,
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

  final TreeSpecies species;
  final TreeSceneId scene;
  final TreeAnimal animal;
  final TreeFraming framing;

  /// 0..1. Below 1 the tree is mid grow-in - the celebration drives this.
  final double reveal;

  final bool reducedMotion;

  /// Never animate, whatever the size. Tiles, thumbnails, the tab bar.
  final bool still;

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

  final BranchLayer _layer = BranchLayer();

  late TreeScene _scene;
  late TreeDecor _decor;

  @override
  void initState() {
    super.initState();
    _scene = _build();
    _decor = TreeDecor(widget.seed);
  }

  @override
  void didUpdateWidget(TreeView old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed ||
        old.level != widget.level ||
        old.frac != widget.frac ||
        old.health != widget.health ||
        old.species != widget.species ||
        old.framing != widget.framing) {
      _scene = _build();
    }
    if (old.seed != widget.seed) _decor = TreeDecor(widget.seed);
    _syncClock();
  }

  TreeScene _build() => cachedTree(
    seed: widget.seed,
    level: widget.level,
    frac: widget.frac,
    health: widget.health,
    species: widget.species,
    fracBucket: widget.framing == TreeFraming.portrait ? 20 : 0,
  );

  bool get _still =>
      widget.still ||
      widget.reducedMotion ||
      MediaQuery.maybeDisableAnimationsOf(context) == true;

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
    final palette = widget.palette ??
        paletteForNow(
          health: widget.health,
          scene: widget.scene,
          species: widget.species,
        );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          return CustomPaint(
            painter: TreePainter(
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
              framing: widget.framing,
              animal: widget.animal,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}


/// The recorded branch layer plus the key it was recorded for.
class BranchLayer {
  ui.Picture? picture;
  String? key;

  void dispose() {
    picture?.dispose();
    picture = null;
  }
}


class TreePainter extends CustomPainter with SceneLayers {
  TreePainter({
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
    this.framing = TreeFraming.scene,
    this.animal = kDefaultAnimal,
  });

  @override
  final TreeScene scene;
  @override
  final TreePalette palette;
  @override
  final TreeDecor decor;
  final BranchLayer layer;
  final double reveal;
  @override
  final double timeMs;
  @override
  final bool still;
  @override
  final int level;
  @override
  final bool celebration;
  final int? bloomFruit;
  @override
  final TreeFraming framing;
  @override
  final TreeAnimal animal;



  /// How much of a branch at [depth] is grown, for the celebration sequence.
  double _revealAt(int depth) {
    if (reveal >= 1) return 1;
    final t = reveal * (scene.maxDepth + 1) - depth;
    return t.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = measureTreeFrame(size, scene, framing, animal, decor);
    paintSky(canvas, frame);
    paintGround(canvas, frame);

    final sway = still
        ? 0.0
        : math.sin(timeMs * 0.00042) * 0.85 + math.sin(timeMs * 0.00097) * 0.255;

    canvas.save();
    canvas.translate(frame.pivotX, frame.pivotY);
    canvas.rotate(sway * kDeg);
    canvas.translate(-frame.pivotX, -frame.pivotY);

    _paintBranches(canvas, frame);
    _paintLeaves(canvas, frame);
    _paintOrnaments(canvas, frame);

    canvas.restore();

    paintForeground(canvas, frame);
  }


  // --------------------------------------------------------------- tree

  void _paintBranches(Canvas canvas, TreeFrame frame) {
    final key =
        '${scene.level}:${scene.health}:${kSpeciesIds[scene.species]}:'
        '${frame.width}x${frame.height}:${framing.name}:${animal.name}:'
        '${palette.bark.toARGB32()}:${reveal.toStringAsFixed(3)}';

    if (layer.picture == null || layer.key != key) {
      final recorder = ui.PictureRecorder();
      final scratch = Canvas(recorder);
      recordBranches(scratch, frame);
      layer.picture?.dispose();
      layer.picture = recorder.endRecording();
      layer.key = key;
    }
    canvas.drawPicture(layer.picture!);
  }

  /// The branch outlines, drawn straight (no layer): the notification image
  /// renderer uses this directly.
  void recordBranches(Canvas canvas, TreeFrame frame) {
    final originX = frame.originX;
    final originY = frame.originY;
    final scale = frame.scale;
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

  /// One leaf at the origin pointing along +x. `size` is already in pixels;
  /// [down] is world-down in the leaf's rotated frame, for the frond's droop.
  Path _leafPath(LeafShape shape, double size, double scale, Offset down) {
    final path = Path();
    switch (shape) {
      case LeafShape.narrow:
        path.addOval(Rect.fromCenter(center: Offset(size * 0.7, 0), width: size * 2.6, height: size * 0.64));
      case LeafShape.large:
        path.addOval(Rect.fromCenter(center: Offset(size * 0.65, 0), width: size * 2.1, height: size * 1.7));
      case LeafShape.almond:
        path.addOval(Rect.fromCenter(center: Offset(size * 0.65, 0), width: size * 2.3, height: size * 0.84));
      case LeafShape.needle:
        // A tuft of needles; a single stroke at avatar sizes.
        final length = size * 1.6;
        final fan = scale > 1.6 ? const [-40.0, -20.0, 0.0, 20.0, 40.0] : const [0.0];
        for (final a in fan) {
          path
            ..moveTo(0, 0)
            ..lineTo(math.cos(a * kDeg) * length, math.sin(a * kDeg) * length);
        }
      case LeafShape.frond:
        final length = size * 3.2;
        final w = size * 0.42;
        final tipX = length + down.dx * length * 0.18;
        final tipY = down.dy * length * 0.26;
        path
          ..moveTo(0, -w)
          ..quadraticBezierTo(length * 0.55, -w * 0.7 + tipY * 0.3, tipX, tipY)
          ..quadraticBezierTo(length * 0.55, w * 0.7 + tipY * 0.3, 0, w)
          ..close();
      case LeafShape.oval:
        path.addOval(Rect.fromCenter(center: Offset(size * 0.6, 0), width: size * 2, height: size * 1.1));
    }
    return path;
  }

  void _paintLeaves(Canvas canvas, TreeFrame frame) {
    final originX = frame.originX;
    final originY = frame.originY;
    final scale = frame.scale;
    final leafScale = (1.1 + 0.8 * scene.growth) * scale;
    final shape = sp.leafShape;
    final fill = Paint();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, 0.32 * scale);
    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final leaf in scene.leaves) {
      if (!leaf.visible) continue;
      final grown = _revealAt(leaf.depth);
      if (grown <= 0) continue;

      final shimmer = still ? 0.0 : math.sin(timeMs * 0.0021 + leaf.phase * 6.283);
      final x = originX + (leaf.x + shimmer * 0.35) * scale;
      final y = originY + leaf.y * scale;
      // A bud is a smaller, tighter version of the same leaf, so unfurling is a
      // size change rather than a pop-in.
      final size = leaf.size * leafScale * grown * (leaf.open ? 1 : 0.45);
      final angle = leaf.angle + shimmer * (shape == LeafShape.frond ? 2 : 6);
      final colour = (leaf.phase > 0.5 ? palette.leafAlt : palette.leaf)
          .withValues(alpha: leaf.open ? 1 : 0.75);
      final down = Offset(math.cos((90 - angle) * kDeg), math.sin((90 - angle) * kDeg));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle * kDeg);
      final path = _leafPath(shape, size, scale, down);
      if (shape == LeafShape.needle) {
        canvas.drawPath(path, stroke..color = colour);
      } else {
        canvas.drawPath(path, fill..color = colour);
        if (shape == LeafShape.frond || shape == LeafShape.large) {
          rib
            ..color = leaf.phase > 0.5 ? palette.leaf : palette.leafAlt
            ..strokeWidth = math.max(0.5, size * 0.08);
          canvas.drawLine(
            Offset.zero,
            Offset(size * (shape == LeafShape.frond ? 2.9 : 1.5), 0),
            rib,
          );
          // Leaflets either side of the rib, where there is room to see them.
          if (shape == LeafShape.frond && scale > 1.4) {
            final length = size * 3.2;
            rib.strokeWidth = math.max(0.5, size * 0.06);
            for (var k = 1; k <= 6; k++) {
              final at = k / 7 * length;
              final reach = size * 0.9 * (1 - k / 9);
              canvas.drawLine(Offset(at, 0), Offset(at + reach * 0.55, -reach), rib);
              canvas.drawLine(Offset(at, 0), Offset(at + reach * 0.55, reach), rib);
            }
          }
        }
      }
      canvas.restore();
    }
  }

  void _drawFruit(Canvas canvas, FruitStyle style, Offset c, double size) {
    final paint = Paint()..color = palette.fruit;
    switch (style) {
      case FruitStyle.olive:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(0.5);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size * 1.5, height: size * 1.1), paint);
        canvas.restore();
      case FruitStyle.fig:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - size * 1.1)
            ..quadraticBezierTo(c.dx + size * 1.15, c.dy - size * 0.2, c.dx + size * 0.55, c.dy + size * 0.75)
            ..quadraticBezierTo(c.dx, c.dy + size * 1.05, c.dx - size * 0.55, c.dy + size * 0.75)
            ..quadraticBezierTo(c.dx - size * 1.15, c.dy - size * 0.2, c.dx, c.dy - size * 1.1),
          paint,
        );
      case FruitStyle.dates:
        for (final (ox, oy) in const [(-0.5, 0.1), (0.5, 0.1), (0.0, 0.75)]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(c.dx + ox * size, c.dy + oy * size),
              width: size * 0.84,
              height: size * 1.2,
            ),
            paint,
          );
        }
      case FruitStyle.almond:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(0.4);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size, height: size * 1.6), paint);
        canvas.restore();
      case FruitStyle.cone:
        canvas.drawOval(Rect.fromCenter(center: c, width: size * 1.1, height: size * 1.8), paint);
        final line = Paint()
          ..color = palette.fruitAlt
          ..strokeWidth = math.max(0.5, size * 0.12);
        canvas.drawLine(Offset(c.dx - size * 0.45, c.dy - size * 0.25), Offset(c.dx + size * 0.45, c.dy - size * 0.25), line);
        canvas.drawLine(Offset(c.dx - size * 0.5, c.dy + size * 0.2), Offset(c.dx + size * 0.5, c.dy + size * 0.2), line);
      case FruitStyle.acorn:
        canvas.drawOval(Rect.fromCenter(center: c.translate(0, size * 0.15), width: size * 1.4, height: size * 1.7), paint);
        canvas.drawOval(
          Rect.fromCenter(center: c.translate(0, -size * 0.45), width: size * 1.6, height: size * 0.84),
          paint..color = palette.fruitAlt,
        );
    }
    // One highlight dot: enough to read as round rather than as a sticker.
    canvas.drawCircle(
      c.translate(-size * 0.3, -size * 0.35),
      size * 0.25,
      Paint()..color = palette.light.withValues(alpha: 0.45),
    );
  }

  void _paintOrnaments(Canvas canvas, TreeFrame frame) {
    final originX = frame.originX;
    final originY = frame.originY;
    final scale = frame.scale;
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
      _drawFruit(canvas, sp.fruitStyle, centre, size);
    }

    // Snow on the branches (level 25+, winter). Drawn inside the swaying
    // transform so the load rides with the tree.
    if (level >= kSeasonsTraitLevel && palette.season == Season.winter) {
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

    final perch = scene.perch;
    if (perch != null && (animal == TreeAnimal.vogel || animal == TreeAnimal.duif)) {
      final p = Offset(originX + perch.x * scale, originY + perch.y * scale);
      if (animal == TreeAnimal.vogel) {
        _drawBird(canvas, p, scale);
      } else {
        _drawDove(canvas, p, scale);
      }
    }
  }

  // ------------------------------------------------------------- animals

  void _drawBird(Canvas canvas, Offset p, double scale) {
    final s = math.max(2.0, 2.6 * scale);
    canvas.drawPath(
      Path()
        ..moveTo(p.dx - s, p.dy)
        ..quadraticBezierTo(p.dx - s * 0.4, p.dy - s * 0.7, p.dx, p.dy)
        ..quadraticBezierTo(p.dx + s * 0.4, p.dy - s * 0.7, p.dx + s, p.dy),
      Paint()
        ..color = palette.bark
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, 0.45 * scale),
    );
  }

  void _drawDove(Canvas canvas, Offset p, double scale) {
    final s = math.max(2.5, 2.4 * scale);
    final flap = still ? 0.0 : math.sin(timeMs * 0.004) * 0.25;
    final x = p.dx;
    final y = p.dy;
    final body = Paint()..color = const Color(0xFFF4F4F0);
    canvas.save();
    canvas.translate(x, y - s * 0.4);
    canvas.rotate(-0.15);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 1.1), body);
    canvas.restore();
    canvas.drawPath(
      Path()
        ..moveTo(x - s * 0.8, y - s * 0.3)
        ..lineTo(x - s * 1.5, y - s * 0.05)
        ..lineTo(x - s * 1.35, y - s * 0.55)
        ..close(),
      body,
    );
    canvas.drawCircle(Offset(x + s * 0.85, y - s * 0.8), s * 0.38, body);
    canvas.drawPath(
      Path()
        ..moveTo(x - s * 0.1, y - s * 0.55)
        ..quadraticBezierTo(x - s * 0.2, y - s * (1.35 + flap), x + s * 0.7, y - s * (1.05 + flap))
        ..lineTo(x + s * 0.4, y - s * 0.45)
        ..close(),
      Paint()..color = const Color(0xFFE2E2D8),
    );
    canvas.drawPath(
      Path()
        ..moveTo(x + s * 1.2, y - s * 0.82)
        ..lineTo(x + s * 1.5, y - s * 0.72)
        ..lineTo(x + s * 1.18, y - s * 0.66)
        ..close(),
      Paint()..color = const Color(0xFFE0A458),
    );
    canvas.drawCircle(
      Offset(x + s * 0.95, y - s * 0.86),
      math.max(0.5, s * 0.08),
      Paint()..color = const Color(0xFF2B2B2B),
    );
  }


  @override
  bool shouldRepaint(TreePainter old) =>
      old.timeMs != timeMs ||
      old.scene != scene ||
      old.reveal != reveal ||
      old.palette != palette ||
      old.celebration != celebration ||
      old.bloomFruit != bloomFruit ||
      old.framing != framing ||
      old.animal != animal;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

Offset _normal(double dx, double dy) {
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return const Offset(0, 0);
  return Offset(-dy / length, dx / length);
}
