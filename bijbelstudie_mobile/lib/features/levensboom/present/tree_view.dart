import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../domain/growth.dart';
import '../domain/paint_spec.dart';
import '../domain/palette.dart';
import '../domain/scene_cache.dart';
import '../domain/scenes.dart';
import '../domain/species.dart';
import '../domain/tree_generator.dart';
import '../domain/tween.dart';
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
/// avatar: the tree alone on a sky disc, for the tab bar and every other place
/// a 24 px face has to read. Both come from `domain/camera.dart` (growth v2):
/// the landscape stays put and the tree takes a designed share of it, so
/// growth shows as size.
///
/// Growth v2 tween: with [TreeView.from], the view plays the tree growing from
/// that position to the current one - [lerpScenes] each frame, with the camera
/// measured on the in-between scene so it eases along. The branch layer is
/// re-recorded every frame while that runs, and only then.
///
/// Honours `MediaQuery.disableAnimations`, the account's own "minder beweging"
/// pref and [TreeView.still]: one static frame, no particles, no sway, and a
/// tween shows its end state at once. Species, scene and animal never touch
/// the generator - they are paint.

/// Where a growth tween starts: the website's TreeCanvas `from`.
class TreeFrom {
  /// On the view's own [TreeView.floor] (the website's `floor` left out).
  const TreeFrom({required this.level, required this.frac})
      : floor = null,
        ownFloor = false;

  /// On an explicit floor; null means none.
  const TreeFrom.withFloor({required this.level, required this.frac, required this.floor})
      : ownFloor = true;

  final int level;
  final double frac;
  final GrowthFloor? floor;

  /// True when [floor] is used rather than the view's.
  final bool ownFloor;

  GrowthFloor? floorFor(GrowthFloor? current) => ownFloor ? floor : current;
}

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
    this.floor,
    this.at,
    this.from,
    this.tweenMs,
    this.onTweenEnd,
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

  /// 0..1. Below 1 the tree is mid grow-in, by depth.
  ///
  /// Deprecated in spirit, as on the website: growth v2 grows the tree with
  /// [from] instead. Kept working for anything that still sets it.
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

  /// Growth v2: the account's never-shrink floor (`levensboom.growth.floor`,
  /// or a public card's `growth.floor`).
  final GrowthFloor? floor;

  /// Growth v2: draw at this position instead of [level]/[frac] (the Groei
  /// ladder's thumbnails).
  final TreeAt? at;

  /// Growth v2: tween from this earlier position to the current one (plan
  /// §9.2, §9.3) - the level-up and the in-level lesson growth. Paths in both
  /// scenes lengthen in place, newborn wood grows out of its parent's tip, the
  /// camera eases. Under reduced motion the end state shows at once.
  ///
  /// Plays once per distinct start (by value). If only the target moves while
  /// it runs, it retargets without restarting; once it has ended, a new
  /// target just shows.
  final TreeFrom? from;

  /// Tween length; defaults to `tween.levelUpMs` (1800) when the step
  /// changes, else `tween.growMs` (1200).
  final int? tweenMs;

  /// Called once when the tween has finished - also when it was skipped
  /// (reduced motion, [still]) and when the view was off screen for its whole
  /// length.
  final VoidCallback? onTweenEnd;

  @override
  State<TreeView> createState() => _TreeViewState();
}

/// The running growth tween: scene A, how long, and whether it is over.
class _Tween {
  _Tween(this.key, this.from, this.ms);

  final String key;
  TreeScene from;
  int ms;
  bool ended = false;
}

class _TreeViewState extends State<TreeView> with TickerProviderStateMixin {
  /// One clock for everything, so the layers cannot drift apart. A minute per
  /// turn keeps the value coarse enough to avoid float noise in the sines.
  static const Duration _period = Duration(seconds: 60);

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _period,
  );

  /// Drives the growth tween, 0 → 1 linear over its length; [tweenEase] shapes it.
  late final AnimationController _tweenClock = AnimationController(vsync: this);

  late final Listenable _ticks = Listenable.merge([_clock, _tweenClock]);

  final BranchLayer _layer = BranchLayer();

  late TreeScene _scene;
  late TreeDecor _decor;

  _Tween? _tween;

  /// A new tween waits for [_syncClock] to start it, where the motion
  /// preferences can be read.
  bool _tweenPending = false;

  /// Ends a tween on time even when no frame is drawn (the route is covered,
  /// the ticker muted): the website's end timer.
  Timer? _endTimer;

  @override
  void initState() {
    super.initState();
    _scene = _build();
    _decor = TreeDecor(widget.seed);
    _syncTween();
  }

  @override
  void didUpdateWidget(TreeView old) {
    super.didUpdateWidget(old);
    if (old.seed != widget.seed ||
        old.level != widget.level ||
        old.frac != widget.frac ||
        old.health != widget.health ||
        old.species != widget.species ||
        old.framing != widget.framing ||
        old.floor != widget.floor ||
        old.at?.position != widget.at?.position ||
        old.at?.step != widget.at?.step) {
      _scene = _build();
    }
    if (old.seed != widget.seed) _decor = TreeDecor(widget.seed);
    _syncTween();
    _syncClock();
  }

  /// Portraits tell 20 positions per step apart, scenes 50 (scene_cache.dart):
  /// an XP tick never regenerates a tree nobody could see change.
  int get _bucket => widget.framing == TreeFraming.portrait ? 20 : kPositionBucket;

  TreeScene _build() => cachedTree(
    seed: widget.seed,
    level: widget.level,
    frac: widget.frac,
    health: widget.health,
    species: widget.species,
    floor: widget.floor,
    at: widget.at,
    bucket: _bucket,
  );

  /// Scene A of the tween, and one tween per distinct start: the same `from`
  /// again only retargets (an ended tween stays ended).
  void _syncTween() {
    final from = widget.from;
    if (from == null) {
      _tween = null;
      _tweenPending = false;
      _endTimer?.cancel();
      if (_tweenClock.isAnimating) _tweenClock.stop();
      return;
    }
    final floor = from.floorFor(widget.floor);
    final key = '${widget.seed}|${kSpeciesIds[widget.species]}|${from.level}|${from.frac}|'
        '${floor?.from ?? '-'},${floor?.to ?? '-'}';
    final fromScene = cachedTree(
      seed: widget.seed,
      level: from.level,
      frac: from.frac,
      health: widget.health,
      species: widget.species,
      floor: floor,
      bucket: _bucket,
    );
    final ms = math.max(0, widget.tweenMs ?? tweenMsFor(fromScene, _scene));
    final running = _tween;
    if (running != null && running.key == key) {
      running.from = fromScene;
      if (running.ms != ms && !running.ended && _tweenClock.isAnimating) {
        // Same start, new length: finish the rest at the new pace.
        _tweenClock
          ..duration = Duration(milliseconds: math.max(1, ms))
          ..forward(from: _tweenClock.value);
      }
      running.ms = ms;
      return;
    }
    _tween = _Tween(key, fromScene, ms);
    _tweenPending = true;
  }

  bool get _still =>
      widget.still ||
      widget.reducedMotion ||
      MediaQuery.maybeDisableAnimationsOf(context) == true;

  void _syncClock() {
    if (_still) {
      if (_clock.isAnimating) _clock.stop();
      if (_tweenClock.isAnimating) _tweenClock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
    final tween = _tween;
    if (_tweenPending && tween != null) {
      _tweenPending = false;
      _endTimer?.cancel();
      // Still: the first frame is the end state (see [_sceneNow]).
      if (!_still && tween.ms > 0) {
        _tweenClock
          ..duration = Duration(milliseconds: tween.ms)
          ..forward(from: 0);
        _endTimer = Timer(Duration(milliseconds: tween.ms + 50), () {
          if (!mounted || tween.ended || !identical(_tween, tween)) return;
          setState(() => _endTween(tween));
        });
      }
    }
  }

  /// The scene to draw now: B, or A→B while the tween runs. Ends the tween
  /// once its time is up.
  TreeScene _sceneNow() {
    final tween = _tween;
    if (tween == null || tween.ended) return _scene;
    final u = _still || tween.ms <= 0 ? 1.0 : _tweenClock.value;
    if (u >= 1) {
      _endTween(tween);
      return _scene;
    }
    return lerpScenes(tween.from, _scene, tweenEase(u));
  }

  void _endTween(_Tween tween) {
    if (tween.ended) return;
    tween.ended = true;
    _endTimer?.cancel();
    // After the paint, so the caller's next step never races the end state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTweenEnd?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncClock();
  }

  @override
  void dispose() {
    _endTimer?.cancel();
    _clock.dispose();
    _tweenClock.dispose();
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
        animation: _ticks,
        builder: (context, _) {
          final still = _still;
          return CustomPaint(
            painter: TreePainter(
              scene: _sceneNow(),
              seed: widget.seed,
              palette: palette,
              decor: _decor,
              layer: _layer,
              reveal: widget.reveal,
              timeMs: still ? 0 : _clock.value * _period.inMilliseconds,
              still: still,
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


/// The recorded branch layer plus what it was recorded for.
class BranchLayer {
  ui.Picture? picture;
  String? key;

  /// The scene it was recorded from, by identity: every frame of a tween is a
  /// new scene, so the layer is re-recorded then and almost never otherwise.
  TreeScene? scene;

  void dispose() {
    picture?.dispose();
    picture = null;
    scene = null;
  }
}

/// A blossom's radius as a share of its (capped) leaf size times the leaf
/// scale: smaller than a leaf. The website's `BLOSSOM_RADIUS`.
const double _blossomRadius = 0.7;

class TreePainter extends CustomPainter with SceneLayers {
  TreePainter({
    required this.scene,
    required this.seed,
    required this.palette,
    required this.decor,
    required this.layer,
    this.reveal = 1,
    required this.timeMs,
    required this.still,
    required this.level,
    this.celebration = false,
    this.bloomFruit,
    this.framing = TreeFraming.scene,
    this.animal = kDefaultAnimal,
  });

  /// What is drawn: during a tween, the in-between scene.
  @override
  final TreeScene scene;

  /// The account's seed, for the maturing details' own stream (`<seed>:mature`).
  final String seed;
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

  /// How much of a branch at [depth] is grown, for the (deprecated) reveal.
  double _revealAt(int depth) {
    if (reveal >= 1) return 1;
    final t = reveal * (scene.maxDepth + 1) - depth;
    return t.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The scene is designed larger than any box it lands in - the rainbow's
    // bow runs on a centre below the horizon and wider than a tile, animals
    // and a big crown can reach past the frame - and a CustomPaint does not
    // clip. Without this the bow painted into a studio tile's caption and
    // over its border. One rect clip, so every surface stays in its box.
    canvas.save();
    canvas.clipRect(Offset.zero & size);

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
    canvas.restore();
  }


  // --------------------------------------------------------------- tree

  void _paintBranches(Canvas canvas, TreeFrame frame) {
    final key =
        '${frame.width}x${frame.height}:${frame.scale}:${frame.originX}:${frame.originY}:'
        '${palette.leaf.toARGB32()}:${palette.leafAlt.toARGB32()}:${palette.bark.toARGB32()}:'
        '${palette.barkLit.toARGB32()}:${palette.groundDeep.toARGB32()}:${reveal.toStringAsFixed(3)}';

    if (layer.picture == null || layer.key != key || !identical(layer.scene, scene)) {
      final recorder = ui.PictureRecorder();
      final scratch = Canvas(recorder);
      recordBranches(scratch, frame);
      layer.picture?.dispose();
      layer.picture = recorder.endRecording();
      layer.key = key;
      layer.scene = scene;
    }
    canvas.drawPicture(layer.picture!);
  }

  /// The branch layer, drawn straight (no picture): root flare behind the
  /// trunk, the wood, then knots and moss on the bark (`paint_spec.dart` has
  /// their numbers). Each branch is lit from the upper left, from its `wood`
  /// colour's lit tone to its own: bark (barkLit → bark) for old wood, the
  /// green-stem mix for young wood. The website's `drawBranches`.
  void recordBranches(Canvas canvas, TreeFrame frame) {
    final originX = frame.originX;
    final originY = frame.originY;
    final scale = frame.scale;
    double px(double x) => originX + x * scale;
    double py(double y) => originY + y * scale;
    final mature = matureDetails(scene, seed);
    // Old details show once the trunk has grown in, never half-drawn.
    final trunkShown = _revealAt(0) >= 1;

    if (trunkShown) {
      for (final foot in mature.roots) {
        canvas.drawPath(
          Path()
            ..moveTo(px(foot.top.x), py(foot.top.y))
            ..quadraticBezierTo(px(foot.ctrl.x), py(foot.ctrl.y), px(foot.toe.x), py(foot.toe.y))
            ..lineTo(px(foot.toe.x), py(foot.bottomY))
            ..lineTo(px(foot.baseX), py(foot.bottomY))
            ..lineTo(px(foot.baseX), py(foot.top.y))
            ..close(),
          Paint()..color = rootColor(palette, foot.side),
        );
      }
    }

    // Wood colours per twentieth, as the website's canvas buckets them: a
    // tree is a handful of distinct mixes.
    final tones = <int, List<Color>>{};
    List<Color> toneOf(double wood) {
      final bucket = (math.min(1.0, math.max(0.0, wood)) * 20).round();
      return tones.putIfAbsent(
        bucket,
        () => [
          woodMix(palette.leafAlt, palette.barkLit, bucket / 20),
          woodMix(palette.leaf, palette.bark, bucket / 20),
        ],
      );
    }

    for (final branch in scene.branches) {
      final t = _revealAt(branch.depth);
      if (t <= 0) continue;
      // A newborn twig at the start of a tween has no length yet.
      if (branch.w0 <= 0 && branch.x1 == branch.x0 && branch.y1 == branch.y0) continue;

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
      final tone = toneOf(branch.wood);
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x0 - w0, y0),
            Offset(x0 + w0, y0),
            tone,
          ),
      );
    }

    if (!trunkShown) return;
    if (mature.knots.isNotEmpty) {
      final colours = knotColors(palette);
      final rim = Paint()..color = colours.rim.withValues(alpha: 0.55);
      final knot = Paint()..color = colours.knot.withValues(alpha: 0.9);
      for (final k in mature.knots) {
        final centre = Offset(px(k.x), py(k.y));
        final angle = k.angle * kDeg;
        fillEllipse(canvas, centre, k.rx * 1.3 * scale, k.ry * 1.4 * scale, rim, rotation: angle);
        fillEllipse(canvas, centre, k.rx * scale, k.ry * scale, knot, rotation: angle);
      }
    }
    if (mature.moss.isNotEmpty) {
      final paint = Paint();
      for (final tuft in mature.moss) {
        canvas.drawCircle(
          Offset(px(tuft.x), py(tuft.y)),
          math.max(0.5, tuft.r * scale),
          paint..color = mossColor(palette, tuft.alt).withValues(alpha: 0.85),
        );
      }
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
      case LeafShape.lance:
        // The willow: long and thin, hanging from its stem.
        path.addOval(Rect.fromCenter(center: Offset(size * 0.8, 0), width: size * 3, height: size * 0.44));
      case LeafShape.scale:
        // The cypress: short, fat foliage that overlaps into a dense mass.
        path.addOval(Rect.fromCenter(center: Offset(size * 0.45, 0), width: size * 1.2, height: size * 0.8));
      case LeafShape.feather:
        // The acacia: a rib with tiny leaflets; the leaflets are strokes added
        // by the caller where there is room to see them.
        path.addOval(Rect.fromCenter(center: Offset(size * 0.7, 0), width: size * 2.2, height: size * 0.6));
      case LeafShape.needle:
        // A tuft of needles. At avatar sizes a single stroke is all that
        // survives the downsample, so the fan collapses to three, then one.
        final length = size * 1.6;
        final fan = scale > 1.6
            ? const [-40.0, -20.0, 0.0, 20.0, 40.0]
            : scale > 1
            ? const [-30.0, 0.0, 30.0]
            : const [0.0];
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
      ..strokeWidth = math.max(1.0, 0.42 * scale);
    final rib = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Seed leaves: two colours per frame, yellowing as the seedling ages (paint_spec.dart).
    final seedLeaf = cotyledonColor(palette, false, step: scene.step, position: scene.position);
    final seedLeafAlt = cotyledonColor(palette, true, step: scene.step, position: scene.position);

    for (final leaf in scene.leaves) {
      if (!leaf.visible || !(leaf.size > 0)) continue;
      final grown = _revealAt(leaf.depth);
      if (grown <= 0) continue;

      final shimmer = still ? 0.0 : math.sin(timeMs * 0.0021 + leaf.phase * 6.283);
      final x = originX + (leaf.x + shimmer * 0.35) * scale;
      final y = originY + leaf.y * scale;
      // A bud is a smaller, tighter version of the same leaf, so unfurling is a
      // size change rather than a pop-in.
      final size = leaf.size * leafScale * grown * (leaf.open ? 1 : 0.45);
      final angle = leaf.angle + shimmer * (shape == LeafShape.frond ? 2 : 6);
      // A bud is translucent; a seed leaf or whorl fades as it goes.
      final alpha = (leaf.open ? 1.0 : 0.75) * leafFadeAlpha(leaf.fade);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle * kDeg);
      if (leaf.kind == LeafKind.cotyledon) {
        // Rounder and fleshier than any species leaf (a conifer's are needles).
        final c = cotyledonShape(scene.form, size);
        fillEllipse(
          canvas,
          Offset(c.cx, 0),
          c.rx,
          c.ry,
          fill..color = (leaf.phase > 0.5 ? seedLeafAlt : seedLeaf).withValues(alpha: alpha),
        );
        canvas.restore();
        continue;
      }
      final alt = leaf.phase > 0.5;
      final colour = (alt ? palette.leafAlt : palette.leaf).withValues(alpha: alpha);
      final down = Offset(math.cos((90 - angle) * kDeg), math.sin((90 - angle) * kDeg));
      final path = _leafPath(shape, size, scale, down);
      if (shape == LeafShape.needle) {
        canvas.drawPath(path, stroke..color = colour);
      } else {
        canvas.drawPath(path, fill..color = colour);
        final frond = shape == LeafShape.frond;
        final feather = shape == LeafShape.feather;
        if (frond || feather || shape == LeafShape.large) {
          rib
            ..color = (alt ? palette.leaf : palette.leafAlt).withValues(alpha: alpha)
            ..strokeWidth = math.max(0.5, size * 0.08);
          canvas.drawLine(
            Offset.zero,
            Offset(size * (frond ? 2.9 : feather ? 1.7 : 1.5), 0),
            rib,
          );
          // Leaflets either side of the rib, where there is room to see them.
          if ((frond || feather) && scale > 1.4) {
            final pairs = frond ? 6 : 4;
            final length = size * (frond ? 3.2 : 1.8);
            final reachMax = size * (frond ? 0.9 : 0.4);
            rib.strokeWidth = math.max(0.5, size * 0.06);
            for (var k = 1; k <= pairs; k++) {
              final at = k / (pairs + 1) * length;
              final reach = reachMax * (1 - k / (pairs + 3));
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
        // A bunch of three under the crown (spec §10.6a): radii (0.42, 0.6)·s.
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
      case FruitStyle.apple:
        canvas.drawCircle(c, size * 0.85, paint);
        canvas.drawLine(
          Offset(c.dx, c.dy - size * 0.8),
          Offset(c.dx + size * 0.15, c.dy - size * 1.25),
          Paint()
            ..color = palette.fruitAlt
            ..strokeWidth = math.max(0.5, size * 0.14),
        );
      case FruitStyle.pomegranate:
        canvas.drawCircle(c, size * 0.9, paint);
        // The calyx crown on top.
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - size * 0.3, c.dy - size * 0.75)
            ..lineTo(c.dx - size * 0.35, c.dy - size * 1.15)
            ..lineTo(c.dx, c.dy - size * 0.95)
            ..lineTo(c.dx + size * 0.35, c.dy - size * 1.15)
            ..lineTo(c.dx + size * 0.3, c.dy - size * 0.75)
            ..close(),
          Paint()..color = palette.fruitAlt,
        );
      case FruitStyle.catkin:
        canvas.drawOval(
          Rect.fromCenter(center: c.translate(0, size * 0.5), width: size * 0.64, height: size * 1.8),
          paint,
        );
        final seed = Paint()..color = palette.fruitAlt;
        for (final (ox, oy) in const [(-0.12, 0.1), (0.14, 0.55), (-0.1, 1.0)]) {
          canvas.drawCircle(Offset(c.dx + ox * size, c.dy + oy * size), size * 0.12, seed);
        }
      case FruitStyle.pod:
        // A hanging, curved seed pod with a seam.
        final pod = Path()
          ..moveTo(c.dx - size * 0.5, c.dy - size * 0.3)
          ..quadraticBezierTo(c.dx + size * 0.1, c.dy + size * 1.2, c.dx + size * 0.7, c.dy + size * 0.9);
        canvas.drawPath(
          pod,
          Paint()
            ..color = palette.fruit
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(0.8, size * 0.4),
        );
        canvas.drawPath(
          pod,
          Paint()
            ..color = palette.fruitAlt
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(0.4, size * 0.1),
        );
      case FruitStyle.berry:
        canvas.drawCircle(c, size * 0.5, paint);
        canvas.drawCircle(Offset(c.dx - size * 0.4, c.dy + size * 0.45), size * 0.38, paint);
        canvas.drawCircle(
          Offset(c.dx + size * 0.55, c.dy + size * 0.35),
          size * 0.42,
          Paint()..color = palette.fruitAlt,
        );
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
        if (!(blossom.size > 0)) continue;
        canvas.drawCircle(
          Offset(originX + blossom.x * scale, originY + blossom.y * scale),
          blossom.size * leafScale * _blossomRadius,
          paint,
        );
      }
    }

    for (final fruit in scene.fruits) {
      // A fruit arriving in a tween swells in; the 1.4 px floor must not pop it.
      if (!(fruit.size > 0)) continue;
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
        if (branch.depth < scene.maxDepth - 2 || !(branch.w0 > 0)) continue;
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

    // In the crown once it has a twig that holds a bird; until then the bird
    // waits on the ground (paintForeground).
    paintCrownBird(canvas, frame);
  }


  @override
  bool shouldRepaint(TreePainter old) =>
      old.timeMs != timeMs ||
      !identical(old.scene, scene) ||
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
