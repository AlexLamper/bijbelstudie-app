/// The tree generator, growth v2: seed, position and species in, a scene
/// graph out.
///
/// A 1:1 port of the website's `lib/levensboom/generate.ts`, kept
/// line-for-line comparable on purpose: the same node paths, the same draws
/// per stream in the same order, the same arithmetic in the same order, the
/// same breadth-first order and the same caps. `test/levensboom_parity_test.dart`
/// asserts the web's own fixture (`test/fixtures/levensboom_v2.json`, printed by
/// `npm run tree:fixtures`); if one side drifts, a reader's tree stops being the
/// same tree on their two devices.
///
/// What makes it grow instead of morph (plan §4.3):
/// - Every node draws from its own seeded stream (`nodeRng(seed, path)`), a
///   fixed vector of [kDraws] values whether it uses them or not.
/// - A node exists from its birth step on and never disappears; it only gets
///   longer and thicker. Only seed leaves, seedling leaf whorls and a tip's own
///   leaves (after it has grown children for `innerKeep` steps) are temporary.
/// - Topology (what exists) depends only on the structural step `k`, integers,
///   table literals and draws - never on a trig result. The position `e` and
///   `frac` only feed arithmetic.
/// - Angles are fixed per path; health droops them on top.
///
/// Pure: no Canvas, no clock. Season, time of day, scene and animal are
/// deliberately not inputs because they only touch colour and render-only
/// layers (`palette.dart`, `tree_view.dart`).
///
/// Contract: `docs/levensboom-spec.md` §3-§4 and §10 in the website repo.
/// Growth table: `growth.dart`.
library;

import 'dart:math' as math;

import 'growth.dart';
import 'rng.dart';
import 'species.dart';
import 'stages.dart';
import 'traits.dart';

const double kGroundY = 88;
const double kTrunkX = 50;

/// How much earth the bounds include under the ground line.
const double kGroundPad = 8;

/// Fruit hangs from a twig but must not inherit a frond's or a fig leaf's size.
const double kMaxFruitSize = 1.6;

/// Safety nets. The growth table keeps every species, seed and step up to 60
/// under 80 % of these (tested on the website); if one ever binds, the
/// traversal is breadth-first by path, so it cuts the newest wood and never
/// old wood.
const int kMaxBranches = 900;
const int kMaxLeaves = 1400;

/// Values per node stream: 0 curve · 1 spread · 2 thirdU · 3-5 jitter per child slot · 6 lenJitter · 7 birthJitter · 8 twigU · 9 reserve.
const int kDraws = 10;

/// Values per leaf stream: 0 angle · 1 distance · 2 size · 3 phase · 4 hardiness.
const int kLeafDraws = 5;

const int _curve = 0;
const int _spread = 1;
const int _third = 2;
const int _jitter = 3;
const int _len = 6;

/// Birth jitter. The trunk has no birth to jitter, so its slot 7 is the lean; the twin root's is its side.
const int _birth = 7;

/// Reserve slot 8, taken by growth v2's maturing twigs: whether (and when) this tip forks once past step 20.
const int _twig = 8;

const double _deg = math.pi / 180;
const List<int> _slotOffset = [-1, 1, 0];

/// Stands in for the website's `Number.POSITIVE_INFINITY` "no child yet".
const int _never = 1 << 40;

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
    required this.path,
    required this.birth,
    required this.wood,
  });

  final double x0, y0, cx, cy, x1, y1, w0, w1;
  final int depth;

  /// Stable id ("T", "T01", "W2" ...): a branch keeps its path, angle and anchor for life.
  final String path;

  /// The step this branch appeared at.
  final int birth;

  /// 0 = green stem, 1 = bark: the share of the branch, from its base up, that has turned woody.
  final double wood;

  Branch copyWith({
    double? x0,
    double? y0,
    double? cx,
    double? cy,
    double? x1,
    double? y1,
    double? w0,
    double? w1,
    double? wood,
  }) {
    return Branch(
      x0: x0 ?? this.x0,
      y0: y0 ?? this.y0,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
      x1: x1 ?? this.x1,
      y1: y1 ?? this.y1,
      w0: w0 ?? this.w0,
      w1: w1 ?? this.w1,
      depth: depth,
      path: path,
      birth: birth,
      wood: wood ?? this.wood,
    );
  }
}

/// `leaf` on a tip, `cotyledon` a seed leaf, `seedling` a leaf of a whorl on
/// the young stem, `frond` a palm frond.
enum LeafKind { leaf, cotyledon, seedling, frond }

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
    required this.path,
    required this.birth,
    required this.kind,
    this.fade = 1,
    this.visible = true,
    this.open = true,
  });

  final double x, y, angle, size;

  /// 0..1 wind offset, so the canopy shimmers instead of pulsing as one block.
  final double phase;

  /// 0..1; the leaves with the highest values are what a wilting tree sheds.
  final double hardiness;

  /// Rank by (birth, path): older leaves open first as `frac` rises.
  int bloomOrder;

  /// The branch depth this leaf hangs from.
  final int depth;

  bool visible;

  /// False while the leaf is still a bud - the in-level XP progress made visual.
  bool open;

  /// Stable id ("T01L2", "C0", "S2L1", "PF3"), for tweening between two positions.
  final String path;

  /// The step this leaf appeared at.
  final int birth;
  final LeafKind kind;

  /// 1 = fresh, 0 = about to fall: seed leaves and seedling whorls run this
  /// down over their last positions (their size shrinks with it; a renderer
  /// fades them too, `leafFadeAlpha` in `paint_spec.dart`). Always 1 on crown leaves.
  final double fade;

  Leaf copyWith({double? x, double? y, double? angle, double? size, double? fade}) {
    return Leaf(
      x: x ?? this.x,
      y: y ?? this.y,
      angle: angle ?? this.angle,
      size: size ?? this.size,
      phase: phase,
      hardiness: hardiness,
      bloomOrder: bloomOrder,
      depth: depth,
      path: path,
      birth: birth,
      kind: kind,
      fade: fade ?? this.fade,
      visible: visible,
      open: open,
    );
  }
}

class Ornament {
  const Ornament({
    required this.x,
    required this.y,
    required this.size,
    required this.index,
    required this.path,
  });

  final double x, y, size;
  final int index;

  /// The leaf (blossom) or twig (fruit) it hangs on; `PD<i>` for a palm's dates.
  final String path;

  Ornament copyWith({double? x, double? y, double? size}) {
    return Ornament(x: x ?? this.x, y: y ?? this.y, size: size ?? this.size, index: index, path: path);
  }
}

/// What the tree actually occupies, so a renderer can guard its frame.
/// Always includes the ground line plus a band of earth under it.
class TreeBounds {
  const TreeBounds(this.minX, this.maxX, this.minY, this.maxY);

  final double minX, maxX, minY, maxY;

  double get width => maxX - minX < 1 ? 1 : maxX - minX;
  double get height => maxY - minY < 1 ? 1 : maxY - minY;
}

/// Render at this position (and step, default floor(position)) instead of the
/// one level/frac/floor give - the website's `TreeInput.at`. For the Groei
/// ladder and design tooling; traits and fruit still follow `level`.
class TreeAt {
  const TreeAt({required this.position, this.step});

  final double position;
  final num? step;
}

class TreeScene {
  const TreeScene({
    this.model = growthModel,
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
    required this.position,
    required this.step,
    required this.phase,
    required this.rings,
    required this.floor,
  });

  final int model;
  final List<Branch> branches;
  final List<Leaf> leaves;
  final List<Ornament> blossoms;
  final List<Ornament> fruits;

  /// Where a bird or a dove sits; null while the crown has no twig that can hold one.
  final ({double x, double y})? perch;
  final TreeBounds bounds;
  final List<TreeTrait> traits;

  /// Continuous size 0..~0.95 at [position] (the v1 name, kept for the renderers).
  final double growth;

  /// The deepest branch depth that exists.
  final int maxDepth;
  final int level;
  final double frac;
  final double health;
  final TreeSpecies species;
  final TreeForm form;

  /// Effective position e (size).
  final double position;

  /// Structural step k (topology).
  final int step;
  final TreeStage phase;
  final int rings;
  final GrowthFloor? floor;

  TreeScene copyWith({
    List<Branch>? branches,
    List<Leaf>? leaves,
    List<Ornament>? blossoms,
    List<Ornament>? fruits,
    ({double x, double y})? Function()? perch,
    TreeBounds? bounds,
    double? growth,
    double? health,
    double? position,
  }) {
    return TreeScene(
      model: model,
      branches: branches ?? this.branches,
      leaves: leaves ?? this.leaves,
      blossoms: blossoms ?? this.blossoms,
      fruits: fruits ?? this.fruits,
      perch: perch != null ? perch() : this.perch,
      bounds: bounds ?? this.bounds,
      traits: traits,
      growth: growth ?? this.growth,
      maxDepth: maxDepth,
      level: level,
      frac: frac,
      health: health ?? this.health,
      species: species,
      form: form,
      position: position ?? this.position,
      step: step,
      phase: phase,
      rings: rings,
      floor: floor,
    );
  }
}

double _clamp(double value, double min, double max) => math.min(max, math.max(min, value));

class _Node {
  _Node({
    required this.path,
    required this.depth,
    required this.rel,
    required this.twin,
    required this.leader,
    required this.tier,
    required this.tierBirth,
    required this.twig,
    required this.d,
    required this.appear,
    required this.baseLen,
    required this.baseWidth,
    required this.x0,
    required this.y0,
    required this.angle,
  });

  final String path;
  final int depth;

  /// Depth inside its own trunk (the twin counts from 0 again), for the birth table.
  final int rel;
  final bool twin;

  /// Conical spine: keeps going up and always forks three ways.
  final bool leader;

  /// Conical: depth inside a side tier (0 = the tier's root), -1 on the spine and in other forms.
  final int tier;

  /// Conical: the step the tier this node belongs to was born; its forks are timed from it.
  final int tierBirth;

  /// A maturing twig (the fork past the depth table): carries a smaller tuft.
  final bool twig;
  final List<double> d;
  final int appear;

  /// Index of this node's branch in `branches`.
  int bi = 0;
  final double baseLen;
  final double baseWidth;
  final double x0;
  final double y0;
  final double angle;
  double endAngle = 0;
  double len = 0;
  double x1 = 0;
  double y1 = 0;
}

class _Candidate {
  const _Candidate(this.leaf, this.h);

  final Leaf leaf;
  final int h;
}

/// Compares two ASCII paths the way the website's `<` / `>` does (UTF-16 code units).
int _comparePaths(String a, String b) => a.compareTo(b);

TreeScene generateTree({
  required String seed,
  required int level,
  required double frac,
  double health = 1,
  TreeSpecies species = kDefaultSpecies,
  GrowthFloor? floor,
  TreeAt? at,
}) {
  final lvl = level < 1 ? 1 : level;
  final f = _clamp(frac.isFinite ? frac : 0.0, 0, 1);
  final h = _clamp(health, 0, 1);
  final sp = speciesParams(species);
  final form = sp.form;
  final table = formTables[form]!;
  final fl = isFloor(floor) ? floor : null;

  final double e;
  final int k;
  if (at != null) {
    e = at.position.isNaN ? 1.0 : math.max(1.0, at.position);
    final s = at.step ?? e + 1e-9;
    k = s.isFinite ? math.max(1, s.floor()) : 1;
  } else {
    e = effectivePosition(lvl, f, fl);
    k = structuralStep(lvl, fl);
  }
  final size = sizeAt(form, e);
  final droopT = (1 - h) * 0.25;

  /// The step a level-gated feature arrived at, never later than now.
  int stepOfLevel(int l) => math.min(k, at != null ? l : structuralStep(l, fl));

  final branches = <Branch>[];
  final leaves = <Leaf>[];
  final nodes = <_Node>[];
  final byPath = <String, _Node>{};

  List<double> draws(String path) => nodeDraws(seed, path, kDraws);
  double woodOf(int appear, bool trunk) => trunk
      ? _clamp((e - geometry.woodStart) / geometry.woodSteps, 0, 1)
      : _clamp((e - appear - geometry.woodDelay) / geometry.woodSteps, 0, 1);

  void pushLeaf({
    required double x,
    required double y,
    required double angle,
    required double size,
    required double phase,
    required double hardiness,
    required int depth,
    required String path,
    required int birth,
    required LeafKind kind,
    double fade = 1,
  }) {
    if (leaves.length >= kMaxLeaves) return;
    leaves.add(
      Leaf(
        x: x,
        y: y,
        angle: angle,
        size: size,
        phase: phase,
        hardiness: hardiness,
        bloomOrder: 0,
        depth: depth,
        path: path,
        birth: birth,
        kind: kind,
        fade: fade,
      ),
    );
  }

  /// A temporary leaf's `fade` from its size factor: 1 while whole, 0 at `fadeMin`.
  double fadeShare(double shrink, double fadeMin) => _clamp((shrink - fadeMin) / (1 - fadeMin), 0, 1);

  /// Lay a node out at the current position and emit its branch.
  void place(_Node node, double grow, double w1Ratio, bool trunk, [double? curveOverride]) {
    final curve = curveOverride ?? (node.d[_curve] * 2 - 1) * sp.curveAmp;
    node.endAngle = node.angle + curve;
    final midAngle = node.angle + curve * 0.5;
    node.len = node.baseLen * grow;
    final width = node.baseWidth * grow;
    node.x1 = node.x0 + math.cos(node.endAngle * _deg) * node.len;
    node.y1 = node.y0 + math.sin(node.endAngle * _deg) * node.len;
    node.bi = branches.length;
    nodes.add(node);
    byPath[node.path] = node;
    branches.add(
      Branch(
        x0: node.x0,
        y0: node.y0,
        cx: node.x0 + math.cos(midAngle * _deg) * node.len * 0.5,
        cy: node.y0 + math.sin(midAngle * _deg) * node.len * 0.5,
        x1: node.x1,
        y1: node.y1,
        w0: width,
        w1: width * w1Ratio,
        depth: node.depth,
        path: node.path,
        birth: node.appear,
        wood: woodOf(node.appear, trunk),
      ),
    );
  }

  /// Leaves reduced to a forked node's inner keep; blossom never lands on them.
  final innerLeaves = <String>{};

  /// The leaves on a tip: the full tuft, kept for `innerKeep` steps after it
  /// forks; then (when [inner]) the first `innerLeaves` of them for good, as
  /// the foliage inside the crown. Leaves fall from the top of the index down,
  /// so the ones that stay are the oldest.
  void tipLeaves(_Node node, int firstChild, bool inner) {
    final full = firstChild > k || k < firstChild + table.innerKeep;
    final tuft = leavesPerTip(form, k, sp.leafCountMul, node.twig);
    int count;
    if (full) {
      count = tuft;
    } else if (inner && node.depth >= table.innerMinDepth && node.depth <= table.innerMaxDepth) {
      count = math.min(table.innerLeaves, tuft);
    } else {
      return;
    }
    final sizeMul = sp.leafSizeMul * leafSizeAtDepth(node.depth);
    for (var i = 0; i < count; i += 1) {
      var born = node.appear;
      while (born < k && leavesPerTip(form, born, sp.leafCountMul, node.twig) <= i) {
        born += 1;
      }
      final path = '${node.path}L$i';
      if (!full) innerLeaves.add(path);
      final ld = nodeDraws(seed, path, kLeafDraws);
      final grow = ramp(e, born);
      final a = node.endAngle + (ld[0] * 2 - 1) * 70;
      final distance = ld[1] * 2.6 * (0.5 + size) * grow * table.leafScatter;
      pushLeaf(
        x: node.x1 + math.cos(a * _deg) * distance,
        y: node.y1 + math.sin(a * _deg) * distance,
        angle: a,
        size: (0.8 + ld[2] * 0.7) * sizeMul * grow,
        phase: ld[3],
        hardiness: ld[4],
        depth: node.depth,
        path: path,
        birth: born,
        kind: LeafKind.leaf,
      );
    }
  }

  /// A point and heading at share t of a placed node's length (the curve read as a heading blend).
  ({double x, double y, double heading}) along(_Node node, double t) {
    final u = _clamp(t, 0, 1);
    final b = branches[node.bi];
    final x = (1 - u) * (1 - u) * b.x0 + 2 * (1 - u) * u * b.cx + u * u * b.x1;
    final y = (1 - u) * (1 - u) * b.y0 + 2 * (1 - u) * u * b.cy + u * u * b.y1;
    return (x: x, y: y, heading: node.angle + (node.endAngle - node.angle) * u);
  }

  double trunkBaseLen(double p, double lenJitter) =>
      (geometry.trunkLenBase + geometry.trunkLenGrow * sizeAt(form, p)) * sp.trunkLenMul * (0.9 + 0.2 * lenJitter);
  // Girth keeps growing past step 20 (maturing), and every width hangs off it.
  double trunkBaseWidth() =>
      (geometry.trunkWidthBase + geometry.trunkWidthGrow * widthAt(form, e)) * sp.trunkWidthMul * girthAt(e);

  final tD = draws('T');
  final lean = (tD[_birth] * 2 - 1) * geometry.lean * sp.leanMul;

  /// One trunk and its subtree, breadth-first by path so a cap cuts the newest
  /// wood. [twinStep] is null for the main tree.
  void growBranching(_Node root, int? twinStep) {
    final queue = <_Node>[];
    place(root, twinStep == null ? 1 : ramp(e, root.appear), sp.childWidthRatio, twinStep == null);
    queue.add(root);
    for (var q = 0; q < queue.length; q += 1) {
      final parent = queue[q];
      final childRel = parent.rel + 1;
      final spine = form == TreeForm.conical && parent.leader;
      final inTier = parent.tier >= 0;
      // The trunk forks in two (the house-style Y), a maturing twig forks in
      // two (fine outer growth), everything else may grow a third, middle child.
      final slots = spine ? const [0, 1, 2] : (parent.depth == 0 || parent.twig ? const [0, 1] : const [0, 1, 2]);
      var firstChild = _never;
      final spread = sp.spreadBase + parent.d[_spread] * sp.spreadJitter;

      for (final slot in slots) {
        if (branches.length >= kMaxBranches) break;
        final chance = slot == 2 && !spine;
        int base;
        int spreadSteps;
        // A maturing twig: the fork past the depth table, gated by the parent's reserve draw.
        var twig = false;
        if (inTier) {
          // A conical tier forks on its own clock, from the step the tier was
          // born, and only as deep as its age allows: the top stays pointed.
          final t = parent.tier + 1;
          final deep = parent.tierBirth <= table.tierDeepUntil
              ? table.tierFork.length
              : math.min(1, table.tierFork.length);
          if (t > deep) continue;
          base = parent.tierBirth + table.tierFork[t - 1];
          spreadSteps = table.tierForkSpread;
        } else if (twinStep == null) {
          if (childRel > table.birth.length) continue;
          twig = childRel == table.birth.length;
          if (twig && form != TreeForm.branching) continue;
          base = twig ? table.twigFrom : table.birth[childRel];
          spreadSteps = twig ? 1 : table.birthSpread[childRel];
        } else {
          if (childRel > geometry.twinMaxDepth + 1) continue;
          twig = childRel == geometry.twinMaxDepth + 1;
          if (twig && form != TreeForm.branching) continue;
          base = twig ? table.twigFrom : twinStep + childRel * geometry.twinDepthSteps;
          spreadSteps = twig ? 1 : geometry.twinBirthSpread;
        }
        final delay = chance ? table.thirdDelay : 0;
        if (base + delay > k) continue;
        final path = '${parent.path}$slot';
        final cd = draws(path);
        var appear = math.max(parent.appear + geometry.childDelay, base + delay + (cd[_birth] * spreadSteps).floor());
        if (twig) {
          // The parent's reserve draw decides; the chance only rises with the
          // step, so a twig that exists keeps existing.
          final u = parent.d[_twig];
          while (appear <= k && !(u < twigChanceAt(form, appear))) {
            appear += 1;
          }
        }
        if (chance) {
          // The parent's draw decides; the chance only rises with the step, so
          // once a third child exists it keeps existing.
          final u = parent.d[_third];
          while (appear <= k && !(u < thirdChanceAt(form, appear) + sp.thirdChildBias)) {
            appear += 1;
          }
        }
        if (appear > k) continue;
        firstChild = math.min(firstChild, appear);

        final offset = _slotOffset[slot];
        final jitter = (parent.d[_jitter + slot] * 2 - 1) * geometry.slotJitter;
        final lenJitter = 0.9 + 0.2 * cd[_len];
        double raw;
        double baseLen;
        double widthRatio;
        var leader = false;
        var tier = -1;
        var tierBirth = 0;
        if (spine) {
          if (slot == 2) {
            // The leader keeps going up; that is the whole cedar silhouette.
            raw = parent.endAngle + jitter * geometry.leaderJitter;
            baseLen = parent.baseLen * table.leaderLen * lenJitter;
            widthRatio = geometry.leaderWidth;
            leader = true;
          } else {
            // A tier leaves the spine nearly flat, sized to the trunk and
            // shorter the higher up the spine it sits.
            raw = parent.endAngle + offset * spread * geometry.tierAngle + jitter;
            baseLen = root.baseLen *
                sp.childLenRatio *
                table.tierLen *
                (1 - table.tierTaper * math.min(1.0, parent.rel / geometry.conicalDepth)) *
                lenJitter;
            widthRatio = geometry.tierWidth;
            tier = 0;
            tierBirth = appear;
          }
        } else if (inTier) {
          // A tier keeps going outward with only a slight fan: layered shelves.
          raw = parent.endAngle + offset * spread * geometry.tierChildSpread + jitter * geometry.tierChildJitter;
          baseLen = parent.baseLen * geometry.tierChildLen * lenJitter;
          widthRatio = geometry.tierChildWidth;
          tier = parent.tier + 1;
          tierBirth = parent.tierBirth;
        } else {
          raw = parent.endAngle + offset * spread + jitter;
          baseLen = parent.baseLen * sp.childLenRatio * lenJitter;
          widthRatio = sp.childWidthRatio;
        }
        // Wilt rotates the tip toward straight down, more the further out it
        // is; a weeping species hangs the same way when perfectly healthy.
        final droop = math.min(1.0, (droopT + sp.droopBase) * ((parent.depth + 1) / geometry.droopDepth));
        final child = _Node(
          path: path,
          depth: parent.depth + 1,
          rel: childRel,
          twin: parent.twin,
          leader: leader,
          tier: tier,
          tierBirth: tierBirth,
          twig: twig,
          d: cd,
          appear: appear,
          baseLen: baseLen,
          baseWidth: parent.baseWidth * widthRatio,
          x0: parent.x1,
          y0: parent.y1,
          angle: raw + (90 - raw) * droop,
        );
        place(child, ramp(e, appear), sp.childWidthRatio, false);
        queue.add(child);
      }

      // The main stem carries seed leaves and whorls instead of a tuft. A
      // leader (the conical spine, a twin's root) carries a tuft only while it
      // is the top; every other node keeps inner foliage after it forks.
      if (parent.path != 'T' && (!parent.leader || firstChild > k)) tipLeaves(parent, firstChild, !parent.leader);
    }
  }

  /// Seed leaves and seedling whorls along the main stem (plan §4.4).
  void growSeedling(_Node trunk) {
    if (k < table.cotyledonDeath && table.cotyledons > 0) {
      final at = along(trunk, trunkBaseLen(1, trunk.d[_len]) / math.max(1e-6, trunk.len));
      final n = table.cotyledons;
      final shrink = fadeAt(e, table.cotyledonDeath, seedling.cotyledonFadeSteps, seedling.cotyledonFadeMin);
      for (var i = 0; i < n; i += 1) {
        final path = 'C$i';
        final ld = nodeDraws(seed, path, kLeafDraws);
        final off = n == 2
            ? (i == 0 ? -seedling.cotyledonAngle : seedling.cotyledonAngle)
            : -seedling.cotyledonFan + (2 * seedling.cotyledonFan * i) / (n - 1);
        final a = at.heading + off;
        pushLeaf(
          x: at.x + math.cos(a * _deg) * seedling.cotyledonDistance,
          y: at.y + math.sin(a * _deg) * seedling.cotyledonDistance,
          angle: a,
          size: seedling.cotyledonSize * sp.leafSizeMul * shrink,
          phase: ld[3],
          hardiness: ld[4],
          depth: 0,
          path: path,
          birth: 1,
          kind: LeafKind.cotyledon,
          fade: fadeShare(shrink, seedling.cotyledonFadeMin),
        );
      }
    }
    // Whorl j sits where the stem's top was at its birth and stays there as
    // the stem grows past it; the lowest whorl falls first, shrinking before it goes.
    for (var j = 1; j <= table.seedlingPairs && j + 1 <= k; j += 1) {
      final born = j + 1;
      final death = pairDeath(form, j);
      if (k >= death) continue;
      final at = along(
        trunk,
        (seedling.pairHeight * trunkBaseLen(born.toDouble(), trunk.d[_len])) / math.max(1e-6, trunk.len),
      );
      final shrink = fadeAt(e, death, seedling.pairFadeSteps, seedling.pairFadeMin);
      final grow = ramp(e, born) * shrink;
      final fade = fadeShare(shrink, seedling.pairFadeMin);
      final n = table.pairLeaves;
      for (var side = 0; side < n; side += 1) {
        final path = 'S${j}L$side';
        final ld = nodeDraws(seed, path, kLeafDraws);
        final fan = n < 2 ? 0.0 : (2 * side) / (n - 1) - 1;
        final a = at.heading + fan * seedling.pairAngle + (ld[0] * 2 - 1) * seedling.pairAngleJitter;
        pushLeaf(
          x: at.x + math.cos(a * _deg) * seedling.pairDistance * grow,
          y: at.y + math.sin(a * _deg) * seedling.pairDistance * grow,
          angle: a,
          size: (seedling.pairSize + ld[2] * seedling.pairSizeJitter) * sp.leafSizeMul * grow,
          phase: ld[3],
          hardiness: ld[4],
          depth: 0,
          path: path,
          birth: born,
          kind: LeafKind.seedling,
          fade: fade,
        );
      }
    }
  }

  /// A palm: a chain of trunk segments and a crown of fronds. Real palms
  /// establish crown first, trunk later - the first segment is a stub until
  /// `palmEmergeSteps`, the others appear from step 7.
  void growPalm(String prefix, double x0, double angle0, double lenShare, double widthShare, int firstStep) {
    final segBirths = table.palmSegments;
    final main = prefix == 'T';
    _Node? parent;
    for (var i = 0; i < segBirths.length; i += 1) {
      if (branches.length >= kMaxBranches) break;
      final appear = main ? segBirths[i] : firstStep + i;
      if (appear > k) break;
      final path = prefix + '2' * i;
      final d = i == 0 && main ? tD : draws(path);
      final grow = i == 0 && main
          ? seedling.palmEmergeMin + (1 - seedling.palmEmergeMin) * _clamp((e - 1) / seedling.palmEmergeSteps, 0, 1)
          : ramp(e, appear);
      var widthShare9 = widthShare;
      for (var j = 0; j < i; j += 1) {
        widthShare9 *= 0.9;
      }
      final node = _Node(
        path: path,
        depth: (main ? 0 : 1) + i,
        rel: i,
        twin: !main,
        leader: true,
        tier: -1,
        tierBirth: 0,
        twig: false,
        d: d,
        appear: appear,
        baseLen: (trunkBaseLen(e, tD[_len]) / segBirths.length) * lenShare,
        baseWidth: trunkBaseWidth() * widthShare9,
        x0: parent != null ? parent.x1 : x0,
        y0: parent != null ? parent.y1 : kGroundY,
        angle: parent != null ? parent.endAngle : angle0,
      );
      // Bends onward in the direction of its own lean, segment after segment.
      final curve = (d[_curve] * 2 - 1) * sp.curveAmp + (angle0 + 90) * 0.35;
      place(node, grow, 0.9, main, curve);
      parent = node;
    }
    if (parent == null) return;
    final top = parent;
    int frondsAt(int step) => main ? palmFronds(step) : math.max(2, (palmFronds(step) * 0.6).round());
    final count = frondsAt(k);
    for (var i = 0; i < count; i += 1) {
      var born = main ? 1 : firstStep;
      while (born < k && frondsAt(born) <= i) {
        born += 1;
      }
      final path = '${main ? 'PF' : 'WF'}$i';
      final ld = nodeDraws(seed, path, kLeafDraws);
      final t = palmFrondFan[i % palmFrondFan.length];
      var a = angle0 + t * 95 + (ld[0] * 2 - 1) * 8;
      // Wilt lets the fronds hang.
      a += (90 - a) * droopT * 0.6;
      final frondSize =
          (2.2 + 2.6 * size) * (0.85 + ld[2] * 0.3) * sp.leafSizeMul * ramp(e, born) * math.sqrt(lenShare);
      pushLeaf(
        x: top.x1 + math.cos(a * _deg) * frondSize * 0.3,
        y: top.y1 + math.sin(a * _deg) * frondSize * 0.3,
        angle: a,
        size: frondSize,
        phase: ld[3],
        hardiness: ld[4],
        depth: top.depth,
        path: path,
        birth: born,
        kind: LeafKind.frond,
      );
    }
  }

  // --- The main tree -------------------------------------------------------

  final angle0 = -90 + lean;
  if (form == TreeForm.palm) {
    growPalm('T', kTrunkX, angle0, 1, 1, 1);
  } else {
    final trunk = _Node(
      path: 'T',
      depth: 0,
      rel: 0,
      twin: false,
      leader: true,
      tier: -1,
      tierBirth: 0,
      twig: false,
      d: tD,
      appear: 1,
      baseLen: trunkBaseLen(e, tD[_len]),
      baseWidth: trunkBaseWidth(),
      x0: kTrunkX,
      y0: kGroundY,
      angle: angle0,
    );
    growBranching(trunk, null);
    growSeedling(trunk);
  }
  final mainCount = nodes.length;

  // --- The twin trunk (trait `twin`): sprouts at its level and grows in ----

  if (hasTrait(lvl, TreeTrait.twin)) {
    final twinStep = stepOfLevel(kTraitLevels[TreeTrait.twin]!);
    final wD = draws('W');
    final side = wD[_birth] < 0.5 ? -1 : 1;
    final x0 = kTrunkX + side * geometry.twinOffset;
    final angle = -90 + lean + side * geometry.twinAngle;
    if (form == TreeForm.palm) {
      growPalm('W', x0, angle, geometry.twinLen, geometry.twinWidth, twinStep);
    } else {
      growBranching(
        _Node(
          path: 'W',
          depth: 1,
          rel: 0,
          twin: true,
          leader: true,
          tier: -1,
          tierBirth: 0,
          twig: false,
          d: wD,
          appear: twinStep,
          baseLen: trunkBaseLen(e, tD[_len]) * geometry.twinLen,
          baseWidth: trunkBaseWidth() * geometry.twinWidth,
          x0: x0,
          y0: kGroundY,
          angle: angle,
        ),
        twinStep,
      );
    }
  }

  // --- Open, visible ---------------------------------------------------------

  // Wilt sheds a scatter rather than a block, and the same leaves return on
  // recovery because `hardiness` is seeded. Older leaves open first. The
  // order is total (paths are unique), so an unstable sort gives the same ranks.
  final visibleCut = 0.55 + 0.45 * h;
  final order = List<int>.generate(leaves.length, (i) => i);
  order.sort((a, b) {
    final la = leaves[a];
    final lb = leaves[b];
    if (la.birth != lb.birth) return la.birth - lb.birth;
    return _comparePaths(la.path, lb.path);
  });
  final openCut = (leaves.length * (0.5 + 0.5 * f)).ceil();
  for (var rank = 0; rank < order.length; rank += 1) {
    final leaf = leaves[order[rank]];
    leaf.bloomOrder = rank;
    leaf.open = rank < openCut;
    leaf.visible = leaf.hardiness <= visibleCut;
  }

  final visible = leaves.where((leaf) => leaf.visible).toList();

  // --- Blossom: anchored to leaves by a ranking whose prefix never changes ---

  final blossoms = <Ornament>[];
  final blossoming =
      sp.blossom == BlossomMode.always || (sp.blossom == BlossomMode.seasonal && hasTrait(lvl, TreeTrait.blossom));
  if (blossoming) {
    // On the outer canopy only (never on a forked node's inner keep); a
    // species that always blooms flowers on its seedling whorls too.
    final candidates = visible
        .where(
          (leaf) => leaf.kind == LeafKind.leaf
              ? !innerLeaves.contains(leaf.path)
              : leaf.kind == LeafKind.seedling && sp.blossom == BlossomMode.always,
        )
        .map((leaf) => _Candidate(leaf, fnv1a32('$seed|B|${leaf.path}')))
        .toList()
      ..sort((a, b) {
        if (a.leaf.birth != b.leaf.birth) return a.leaf.birth - b.leaf.birth;
        if (a.h != b.h) return a.h - b.h;
        return _comparePaths(a.leaf.path, b.leaf.path);
      });
    final cap = math.min((6 + 10 * sizeAtStep(form, k)).round(), (candidates.length / 6).ceil());
    for (var i = 0; i < cap && i < candidates.length; i += 1) {
      final leaf = candidates[i].leaf;
      blossoms.add(
        Ornament(
          x: leaf.x,
          y: leaf.y,
          size: math.min(leaf.size, geometry.blossomMaxSize),
          index: i,
          path: leaf.path,
        ),
      );
    }
  }

  // --- Fruit: fruit i is hung, once, on a twig chosen at the step it arrived --

  final fruits = <Ornament>[];
  final wanted = fruitCount(lvl);
  if (wanted > 0) {
    if (form == TreeForm.palm) {
      final trunk = nodes.where((n) => !n.twin).toList();
      final top = trunk.isNotEmpty ? trunk.last : null;
      if (top != null) {
        for (var i = 0; i < wanted; i += 1) {
          final dx = (i % 2 == 0 ? 1 : -1) * (0.6 + 0.5 * (i ~/ 2));
          final dy = 1.6 + 0.4 * (i % 3);
          // Dates hang under whatever is the crown now; the path names the
          // bunch, not the segment. Small: a renderer draws each as a cluster.
          fruits.add(Ornament(x: top.x1 + dx, y: top.y1 + dy, size: geometry.dateSize, index: i, path: 'PD$i'));
        }
      }
    } else {
      final main = nodes.sublist(0, mainCount);
      final used = <String>{};
      for (var i = 0; i < wanted; i += 1) {
        final atStep = stepOfLevel(fruitLevel(i));
        var deepest = 0;
        for (final n in main) {
          if (n.appear <= atStep && n.depth > deepest) deepest = n.depth;
        }
        _Node? pick;
        var pickHash = 0;
        for (final n in main) {
          if (n.appear > atStep || n.depth < math.max(1, deepest - 1) || used.contains(n.path)) continue;
          final hash = fnv1a32('$seed|F|${n.path}');
          if (pick == null || hash < pickHash || (hash == pickHash && _comparePaths(n.path, pick.path) < 0)) {
            pick = n;
            pickHash = hash;
          }
        }
        if (pick == null) continue;
        used.add(pick.path);
        final hang = (60 + (pickHash % 60)) * _deg;
        final fruitSize = math.min((1 + ((pickHash >> 8) % 100) / 200) * sp.leafSizeMul, kMaxFruitSize);
        fruits.add(
          Ornament(
            x: pick.x1 + math.cos(hang) * 0.9,
            y: pick.y1 + math.sin(hang) * 0.9,
            size: fruitSize,
            index: i,
            path: pick.path,
          ),
        );
      }
    }
  }

  // --- Perch: a fixed chain of paths, never "the leaf nearest a point" ------

  ({double x, double y})? perch;
  if (form == TreeForm.palm) {
    final segments = nodes.where((n) => !n.twin).toList();
    if (segments.length >= 3) {
      final top = segments.last;
      perch = (x: top.x1 + 1.2, y: top.y1 + 0.6);
    }
  } else {
    var path = 'T1';
    _Node? best;
    for (var node = byPath[path]; node != null; node = byPath[path]) {
      if (node.depth >= 2 && e - node.appear >= 1) best = node;
      path += '1';
    }
    if (best != null) perch = (x: best.x1, y: best.y1);
  }

  // --- Bounds ----------------------------------------------------------------

  // Padded by a leaf's worth so the outermost canopy is never clipped; a frond
  // is drawn well past its anchor, so it pads by its own length. Wilted leaves
  // count too: the camera frames by these bounds, and health must not move it.
  var minX = kTrunkX, maxX = kTrunkX, minY = kGroundY;
  for (final branch in branches) {
    minX = math.min(minX, math.min(branch.x0, branch.x1));
    maxX = math.max(maxX, math.max(branch.x0, branch.x1));
    minY = math.min(minY, math.min(branch.y0, branch.y1));
  }
  for (final leaf in leaves) {
    final pad = sp.leafShape == LeafShape.frond ? leaf.size * 2.8 : 3 * math.min(1.0, leaf.size / sp.leafSizeMul);
    minX = math.min(minX, leaf.x - pad);
    maxX = math.max(maxX, leaf.x + pad);
    minY = math.min(minY, leaf.y - pad);
  }

  var maxDepth = 0;
  for (final branch in branches) {
    if (branch.depth > maxDepth) maxDepth = branch.depth;
  }

  return TreeScene(
    model: growthModel,
    branches: branches,
    leaves: leaves,
    blossoms: blossoms,
    fruits: fruits,
    perch: perch,
    bounds: TreeBounds(minX, maxX, minY, kGroundY + kGroundPad),
    traits: traitsForLevel(lvl),
    growth: size,
    maxDepth: maxDepth,
    level: lvl,
    frac: f,
    health: h,
    species: species,
    form: form,
    position: e,
    step: k,
    phase: phaseForStep(k).stage,
    rings: ringsForStep(k),
    floor: fl,
  );
}
