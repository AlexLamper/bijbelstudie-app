/// The Levensboom generator: level and XP in, a scene graph out.
///
/// A port of the website's `lib/levensboom/generate.ts`, kept line-for-line
/// comparable on purpose - `test/levensboom_parity_test.dart` and the web's
/// `tests/levensboom.test.ts` assert the same counts from the same seed, and if
/// one drifts a user's tree stops being the same tree on their two devices.
///
/// Pure: no Canvas, no clock. Season and time of day are deliberately not
/// inputs because they only touch colour (`palette.dart`).
///
/// Contract: `docs/levensboom-spec.md` §4 in the website repo.
library;

import 'dart:math' as math;

import 'rng.dart';
import 'traits.dart';

const double kGroundY = 88;
const double kTrunkX = 50;
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

class Mote {
  const Mote({required this.x, required this.y, required this.phase});

  final double x, y, phase;
}

/// What the tree actually occupies, so a renderer can frame it instead of
/// letterboxing a fixed 100x100 box.
///
/// A level-2 sapling and a level-30 tree are wildly different heights; without
/// this the sapling is a speck at the bottom of an empty sky and the big tree
/// still leaves a third of the frame unused. Always includes the ground line.
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
    required this.bird,
    required this.fireflies,
    required this.bounds,
    required this.traits,
    required this.growth,
    required this.maxDepth,
    required this.level,
    required this.frac,
    required this.health,
  });

  final List<Branch> branches;
  final List<Leaf> leaves;
  final List<Ornament> blossoms;
  final List<Ornament> fruits;
  final ({double x, double y})? bird;
  final List<Mote> fireflies;
  final TreeBounds bounds;
  final List<TreeTrait> traits;
  final double growth;
  final int maxDepth;
  final int level;
  final double frac;
  final double health;
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Asymptotic, so the curve needs no cap: level 40 is visibly bigger than level
/// 20, but the gap keeps shrinking and the tree never grows off the canvas.
double growthForLevel(int level) => 1 - 1 / (1 + (level < 1 ? 1 : level) / 8);

int maxDepthForLevel(int level) {
  final value = 2 + (5 * growthForLevel(level)).round();
  return value > 7 ? 7 : value;
}

TreeScene generateTree({
  required String seed,
  required int level,
  required double frac,
  double health = 1,
}) {
  final lvl = level < 1 ? 1 : level;
  final f = _clamp(frac, 0, 1);
  final h = _clamp(health, 0, 1);

  final rand = seededRng(seed);
  final growth = growthForLevel(lvl);
  final maxDepth = maxDepthForLevel(lvl);
  final droopT = (1 - h) * 0.25;
  final canopy = hasTrait(lvl, TreeTrait.canopy);

  final branches = <Branch>[];
  final leaves = <Leaf>[];

  void emitLeaves(double x, double y, double angle, int depth) {
    if (leaves.length >= kMaxLeaves) return;
    // Enough leaves per tip, held close enough to it, that the clusters read as
    // one canopy. Fewer and wider - which is where this started - draws a bare
    // skeleton wearing a handful of specks, and a bare tree is exactly the
    // message this feature must not send.
    final count = canopy ? (4 + 6 * growth).round() : 3;
    for (var i = 0; i < count; i++) {
      final a = angle + (rand() * 2 - 1) * 70;
      final distance = rand() * 2.6 * (0.5 + growth);
      leaves.add(
        Leaf(
          x: x + math.cos(a * _deg) * distance,
          y: y + math.sin(a * _deg) * distance,
          angle: a,
          size: 0.8 + rand() * 0.7,
          phase: rand(),
          hardiness: rand(),
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
    int depth,
  ) {
    if (branches.length >= kMaxBranches) return;

    final curve = (rand() * 2 - 1) * 10;
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
        w1: width * 0.68,
        depth: depth,
      ),
    );

    if (depth >= maxDepth) {
      emitLeaves(x1, y1, endAngle, depth);
      return;
    }

    // Two children by default, a third with a chance that rises with growth:
    // that is what makes a high level read as *fuller* and not merely taller.
    final childCount = depth == 0
        ? 2
        : (rand() < 0.15 + 0.2 * growth ? 3 : 2);
    final spread = 26 + rand() * 14;

    for (var i = 0; i < childCount; i++) {
      // -1..1 across the fan. childCount is never 1, so no guard is needed.
      final t = (i / (childCount - 1)) * 2 - 1;
      final jitter = (rand() * 2 - 1) * 8;
      final raw = endAngle + t * spread + jitter;
      // Wilt rotates the tip toward straight down, more the further out it is.
      final droop = droopT * ((depth + 1) / maxDepth);
      final childAngle = raw + (90 - raw) * droop;
      recurse(x1, y1, childAngle, len * 0.74, width * 0.68, depth + 1);
    }

    if (depth == maxDepth - 1) emitLeaves(x1, y1, endAngle, depth);
  }

  final lean = (rand() * 2 - 1) * 6;
  final trunkLen = 15 + 25 * growth;
  final trunkWidth = 2 + 5 * growth;
  recurse(kTrunkX, kGroundY, -90 + lean, trunkLen, trunkWidth, 0);

  if (hasTrait(lvl, TreeTrait.twin)) {
    // Drawn after the main tree finishes so the main tree's shape never changes
    // when this unlocks - the user gains a second trunk, they do not get a
    // different tree.
    final side = rand() < 0.5 ? -1 : 1;
    recurse(
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
  if (hasTrait(lvl, TreeTrait.blossom)) {
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

  ({double x, double y})? bird;
  if (hasTrait(lvl, TreeTrait.bird) && visible.isNotEmpty) {
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
    bird = (x: best.x, y: best.y);
  }

  final fireflies = <Mote>[];
  if (hasTrait(lvl, TreeTrait.fireflies) && visible.isNotEmpty) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final leaf in visible) {
      if (leaf.x < minX) minX = leaf.x;
      if (leaf.x > maxX) maxX = leaf.x;
      if (leaf.y < minY) minY = leaf.y;
      if (leaf.y > maxY) maxY = leaf.y;
    }
    for (var i = 0; i < 12; i++) {
      fireflies.add(
        Mote(
          x: minX + rand() * (maxX - minX),
          y: minY + rand() * (maxY - minY),
          phase: rand(),
        ),
      );
    }
  }

  // Padded by a leaf's worth so the outermost canopy is never clipped.
  var minX = kTrunkX, maxX = kTrunkX, minY = kGroundY;
  for (final branch in branches) {
    minX = math.min(minX, math.min(branch.x0, branch.x1));
    maxX = math.max(maxX, math.max(branch.x0, branch.x1));
    minY = math.min(minY, math.min(branch.y0, branch.y1));
  }
  for (final leaf in visible) {
    minX = math.min(minX, leaf.x - 3);
    maxX = math.max(maxX, leaf.x + 3);
    minY = math.min(minY, leaf.y - 3);
  }

  return TreeScene(
    branches: branches,
    leaves: leaves,
    blossoms: blossoms,
    fruits: fruits,
    bird: bird,
    fireflies: fireflies,
    bounds: TreeBounds(minX, maxX, minY, kGroundY + 6),
    traits: traitsForLevel(lvl),
    growth: growth,
    maxDepth: maxDepth,
    level: lvl,
    frac: f,
    health: h,
  );
}
