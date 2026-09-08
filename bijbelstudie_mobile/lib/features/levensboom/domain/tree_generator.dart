/// The Levensboom generator: level, XP and species in, a scene graph out.
///
/// A port of the website's `lib/levensboom/generate.ts`, kept line-for-line
/// comparable on purpose - `test/levensboom_parity_test.dart` and the web's
/// `tests/levensboom.test.ts` assert the same counts from the same seed, and if
/// one drifts a user's tree stops being the same tree on their two devices.
///
/// Pure: no Canvas, no clock. Season, time of day, scene and animal are
/// deliberately not inputs because they only touch colour and render-only
/// layers (`palette.dart`, `tree_view.dart`).
///
/// Contract: `docs/levensboom-spec.md` §4 in the website repo.
library;

import 'dart:math' as math;

import 'rng.dart';
import 'species.dart';
import 'traits.dart';

const double kGroundY = 88;
const double kTrunkX = 50;

/// How much earth the bounds include under the ground line.
const double kGroundPad = 8;
const double _deg = math.pi / 180;

/// Hard stop on the recursion, checked before any random draw so it cannot
/// desync the two platforms' streams.
///
/// Branch count is exponential in depth and the level curve has no ceiling.
/// Without a ceiling a level-60 account hands a low-end phone a five-figure
/// scene graph to repaint every frame; past this point growth shows up as
/// scale, traits and fruit instead of more twigs.
const int kMaxBranches = 900;

/// Same reasoning, for the layer that is repainted per frame.
const int kMaxLeaves = 1400;

class Branch {
  const Branch({
    required this.x0,
    required this.y0,
    required this.cx,
    required this.cy,
    required this.x1,
    required this.y1,
    required this.w0,
    required this.w1,
    required this.depth,
  });

  final double x0, y0, cx, cy, x1, y1, w0, w1;
  final int depth;
}

class Leaf {
  Leaf({
    required this.x,
    required this.y,
    required this.angle,
    required this.size,
    required this.phase,
    required this.hardiness,
    required this.bloomOrder,
    required this.depth,
    this.visible = true,
    this.open = true,
  });

  final double x, y, angle, size;

  /// 0..1 wind offset, so the canopy shimmers instead of pulsing as one block.
  final double phase;

  /// 0..1; the leaves with the highest values are what a wilting tree sheds.
  final double hardiness;

  final int bloomOrder;
  final int depth;

  bool visible;

  /// False while the leaf is still a bud - the in-level XP progress made visual.
  bool open;
}

class Ornament {
  const Ornament({
    required this.x,
    required this.y,
    required this.size,
    required this.index,
  });

  final double x, y, size;
  final int index;
}

/// What the tree actually occupies, so a renderer can frame it instead of
/// letterboxing a fixed 100x100 box.
///
/// A level-1 kiem and a level-30 tree are wildly different heights; without
/// this the kiem is a speck at the bottom of an empty sky and the big tree
/// still leaves a third of the frame unused. Always includes the ground line
/// plus a band of earth under it.
class TreeBounds {
  const TreeBounds(this.minX, this.maxX, this.minY, this.maxY);

  final double minX, maxX, minY, maxY;

  double get width => maxX - minX < 1 ? 1 : maxX - minX;
  double get height => maxY - minY < 1 ? 1 : maxY - minY;
}

class TreeScene {
  const TreeScene({
    required this.branches,
    required this.leaves,
    required this.blossoms,
    required this.fruits,
    required this.perch,
    required this.bounds,
    required this.traits,
    required this.growth,
    required this.maxDepth,
    required this.level,
    required this.frac,
    required this.health,
    required this.species,
    required this.form,
  });

  final List<Branch> branches;
  final List<Leaf> leaves;
  final List<Ornament> blossoms;
  final List<Ornament> fruits;

  /// Where a bird or a dove sits: the leaf nearest the upper right of the crown.
  final ({double x, double y})? perch;
  final TreeBounds bounds;
  final List<TreeTrait> traits;
  final double growth;
  final int maxDepth;
  final int level;
  final double frac;
  final double health;
  final TreeSpecies species;
  final TreeForm form;
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Asymptotic, so the curve needs no cap: level 40 is visibly bigger than level
/// 20, but the gap keeps shrinking and the tree never grows off the canvas.
/// Level 1 is exactly zero - a kiem, two leaves on a stem.
double growthForLevel(int level) => 1 - 1 / (1 + ((level < 1 ? 1 : level) - 1) / 6);

/// 0 at level 1 (the stem only), 1 at level 2, 4 at level 8, 6 from level 26.
int maxDepthForLevel(int level) {
  final value = (7 * growthForLevel(level)).round();
  return value > 7 ? 7 : value;
}

TreeScene generateTree({
  required String seed,
  required int level,
  required double frac,
  double health = 1,
  TreeSpecies species = kDefaultSpecies,
}) {
  final lvl = level < 1 ? 1 : level;
  final f = _clamp(frac, 0, 1);
  final h = _clamp(health, 0, 1);
  final sp = kSpecies[species]!;

  final rand = seededRng(seed);
  final growth = growthForLevel(lvl);
  final maxDepth = maxDepthForLevel(lvl);
  final droopT = (1 - h) * 0.25;
  final leafCount = maxDepth == 0
      ? 2
      : math.max(2, ((3 + 7 * growth) * sp.leafCountMul).round());
  final blossoming = sp.blossom == BlossomMode.always ||
      (sp.blossom == BlossomMode.seasonal && hasTrait(lvl, TreeTrait.blossom));

  final branches = <Branch>[];
  final leaves = <Leaf>[];

  void emitLeaves(double x, double y, double angle, int depth) {
    for (var i = 0; i < leafCount; i++) {
      if (leaves.length >= kMaxLeaves) return;
      var a = angle + (rand() * 2 - 1) * 70;
      var distance = rand() * 2.6 * (0.5 + growth);
      var size = (0.8 + rand() * 0.7) * sp.leafSizeMul;
      final phase = rand();
      final hardiness = rand();
      if (maxDepth == 0) {
        // A kiem is a stem with one leaf either side. The five draws above are
        // still made, so the stream stays aligned once the tree grows out of it.
        a = angle + (i == 0 ? -58 : 58);
        distance = 1.4;
        size = 1.6 * sp.leafSizeMul;
      }
      leaves.add(
        Leaf(
          x: x + math.cos(a * _deg) * distance,
          y: y + math.sin(a * _deg) * distance,
          angle: a,
          size: size,
          phase: phase,
          hardiness: hardiness,
          bloomOrder: leaves.length,
          depth: depth,
        ),
      );
    }
  }

  void recurse(
    double x0,
    double y0,
    double angle,
    double len,
    double width,
    int depth, [
    bool leader = true,
  ]) {
    if (branches.length >= kMaxBranches) return;

    final curve = (rand() * 2 - 1) * sp.curveAmp;
    final endAngle = angle + curve;
    final midAngle = angle + curve * 0.5;

    final x1 = x0 + math.cos(endAngle * _deg) * len;
    final y1 = y0 + math.sin(endAngle * _deg) * len;

    branches.add(
      Branch(
        x0: x0,
        y0: y0,
        cx: x0 + math.cos(midAngle * _deg) * len * 0.5,
        cy: y0 + math.sin(midAngle * _deg) * len * 0.5,
        x1: x1,
        y1: y1,
        w0: width,
        w1: width * sp.childWidthRatio,
        depth: depth,
      ),
    );

    if (depth >= maxDepth) {
      emitLeaves(x1, y1, endAngle, depth);
      return;
    }

    // Two children by default, a third with a chance that rises with growth:
    // that is what makes a high level read as *fuller* and not merely taller.
    // A conical tree's leader always fans three - itself and two sides - but
    // still makes the draw, so the stream stays aligned across species.
    final third = rand() < 0.15 + 0.2 * growth + sp.thirdChildBias;
    final spread = sp.spreadBase + rand() * sp.spreadJitter;
    final spine = sp.form == TreeForm.conical && leader;
    final childCount = spine ? 3 : (depth == 0 ? 2 : (third ? 3 : 2));

    for (var i = 0; i < childCount; i++) {
      // -1..1 across the fan. childCount is never 1, so no guard is needed.
      final t = (i / (childCount - 1)) * 2 - 1;
      final jitter = (rand() * 2 - 1) * 8;
      double raw;
      double childLen;
      double childWidth;
      var childLeader = false;
      if (spine) {
        if (i == 1) {
          // The leader keeps going up; that is the whole cedar silhouette.
          raw = endAngle + jitter * 0.35;
          childLen = len * 0.72;
          childWidth = width * 0.72;
          childLeader = true;
        } else {
          // Side branches go out nearly flat, longer near the ground.
          raw = endAngle + t * (spread + 40) + jitter;
          childLen = len * sp.childLenRatio * (0.55 + 0.45 * (1 - depth / maxDepth));
          childWidth = width * 0.55;
        }
      } else {
        raw = endAngle + t * spread + jitter;
        childLen = len * sp.childLenRatio;
        childWidth = width * sp.childWidthRatio;
      }
      // Wilt rotates the tip toward straight down, more the further out it is.
      final droop = droopT * ((depth + 1) / maxDepth);
      final childAngle = raw + (90 - raw) * droop;
      recurse(x1, y1, childAngle, childLen, childWidth, depth + 1, childLeader);
    }

    if (depth == maxDepth - 1) emitLeaves(x1, y1, endAngle, depth);
  }

  /// One curved trunk of segments and a crown of fronds. Fronds are ordinary
  /// leaves with a big `size`; the renderer draws the shape.
  void growPalm(
    double x0,
    double y0,
    double angle0,
    double trunkLen,
    double trunkWidth,
    int depthBase,
  ) {
    final segments = maxDepth == 0 ? 1 : math.min(6, maxDepth + 1);
    final segLen = trunkLen / segments;
    var x = x0;
    var y = y0;
    var angle = angle0;
    var width = trunkWidth;
    for (var i = 0; i < segments; i++) {
      if (branches.length >= kMaxBranches) return;
      // Bends onward in the direction of its own lean, segment after segment.
      final curve = (rand() * 2 - 1) * sp.curveAmp + (angle0 + 90) * 0.35;
      final endAngle = angle + curve;
      final midAngle = angle + curve * 0.5;
      final x1 = x + math.cos(endAngle * _deg) * segLen;
      final y1 = y + math.sin(endAngle * _deg) * segLen;
      branches.add(
        Branch(
          x0: x,
          y0: y,
          cx: x + math.cos(midAngle * _deg) * segLen * 0.5,
          cy: y + math.sin(midAngle * _deg) * segLen * 0.5,
          x1: x1,
          y1: y1,
          w0: width,
          w1: width * 0.9,
          depth: depthBase + i,
        ),
      );
      x = x1;
      y = y1;
      angle = endAngle;
      width *= 0.9;
    }

    final count = maxDepth == 0 ? 2 : 4 + (8 * growth).round();
    for (var i = 0; i < count; i++) {
      if (leaves.length >= kMaxLeaves) return;
      final t = count == 1 ? 0.0 : (i / (count - 1)) * 2 - 1;
      final jitter = (rand() * 2 - 1) * 8;
      final size = (2.2 + 2.6 * growth) * (0.85 + rand() * 0.3) * sp.leafSizeMul;
      final phase = rand();
      final hardiness = rand();
      var a = angle + t * 95 + jitter;
      // Wilt lets the fronds hang.
      a += (90 - a) * droopT * 0.6;
      leaves.add(
        Leaf(
          x: x + math.cos(a * _deg) * size * 0.3,
          y: y + math.sin(a * _deg) * size * 0.3,
          angle: a,
          size: size,
          phase: phase,
          hardiness: hardiness,
          bloomOrder: leaves.length,
          depth: depthBase + segments - 1,
        ),
      );
    }
  }

  void grow(double x0, double y0, double angle, double len, double width, int depth) {
    if (sp.form == TreeForm.palm) {
      growPalm(x0, y0, angle, len, width, depth);
    } else {
      recurse(x0, y0, angle, len, width, depth);
    }
  }

  final lean = (rand() * 2 - 1) * 6 * sp.leanMul;
  final trunkLen = (4 + 36 * growth) * sp.trunkLenMul;
  final trunkWidth = (0.8 + 6.2 * growth) * sp.trunkWidthMul;
  grow(kTrunkX, kGroundY, -90 + lean, trunkLen, trunkWidth, 0);

  if (hasTrait(lvl, TreeTrait.twin)) {
    // Drawn after the main tree finishes so the main tree's shape never changes
    // when this unlocks - the user gains a second trunk, they do not get a
    // different tree.
    final side = rand() < 0.5 ? -1 : 1;
    grow(
      kTrunkX + side * 6,
      kGroundY,
      -90 + lean + side * 14,
      trunkLen * 0.62,
      trunkWidth * 0.55,
      1,
    );
  }

  // Wilt sheds a scatter rather than a block, and the same leaves return on
  // recovery because `hardiness` is seeded.
  final visibleCut = 0.55 + 0.45 * h;
  final openCut = (leaves.length * (0.5 + 0.5 * f)).ceil();
  for (final leaf in leaves) {
    leaf.visible = leaf.hardiness <= visibleCut;
    leaf.open = leaf.bloomOrder < openCut;
  }

  final visible = leaves.where((leaf) => leaf.visible).toList();

  final blossoms = <Ornament>[];
  if (blossoming) {
    final cap = (6 + 10 * growth).round();
    for (var i = 0; i < visible.length && blossoms.length < cap; i += 9) {
      blossoms.add(
        Ornament(
          x: visible[i].x,
          y: visible[i].y,
          size: visible[i].size,
          index: blossoms.length,
        ),
      );
    }
  }

  final fruits = <Ornament>[];
  final wanted = fruitCount(lvl);
  if (wanted > 0 && visible.isNotEmpty) {
    // Highest leaves first, so fruit hangs in the canopy and not on the trunk.
    final highest = [...visible]
      ..sort(
        (a, b) => a.y == b.y
            ? a.bloomOrder.compareTo(b.bloomOrder)
            : a.y.compareTo(b.y),
      );
    final stride = math.max(1, highest.length ~/ wanted);
    for (var i = 0; i < wanted; i++) {
      final leaf = highest[math.min(highest.length - 1, i * stride)];
      fruits.add(Ornament(x: leaf.x, y: leaf.y, size: leaf.size, index: i));
    }
  }

  // No random draw here, so it is always computed: whether a bird sits on it
  // is the renderer's business.
  ({double x, double y})? perch;
  if (visible.isNotEmpty) {
    var best = visible.first;
    var bestDistance = double.infinity;
    for (final leaf in visible) {
      final dx = leaf.x - 62;
      final dy = leaf.y - 40;
      final d = dx * dx + dy * dy;
      if (d < bestDistance) {
        bestDistance = d;
        best = leaf;
      }
    }
    perch = (x: best.x, y: best.y);
  }

  // Padded by a leaf's worth so the outermost canopy is never clipped; a frond
  // is drawn well past its anchor, so it pads by its own length.
  var minX = kTrunkX, maxX = kTrunkX, minY = kGroundY;
  for (final branch in branches) {
    minX = math.min(minX, math.min(branch.x0, branch.x1));
    maxX = math.max(maxX, math.max(branch.x0, branch.x1));
    minY = math.min(minY, math.min(branch.y0, branch.y1));
  }
  for (final leaf in visible) {
    final pad = sp.leafShape == LeafShape.frond ? leaf.size * 2.8 : 3.0;
    minX = math.min(minX, leaf.x - pad);
    maxX = math.max(maxX, leaf.x + pad);
    minY = math.min(minY, leaf.y - pad);
  }

  return TreeScene(
    branches: branches,
    leaves: leaves,
    blossoms: blossoms,
    fruits: fruits,
    perch: perch,
    bounds: TreeBounds(minX, maxX, minY, kGroundY + kGroundPad),
    traits: traitsForLevel(lvl),
    growth: growth,
    maxDepth: maxDepth,
    level: lvl,
    frac: f,
    health: h,
    species: species,
    form: sp.form,
  );
}
