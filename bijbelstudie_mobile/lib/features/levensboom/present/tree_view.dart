import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../domain/palette.dart';
import '../domain/rng.dart';
import '../domain/scene_cache.dart';
import '../domain/scenes.dart';
import '../domain/species.dart';
import '../domain/tree_generator.dart';

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
enum TreeFraming { scene, portrait }

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

/// Motes, stars, drifters and the backdrop's own details, drawn from their own
/// streams so adding one can never shift the tree's own random draws.
class TreeDecor {
  TreeDecor(String seed) {
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
    fireflies = [
      for (var i = 0; i < 12; i++) (x: rand(), y: rand(), phase: rand()),
    ];
    butterflies = [
      for (var i = 0; i < 3; i++)
        (
          rx: 0.55 + rand() * 0.35,
          ry: 0.35 + rand() * 0.3,
          speed: 0.7 + rand() * 0.6,
          phase: rand(),
          hue: i,
        ),
    ];

    final scene = seededRng('$seed:scene');
    dots = [
      for (var i = 0; i < 120; i++)
        (x: scene(), y: scene(), r: scene(), k: scene()),
    ];
    sheep = (-(13 + scene() * 8), 11 + scene() * 7);
    deer = 15 + scene() * 6;
  }

  late final List<({double x, double y, double r, double speed, double phase})> motes;
  late final List<({double x, double y, double r, double phase})> stars;
  late final List<
    ({double x, double y, double size, double speed, double drift, double phase})
  >
  drifters;
  late final List<({double x, double y, double phase})> fireflies;
  late final List<({double rx, double ry, double speed, double phase, int hue})>
  butterflies;

  /// Backdrop details: stone/flower/olive positions, extra stars. 0..1.
  late final List<({double x, double y, double r, double k})> dots;

  /// Where the ground animals stand, in tree units left/right of the trunk.
  late final (double, double) sheep;
  late final double deer;
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

/// The frame a scene is drawn in: where tree space lands in pixels.
class TreeFrame {
  const TreeFrame({
    required this.width,
    required this.height,
    required this.scale,
    required this.originX,
    required this.originY,
    required this.pivotX,
    required this.pivotY,
    required this.groundTop,
  });

  final double width, height, scale, originX, originY, pivotX, pivotY;

  /// Top edge of the earth band (scene) or of the shadow (portrait).
  final double groundTop;
}

const double _deg = math.pi / 180;

/// Ground animals stand beside the trunk; the frame has to hold them too.
({double minX, double maxX}) _extentWithAnimals(
  TreeScene scene,
  TreeAnimal animal,
  TreeDecor decor,
) {
  var minX = scene.bounds.minX;
  var maxX = scene.bounds.maxX;
  if (animal == TreeAnimal.schaap) {
    minX = math.min(minX, kTrunkX + decor.sheep.$1 - 5);
    maxX = math.max(maxX, kTrunkX + decor.sheep.$2 + 5);
  }
  if (animal == TreeAnimal.hert) maxX = math.max(maxX, kTrunkX + decor.deer + 6);
  return (minX: minX, maxX: maxX);
}

TreeFrame measureTreeFrame(
  Size size,
  TreeScene scene,
  TreeFraming framing,
  TreeAnimal animal,
  TreeDecor decor,
) {
  final extent = _extentWithAnimals(scene, animal, decor);
  final minX = extent.minX;
  final maxX = extent.maxX;
  final minY = scene.bounds.minY;
  final contentW = math.max(1.0, maxX - minX);
  final treeH = math.max(1.0, kGroundY - minY);
  final width = size.width;
  final height = size.height;

  if (framing == TreeFraming.portrait) {
    // The tree alone, centred, standing on a soft shadow near the bottom.
    final padX = width * 0.1;
    final padY = height * 0.1;
    final scale = math.min((width - 2 * padX) / contentW, (height - 2 * padY) / treeH);
    final originX = width / 2 - ((minX + maxX) / 2) * scale;
    final pivotY = height - padY * 1.15;
    final originY = pivotY - kGroundY * scale;
    return TreeFrame(
      width: width,
      height: height,
      scale: scale,
      originX: originX,
      originY: originY,
      pivotX: originX + kTrunkX * scale,
      pivotY: pivotY,
      groundTop: pivotY,
    );
  }

  // The scene: a fixed earth band (never scaled from the tree, which for a
  // kiem swallowed the whole frame), a minimum framed extent so a small tree
  // stands small in a real landscape, and the trunk base just below the band's
  // top edge so the tree stands in the ground rather than on a line above it.
  final band = height * 0.12;
  final sceneW = math.max(contentW, kMinSceneWidth);
  final sceneH = math.max(treeH, kMinSceneHeight);
  final scale = math.min((width * 0.9) / sceneW, ((height - band) * 0.84) / sceneH);
  final groundTop = height - band;
  final pivotY = groundTop + 0.6 * scale;
  final originX = width / 2 - ((minX + maxX) / 2) * scale;
  final originY = pivotY - kGroundY * scale;
  return TreeFrame(
    width: width,
    height: height,
    scale: scale,
    originX: originX,
    originY: originY,
    pivotX: originX + kTrunkX * scale,
    pivotY: pivotY,
    groundTop: groundTop,
  );
}

class TreePainter extends CustomPainter {
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

  final TreeScene scene;
  final TreePalette palette;
  final TreeDecor decor;
  final BranchLayer layer;
  final double reveal;
  final double timeMs;
  final bool still;
  final int level;
  final bool celebration;
  final int? bloomFruit;
  final TreeFraming framing;
  final TreeAnimal animal;

  /// The `seasons` trait (docs/levensboom-spec.md §6) arrives here.
  static const int _seasonsTraitLevel = 25;

  SpeciesParams get _sp => speciesParams(scene.species);

  /// How much of a branch at [depth] is grown, for the celebration sequence.
  double _revealAt(int depth) {
    if (reveal >= 1) return 1;
    final t = reveal * (scene.maxDepth + 1) - depth;
    return t.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = measureTreeFrame(size, scene, framing, animal, decor);
    _paintSky(canvas, frame);
    _paintGround(canvas, frame);

    final sway = still
        ? 0.0
        : math.sin(timeMs * 0.00042) * 0.85 + math.sin(timeMs * 0.00097) * 0.255;

    canvas.save();
    canvas.translate(frame.pivotX, frame.pivotY);
    canvas.rotate(sway * _deg);
    canvas.translate(-frame.pivotX, -frame.pivotY);

    _paintBranches(canvas, frame);
    _paintLeaves(canvas, frame);
    _paintOrnaments(canvas, frame);

    canvas.restore();

    _paintForeground(canvas, frame);
  }

  // ---------------------------------------------------------------- sky

  void _paintSky(Canvas canvas, TreeFrame frame) {
    final rect = Offset.zero & Size(frame.width, frame.height);
    if (framing == TreeFraming.portrait) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(frame.width / 2, frame.height * 0.38),
            math.max(frame.width, frame.height) * 0.75,
            [palette.skyBottom, palette.skyTop],
          ),
      );
      return;
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, frame.groundTop),
          [palette.skyTop, palette.skyBottom],
        ),
    );

    if (palette.night) {
      final star = Paint();
      for (final s in decor.stars) {
        final twinkle =
            0.45 + 0.55 * math.sin(timeMs * 0.0008 + s.phase * 6.283).abs();
        // Sky decoration is placed in viewport fractions, not tree space: the
        // tree is framed to its own bounds, so following it would bunch the
        // stars around the canopy instead of filling the sky.
        canvas.drawCircle(
          Offset(s.x / 100 * frame.width, s.y / 100 * frame.groundTop),
          math.max(0.5, s.r * frame.scale),
          star..color = palette.light.withValues(alpha: twinkle * 0.8),
        );
      }
    }
  }

  // ------------------------------------------------------------- ground

  void _paintGround(Canvas canvas, TreeFrame frame) {
    final scale = frame.scale;
    final pivot = Offset(frame.pivotX, frame.pivotY);

    if (framing == TreeFraming.portrait) {
      // A soft shadow and a thin arc of ground: enough to stand on, not a
      // landscape.
      final extent = _extentWithAnimals(scene, animal, decor);
      final rx = math.max(6.0, ((extent.maxX - extent.minX) / 2) * scale * 0.55);
      canvas.drawOval(
        Rect.fromCenter(center: pivot, width: rx * 2, height: math.max(3.0, 3.2 * scale)),
        Paint()..color = palette.ground.withValues(alpha: 0.9),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: pivot.translate(0, 0.4 * scale),
          width: rx * 1.4,
          height: math.max(2.0, 2.2 * scale),
        ),
        Paint()..color = palette.bark.withValues(alpha: 0.25),
      );
      return;
    }

    // The glow, centred on the canopy wherever it happens to be for this level.
    final glowCentre = Offset(
      frame.pivotX,
      frame.originY + (scene.bounds.minY + kGroundY) / 2 * scale,
    );
    final glowRadius = math.max(30.0, (kGroundY - scene.bounds.minY) * 0.7) * scale;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, frame.width, frame.groundTop),
      Paint()
        ..shader = ui.Gradient.radial(glowCentre, glowRadius, [
          palette.glow.withValues(alpha: 0.4),
          palette.glow.withValues(alpha: 0),
        ]),
    );

    _paintFarBackdrop(canvas, frame);

    // The earth band, with a low mound where the trunk goes in.
    final top = frame.groundTop;
    canvas.drawRect(
      Rect.fromLTRB(0, top, frame.width, frame.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, frame.height), [
          palette.ground,
          palette.groundDeep,
        ]),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(frame.pivotX, top + 0.2 * scale),
        width: math.max(16.0, 28 * scale),
        height: math.max(4.0, 4.4 * scale),
      ),
      Paint()..color = palette.ground,
    );

    _paintNearBackdrop(canvas, frame);

    canvas.drawOval(
      Rect.fromCenter(
        center: pivot.translate(0, 0.6 * scale),
        width: math.max(12.0, 22 * scale),
        height: math.max(2.4, 3.2 * scale),
      ),
      Paint()
        ..color = Color.lerp(palette.groundDeep, palette.bark, 0.5)!.withValues(alpha: 0.28),
    );
  }

  Path _hillPath(double width, double baseY, double amp, double freq, double phase, double lift) {
    final path = Path()..moveTo(0, baseY + amp * 2);
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps * width;
      final y = baseY - lift - amp * (0.5 + 0.5 * math.sin(i / steps * freq * math.pi * 2 + phase));
      path.lineTo(x, y);
    }
    path
      ..lineTo(width, baseY + amp * 2)
      ..close();
    return path;
  }

  void _paintFarBackdrop(Canvas canvas, TreeFrame frame) {
    final w = frame.width;
    final h = frame.height;
    final groundTop = frame.groundTop;
    final spec = sceneSpec(palette.scene);
    final paint = Paint();

    switch (spec.backdrop) {
      case Backdrop.hills:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.09, 1.3, 0.8, h * 0.05), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.06, 2.1, 2.6, 0), paint..color = palette.far);
        // Olive groves: dark specks along the near hill.
        paint.color = spec.accent.withValues(alpha: 0.7);
        for (var i = 0; i < 9; i++) {
          final d = decor.dots[i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(d.x * w, groundTop - h * 0.02 - d.y * h * 0.05),
              width: math.max(2.4, w * 0.024),
              height: math.max(2.0, w * 0.016),
            ),
            paint,
          );
        }
      case Backdrop.lake:
        final horizon = groundTop - h * 0.14;
        canvas.drawPath(_hillPath(w, horizon, h * 0.045, 1.6, 1.2, 0), paint..color = palette.far);
        canvas.drawRect(
          Rect.fromLTRB(0, horizon, w, groundTop),
          paint..color = palette.water ?? palette.far,
        );
        final streak = Paint()
          ..color = spec.accent.withValues(alpha: 0.5)
          ..strokeWidth = math.max(1.0, h * 0.004)
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 5; i++) {
          final d = decor.dots[i + 10];
          final y = horizon + (0.2 + d.y * 0.7) * (groundTop - horizon);
          final x = d.x * w;
          final half = w * 0.05 * (0.5 + d.r);
          canvas.drawLine(Offset(x - half, y), Offset(x + half, y), streak);
        }
        // The boat.
        final bx = w * 0.74;
        final by = horizon + (groundTop - horizon) * 0.3;
        final bw = math.max(8.0, w * 0.06);
        canvas.drawPath(
          Path()
            ..moveTo(bx - bw / 2, by)
            ..lineTo(bx + bw / 2, by)
            ..lineTo(bx + bw * 0.35, by + bw * 0.22)
            ..lineTo(bx - bw * 0.35, by + bw * 0.22)
            ..close(),
          paint..color = palette.bark,
        );
        canvas.drawLine(
          Offset(bx, by),
          Offset(bx, by - bw * 0.7),
          Paint()
            ..color = palette.bark
            ..strokeWidth = math.max(1.0, bw * 0.05),
        );
        canvas.drawPath(
          Path()
            ..moveTo(bx + bw * 0.03, by - bw * 0.68)
            ..lineTo(bx + bw * 0.42, by - bw * 0.08)
            ..lineTo(bx + bw * 0.03, by - bw * 0.08)
            ..close(),
          paint..color = spec.accent,
        );
      case Backdrop.dunes:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.1, 0.9, 2.2, h * 0.03), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.07, 1.4, 4.4, 0), paint..color = palette.far);
      case Backdrop.mountain:
        const peaks = [
          (-0.05, 0.12),
          (0.08, 0.3),
          (0.24, 0.42),
          (0.4, 0.26),
          (0.58, 0.48),
          (0.74, 0.3),
          (0.9, 0.38),
          (1.05, 0.14),
        ];
        final range = Path()..moveTo(-w * 0.1, groundTop);
        for (final (px, py) in peaks) {
          range.lineTo(px * w, groundTop - py * h);
        }
        range
          ..lineTo(w * 1.1, groundTop)
          ..close();
        canvas.drawPath(range, paint..color = palette.far);
        // Snow on the two tallest peaks.
        paint.color = spec.accent;
        for (final (px, py) in [peaks[2], peaks[4]]) {
          final top = groundTop - py * h;
          final cap = h * 0.06;
          canvas.drawPath(
            Path()
              ..moveTo(px * w, top)
              ..lineTo(px * w + cap * 0.9, top + cap)
              ..lineTo(px * w + cap * 0.3, top + cap * 0.8)
              ..lineTo(px * w - cap * 0.2, top + cap * 1.05)
              ..lineTo(px * w - cap * 0.9, top + cap)
              ..close(),
            paint,
          );
        }
        canvas.drawPath(_hillPath(w, groundTop, h * 0.07, 1.1, 3.4, 0), paint..color = palette.farAlt);
      case Backdrop.wall:
        final wallTop = groundTop - h * 0.17;
        paint.color = palette.far;
        canvas.drawRect(Rect.fromLTRB(0, wallTop, w, groundTop), paint);
        final step = w * 0.07;
        final mw = step * 0.5;
        final mh = h * 0.035;
        for (var x = step * 0.25; x < w; x += step) {
          canvas.drawRect(Rect.fromLTWH(x, wallTop - mh, mw, mh + 1), paint);
        }
        final tx = w * 0.78;
        final tw = w * 0.12;
        final towerTop = groundTop - h * 0.3;
        canvas.drawRect(Rect.fromLTRB(tx, towerTop, tx + tw, groundTop), paint);
        for (var x = tx; x < tx + tw; x += tw / 4) {
          canvas.drawRect(Rect.fromLTWH(x, towerTop - mh, tw / 8, mh + 1), paint);
        }
        final course = Paint()
          ..color = palette.farAlt.withValues(alpha: 0.55)
          ..strokeWidth = 1;
        for (var i = 1; i < 4; i++) {
          final y = wallTop + (groundTop - wallTop) * i / 4;
          canvas.drawLine(Offset(0, y), Offset(w, y), course);
        }
        final gx = w * 0.28;
        final gw = w * 0.06;
        canvas.drawPath(
          Path()
            ..moveTo(gx - gw / 2, groundTop)
            ..lineTo(gx - gw / 2, groundTop - h * 0.07)
            ..arcTo(
              Rect.fromCircle(center: Offset(gx, groundTop - h * 0.07), radius: gw / 2),
              math.pi,
              math.pi,
              false,
            )
            ..lineTo(gx + gw / 2, groundTop)
            ..close(),
          paint..color = spec.accent,
        );
      case Backdrop.garden:
        canvas.drawPath(_hillPath(w, groundTop, h * 0.08, 1.7, 0.4, h * 0.03), paint..color = palette.farAlt);
        canvas.drawPath(_hillPath(w, groundTop, h * 0.05, 3.2, 1.9, 0), paint..color = palette.far);
      case Backdrop.stars:
        for (var i = 0; i < 90; i++) {
          final d = decor.dots[i];
          canvas.drawCircle(
            Offset(d.x * w, d.y * groundTop * 0.95),
            math.max(0.4, d.r * w * 0.0035),
            paint..color = palette.light.withValues(alpha: 0.35 + 0.6 * d.k),
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w, groundTop),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(w, groundTop),
              [
                palette.light.withValues(alpha: 0),
                palette.light.withValues(alpha: 0.13),
                palette.light.withValues(alpha: 0),
              ],
              [0.3, 0.5, 0.7],
            ),
        );
        final mx = w * 0.18;
        final my = h * 0.16;
        final mr = math.max(4.0, w * 0.035);
        canvas.drawCircle(Offset(mx, my), mr, paint..color = spec.accent);
        canvas.drawCircle(
          Offset(mx + mr * 0.45, my - mr * 0.15),
          mr * 0.85,
          paint..color = palette.skyTop,
        );
      case Backdrop.meadow:
        canvas.drawPath(
          _hillPath(w, groundTop, h * 0.04, 1.2, 1.1, 0),
          paint..color = palette.far.withValues(alpha: 0.55),
        );
    }
  }

  /// Details that sit on the earth band: the stream, the pool, flowers, stones.
  void _paintNearBackdrop(Canvas canvas, TreeFrame frame) {
    final w = frame.width;
    final h = frame.height;
    final groundTop = frame.groundTop;
    final band = h - groundTop;
    final spec = sceneSpec(palette.scene);
    final paint = Paint();

    switch (spec.backdrop) {
      case Backdrop.meadow:
        final water = palette.water;
        if (water == null) return;
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.66, groundTop)
            ..quadraticBezierTo(w * 0.72, groundTop + band * 0.45, w * 0.98, groundTop + band * 0.75)
            ..lineTo(w * 1.02, h)
            ..lineTo(w * 0.84, h)
            ..quadraticBezierTo(w * 0.7, groundTop + band * 0.55, w * 0.7, groundTop)
            ..close(),
          paint..color = water,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.7, groundTop + band * 0.2)
            ..quadraticBezierTo(w * 0.76, groundTop + band * 0.5, w * 0.9, groundTop + band * 0.7),
          Paint()
            ..color = spec.accent.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, band * 0.04),
        );
        paint.color = palette.farAlt;
        for (var i = 0; i < 4; i++) {
          final d = decor.dots[20 + i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(w * (0.05 + d.x * 0.5), groundTop + band * (0.3 + d.y * 0.5)),
              width: math.max(3.0, w * 0.024 * (0.5 + d.r)),
              height: math.max(2.0, w * 0.014 * (0.5 + d.r)),
            ),
            paint,
          );
        }
      case Backdrop.dunes:
        final water = palette.water;
        if (water == null) return;
        final px = w * 0.2;
        final py = groundTop + band * 0.45;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(px, py), width: w * 0.26, height: band * 0.56),
          paint..color = water,
        );
        paint.color = spec.accent.withValues(alpha: 0.8);
        for (final ox in [-1.15, 1.1]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(px + ox * w * 0.13, py - band * 0.05),
              width: math.max(4.0, w * 0.04),
              height: math.max(3.0, band * 0.32),
            ),
            paint,
          );
        }
      case Backdrop.garden:
        final water = palette.water;
        if (water != null) {
          canvas.drawPath(
            Path()
              ..moveTo(-w * 0.02, groundTop + band * 0.35)
              ..quadraticBezierTo(w * 0.18, groundTop + band * 0.2, w * 0.3, groundTop + band * 0.8)
              ..lineTo(w * 0.22, h)
              ..lineTo(-w * 0.02, h)
              ..close(),
            paint..color = water,
          );
        }
        final colours = [spec.accent, const Color(0xFFF5D76E), const Color(0xFFFFFFFF), const Color(0xFFF28C6B)];
        for (var i = 0; i < 16; i++) {
          final d = decor.dots[30 + i];
          final x = w * (0.32 + d.x * 0.66);
          final y = groundTop + band * (0.15 + d.y * 0.7);
          final r = math.max(1.2, w * 0.006 * (0.7 + d.r));
          canvas.drawLine(
            Offset(x, y + r * 2.4),
            Offset(x, y),
            Paint()
              ..color = palette.groundDeep
              ..strokeWidth = math.max(0.8, r * 0.4),
          );
          canvas.drawCircle(
            Offset(x, y),
            r,
            paint..color = colours[(d.k * colours.length).floor() % colours.length],
          );
        }
      case Backdrop.mountain:
      case Backdrop.wall:
      case Backdrop.hills:
      case Backdrop.lake:
        paint.color = palette.farAlt.withValues(alpha: 0.6);
        for (var i = 0; i < 3; i++) {
          final d = decor.dots[40 + i];
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(w * (0.05 + d.x * 0.9), groundTop + band * (0.35 + d.y * 0.45)),
              width: math.max(3.0, w * 0.028 * (0.5 + d.r)),
              height: math.max(2.0, w * 0.016 * (0.5 + d.r)),
            ),
            paint,
          );
        }
      case Backdrop.stars:
        break;
    }
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
            ..lineTo(math.cos(a * _deg) * length, math.sin(a * _deg) * length);
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
    final shape = _sp.leafShape;
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
      final down = Offset(math.cos((90 - angle) * _deg), math.sin((90 - angle) * _deg));

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle * _deg);
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
      _drawFruit(canvas, _sp.fruitStyle, centre, size);
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

  void _drawSheep(Canvas canvas, Offset p, double scale, double facing) {
    final s = math.max(3.0, 1.8 * scale);
    final x = p.dx;
    final y = p.dy;
    final graze = still ? 0.0 : math.max(0.0, math.sin(timeMs * 0.0012 + x)) * 0.25;
    final legs = Paint()
      ..color = const Color(0xFF3B3330)
      ..strokeWidth = math.max(1.0, s * 0.18)
      ..strokeCap = StrokeCap.round;
    for (final lx in const [-0.9, -0.35, 0.35, 0.9]) {
      canvas.drawLine(Offset(x + lx * s, y - s * 0.5), Offset(x + lx * s, y), legs);
    }
    final fleece = Paint()..color = const Color(0xFFF2EFE6);
    for (final (ox, oy, r) in const [(-0.7, -0.95, 0.75), (0.1, -1.05, 0.85), (0.8, -0.9, 0.7)]) {
      canvas.drawCircle(Offset(x + ox * s, y + oy * s), r * s, fleece);
    }
    canvas.drawOval(Rect.fromCenter(center: Offset(x, y - s * 0.8), width: s * 3, height: s * 1.5), fleece);
    final hx = x + facing * s * 1.55;
    final hy = y - s * (0.85 - graze);
    final head = Paint()..color = const Color(0xFF3B3330);
    canvas.drawOval(Rect.fromCenter(center: Offset(hx, hy), width: s * 0.84, height: s * 1.1), head);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx - facing * s * 0.3, hy - s * 0.35), width: s * 0.56, height: s * 0.28),
      head,
    );
  }

  void _drawDeer(Canvas canvas, Offset p, double scale) {
    final s = math.max(3.0, 2 * scale);
    final x = p.dx;
    final y = p.dy;
    final nod = still ? 0.0 : math.sin(timeMs * 0.0009) * 0.08;
    const body = Color(0xFF8B6A4A);
    const dark = Color(0xFF5C4530);
    final legs = Paint()
      ..color = dark
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, s * 0.16);
    for (final lx in const [-1.1, -0.6, 0.6, 1.1]) {
      canvas.drawLine(Offset(x + lx * s, y - s * 1.1), Offset(x + lx * s * 1.05, y), legs);
    }
    final fill = Paint()..color = body;
    canvas.drawOval(Rect.fromCenter(center: Offset(x, y - s * 1.5), width: s * 3.4, height: s * 1.7), fill);
    final nx = x - s * 1.5;
    final ny = y - s * 2.1;
    canvas.drawLine(
      Offset(x - s * 1.2, y - s * 1.6),
      Offset(nx, ny - s * (0.9 - nod)),
      Paint()
        ..color = body
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, s * 0.5),
    );
    final hx = nx - s * 0.2;
    final hy = ny - s * (1.15 - nod);
    canvas.save();
    canvas.translate(hx, hy);
    canvas.rotate(-0.3);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 1.24, height: s * 0.76), fill);
    canvas.restore();
    final antler = Paint()
      ..color = dark
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, s * 0.14);
    canvas.drawLine(Offset(hx + s * 0.2, hy - s * 0.3), Offset(hx + s * 0.45, hy - s * 0.75), antler);
    canvas.drawLine(Offset(hx + s * 0.35, hy - s * 0.25), Offset(hx + s * 0.55, hy - s * 1.15), antler);
    canvas.drawLine(Offset(hx + s * 0.45, hy - s * 0.7), Offset(hx + s * 0.75, hy - s * 1.0), antler);
    canvas.drawLine(Offset(hx + s * 0.5, hy - s * 0.95), Offset(hx + s * 0.3, hy - s * 1.35), antler);
    canvas.drawCircle(Offset(hx - s * 0.25, hy - s * 0.08), math.max(0.5, s * 0.07), Paint()..color = const Color(0xFF2B2B2B));
    canvas.drawCircle(Offset(x + s * 1.65, y - s * 1.6), s * 0.22, Paint()..color = const Color(0xFFF2EFE6));
  }

  void _drawButterflies(Canvas canvas, TreeFrame frame) {
    final b = scene.bounds;
    final scale = frame.scale;
    final cx = frame.originX + ((b.minX + b.maxX) / 2) * scale;
    final cy = frame.originY + ((b.minY + kGroundY) / 2) * scale;
    final rx = ((b.maxX - b.minX) / 2) * scale;
    final ry = ((kGroundY - b.minY) / 2) * scale;
    const colours = [Color(0xFFF6C453), Color(0xFFF28CB1), Color(0xFF7EC8E3)];
    final size = math.max(2.0, 1.1 * scale);
    final wing = Paint();
    final bodyPaint = Paint()
      ..color = const Color(0xFF3B3330)
      ..strokeWidth = math.max(0.6, size * 0.16)
      ..strokeCap = StrokeCap.round;
    for (final fly in decor.butterflies) {
      final p = fly.phase * math.pi * 2;
      final tt = still ? 0.0 : timeMs * 0.0004 * fly.speed;
      final x = cx + math.cos(tt + p) * rx * fly.rx;
      final y = cy + math.sin(tt * 1.6 + p) * ry * fly.ry;
      final flap = still ? 0.85 : 0.35 + 0.65 * math.sin(timeMs * 0.018 + p).abs();
      wing.color = colours[fly.hue % colours.length];
      for (final side in const [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(x + side * size * 0.55 * flap, y);
        canvas.rotate(side * 0.4);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size * 1.2 * flap, height: size * 0.9), wing);
        canvas.restore();
      }
      canvas.drawLine(Offset(x, y - size * 0.45), Offset(x, y + size * 0.45), bodyPaint);
    }
  }

  // ---------------------------------------------------------- foreground

  void _paintForeground(Canvas canvas, TreeFrame frame) {
    final scale = frame.scale;
    final groundY = framing == TreeFraming.portrait ? frame.pivotY : frame.pivotY + 0.4 * scale;

    if (animal == TreeAnimal.schaap) {
      _drawSheep(canvas, Offset(frame.pivotX + decor.sheep.$1 * scale, groundY), scale, 1);
      _drawSheep(canvas, Offset(frame.pivotX + decor.sheep.$2 * scale, groundY), scale, -1);
    }
    if (animal == TreeAnimal.hert) {
      _drawDeer(canvas, Offset(frame.pivotX + decor.deer * scale, groundY), scale);
    }
    if (animal == TreeAnimal.vlinders) _drawButterflies(canvas, frame);

    if (animal == TreeAnimal.vuurvliegjes && palette.night) {
      final b = scene.bounds;
      final paint = Paint();
      for (final fly in decor.fireflies) {
        final pulse = 0.25 + 0.75 * math.sin(timeMs * 0.0013 + fly.phase * 6.283).abs();
        final drift = still ? 0.0 : math.sin(timeMs * 0.0005 + fly.phase * 6.283) * 1.6;
        canvas.drawCircle(
          Offset(
            frame.originX + (b.minX + fly.x * (b.maxX - b.minX) + drift) * scale,
            frame.originY + (b.minY + fly.y * (kGroundY - b.minY)) * scale,
          ),
          math.max(0.8, 0.6 * scale),
          paint..color = const Color(0xFFFFE9A8).withValues(alpha: pulse),
        );
      }
    }

    if (framing == TreeFraming.portrait) return;

    // Drifting petals and falling leaves. Autumn drops the occasional leaf for
    // everyone but the evergreens; the blossom storm is the level-25 `seasons`
    // trait and only blows in spring. Both are the same drifters, so a season
    // change costs a colour and nothing else.
    final hasSeasons = level >= _seasonsTraitLevel;
    final blossom = palette.blossom;
    final drifterColor = palette.season == Season.autumn && !_sp.evergreen
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
        final swayX = still ? 0.0 : math.sin(timeMs * 0.0012 + d.phase * 6.283) * d.drift * 3;
        canvas.save();
        canvas.translate((d.x + swayX) / 100 * frame.width, y / 100 * frame.height);
        canvas.rotate(still ? 0 : timeMs * 0.0016 + d.phase * 6.283);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: d.size * 2 * scale, height: d.size * scale),
          drifterPaint,
        );
        canvas.restore();
      }
    }

    // The level-up column of light.
    if (celebration && !still) {
      final column = Paint();
      for (var i = 0; i < 22; i++) {
        final phase = (i / 22 + timeMs * 0.00022) % 1;
        final y = frame.pivotY - phase * (frame.pivotY - frame.originY);
        final spread = (1 - phase) * 9 * scale;
        canvas.drawCircle(
          Offset(frame.pivotX + math.sin(timeMs * 0.0015 + i) * spread, y),
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
      final wobble = still ? 0.0 : math.sin(timeMs * 0.0009 + mote.phase * 6.283) * 1.2;
      final alpha = 0.16 + 0.14 * math.sin(timeMs * 0.001 + mote.phase * 6.283);
      canvas.drawCircle(
        Offset((mote.x + wobble) / 100 * frame.width, y / 100 * frame.height),
        math.max(0.6, mote.r * scale),
        paint..color = palette.light.withValues(alpha: alpha.clamp(0.0, 1.0)),
      );
    }
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
