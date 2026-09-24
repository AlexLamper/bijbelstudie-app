/// Growth v2: one tree between two positions (plan §9.2, §9.3). Mirror of the
/// website's `lib/levensboom/tween.ts`, line for line.
///
/// The level-up and the in-level lesson growth both hold scene A (before) and
/// scene B (after) of the same seed and species, and render
/// `lerpScenes(a, b, tweenEase(u))` for u running 0 → 1 over the tween. Since
/// v2 a node keeps its path, angle and anchor for life, "the same branch in both
/// scenes" is a path lookup, and the in-between is plain interpolation:
///
/// - Wood in both scenes (by `path`): every coordinate and width lerps.
/// - Newborn wood (only in B): grows out of its parent's *lerped* tip. The start
///   point is the parent's lerped end (parent = path minus its last character;
///   the roots `T` and `W` anchor at their own start), and its vector (control
///   and end relative to the start) and widths scale by [sprout].
/// - Leaves in both: lerp x, y, size and angle, carried by their owner node's
///   lerped tip (owner = the path before the last `L`; a palm frond's owner is
///   the top segment of its chain). New leaves ride on the owner's lerped tip
///   and scale in with [unfurl]. Leaves only in A (seed leaves, leaf whorls,
///   inner foliage falling) shrink out with [fall]. Seed leaves and leaf
///   whorls have no owner node and lerp in place.
/// - Blossoms (by path) sit on their leaf's lerped position; fruit (by path and
///   index) rides its twig's lerped tip; both follow the same in / out rules.
/// - Bounds, position, growth and health lerp, so a renderer that measures its
///   camera on the lerped scene gets the camera ease for free. Topology fields
///   (`step`, `phase`, `rings`, `traits`, `maxDepth`) and everything else come
///   from B.
///
/// At t = 1 the result is B itself; at t = 0 every shared path has A's geometry
/// and newborn wood is a zero-length bud at its parent's tip.
///
/// Pure: no Canvas, no clock, no random. The website memoises the per-scene
/// path index in a WeakMap; here an [Expando] does the same.
library;

import 'dart:math' as math;

import 'tree_generator.dart';

/// Timing shape of a tween (the website's `TWEEN`). Design numbers (CP6).
class TweenTiming {
  const TweenTiming._();

  /// Newborn wood waits this share of the (eased) tween, then grows out of its parent's tip.
  final double sproutDelay = 0.12;

  /// New leaves, blossom and fruit unfurl after the wood, from this share on.
  final double unfurlDelay = 0.4;

  /// Leaves and ornaments that leave (seed leaves, inner foliage) are gone by this share.
  final double fallEnd = 0.55;

  /// Default length when the step changes (a level-up).
  final int levelUpMs = 1800;

  /// Default length for growth within a level (after a lesson or a chapter).
  final int growMs = 1200;

  /// [tweenEase] = smoothstep(u ^ easeBias): below 1 leans the motion earlier.
  final double easeBias = 0.75;
}

const TweenTiming tween = TweenTiming._();

double _clamp01(double x) => x <= 0 ? 0 : (x >= 1 ? 1 : x);

double _smoothstep(double x) {
  final u = _clamp01(x);
  return u * u * (3 - 2 * u);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Time to tween progress: a short wake-up, the growth through the middle, a
/// long settle - `smoothstep(u^0.75)`, so nothing jolts at either end and the
/// tree is still visibly growing past the halfway mark (0.30 at a quarter,
/// 0.65 at half, 0.90 at three quarters).
double tweenEase(double u) => _smoothstep(math.pow(_clamp01(u), tween.easeBias).toDouble());

/// How far newborn wood has grown at tween progress t.
double sprout(double t) => _smoothstep((t - tween.sproutDelay) / (1 - tween.sproutDelay));

/// How far a new leaf, blossom or fruit has opened at tween progress t.
double unfurl(double t) => _smoothstep((t - tween.unfurlDelay) / (1 - tween.unfurlDelay));

/// How much of a leaving leaf or ornament is left at tween progress t.
double fall(double t) => 1 - _smoothstep(t / tween.fallEnd);

/// The default tween length for a pair of scenes.
int tweenMsFor(TreeScene a, TreeScene b) => a.step != b.step ? tween.levelUpMs : tween.growMs;

// ---------------------------------------------------------------------------
// Path index
// ---------------------------------------------------------------------------

typedef _Point = ({double x, double y});

class _SceneIndex {
  _SceneIndex(this.branches, this.leaves, this.blossoms, this.fruits, this.tops);

  final Map<String, Branch> branches;
  final Map<String, Leaf> leaves;
  final Map<String, Ornament> blossoms;
  final Map<String, Ornament> fruits;

  /// Top segment of each palm chain ('T', 'W'), by path.
  final Map<String, String> tops;
}

final Expando<_SceneIndex> _indexes = Expando<_SceneIndex>('levensboom tween index');

String _fruitKey(Ornament o) => '${o.path}#${o.index}';

_SceneIndex _indexOf(TreeScene scene) {
  final hit = _indexes[scene];
  if (hit != null) return hit;
  final branches = <String, Branch>{};
  final tops = <String, String>{};
  for (final b in scene.branches) {
    branches[b.path] = b;
    // Branches come parents first, so the last one of each root is its top
    // segment; only a palm reads this.
    tops[b.path.substring(0, 1)] = b.path;
  }
  final leaves = <String, Leaf>{for (final l in scene.leaves) l.path: l};
  final blossoms = <String, Ornament>{for (final o in scene.blossoms) o.path: o};
  final fruits = <String, Ornament>{for (final o in scene.fruits) _fruitKey(o): o};
  final index = _SceneIndex(branches, leaves, blossoms, fruits, tops);
  _indexes[scene] = index;
  return index;
}

/// The branch whose tip a leaf rides, or null (seed leaves, leaf whorls).
String? _leafOwner(String path, LeafKind kind, _SceneIndex index) {
  if (kind == LeafKind.frond || path.startsWith('PF') || path.startsWith('WF')) {
    return index.tops[path.startsWith('W') ? 'W' : 'T'];
  }
  final at = path.lastIndexOf('L');
  if (at <= 0) return null;
  final owner = path.substring(0, at);
  return index.branches.containsKey(owner) ? owner : null;
}

/// The branch whose tip a fruit hangs from, or null. Palm dates hang under the crown.
String? _fruitOwner(String path, _SceneIndex index) {
  if (path.startsWith('PD')) return index.tops['T'];
  return index.branches.containsKey(path) ? path : null;
}

_Point? _tipOf(_SceneIndex index, String? path) {
  if (path == null) return null;
  final b = index.branches[path];
  return b == null ? null : (x: b.x1, y: b.y1);
}

String? _parentPath(String path) => path.length > 1 ? path.substring(0, path.length - 1) : null;

// ---------------------------------------------------------------------------
// The tween
// ---------------------------------------------------------------------------

/// Place something that rides a branch tip. [own] is where it sits in its own
/// scene and [ownTip] that scene's tip of its owner; [tip] is the owner's
/// lerped tip. With no owner it stays where it is.
_Point _ride(_Point own, _Point? ownTip, _Point? tip, double share) {
  if (ownTip == null || tip == null) return (x: own.x, y: own.y);
  return (x: tip.x + (own.x - ownTip.x) * share, y: tip.y + (own.y - ownTip.y) * share);
}

TreeScene lerpScenes(TreeScene a, TreeScene b, double t) {
  final p = t.isFinite ? _clamp01(t) : 0.0;
  if (p >= 1) return b;

  final ia = _indexOf(a);
  final ib = _indexOf(b);
  final grow = sprout(p);
  final open = unfurl(p);
  final leave = fall(p);

  // --- Wood ------------------------------------------------------------------

  /// Lerped tips by path: B's wood, then wood only A has (never, in practice).
  final tips = <String, _Point>{};
  final branches = <Branch>[];
  for (final nb in b.branches) {
    final oa = ia.branches[nb.path];
    Branch branch;
    if (oa != null) {
      branch = nb.copyWith(
        x0: _lerp(oa.x0, nb.x0, p),
        y0: _lerp(oa.y0, nb.y0, p),
        cx: _lerp(oa.cx, nb.cx, p),
        cy: _lerp(oa.cy, nb.cy, p),
        x1: _lerp(oa.x1, nb.x1, p),
        y1: _lerp(oa.y1, nb.y1, p),
        w0: _lerp(oa.w0, nb.w0, p),
        w1: _lerp(oa.w1, nb.w1, p),
        wood: _lerp(oa.wood, nb.wood, p),
      );
    } else {
      final parentPath = _parentPath(nb.path);
      final parent = parentPath == null ? null : tips[parentPath];
      final sx = parent != null ? parent.x : nb.x0;
      final sy = parent != null ? parent.y : nb.y0;
      branch = nb.copyWith(
        x0: sx,
        y0: sy,
        cx: sx + (nb.cx - nb.x0) * grow,
        cy: sy + (nb.cy - nb.y0) * grow,
        x1: sx + (nb.x1 - nb.x0) * grow,
        y1: sy + (nb.y1 - nb.y0) * grow,
        w0: nb.w0 * grow,
        w1: nb.w1 * grow,
      );
    }
    tips[nb.path] = (x: branch.x1, y: branch.y1);
    branches.add(branch);
  }
  // Wood only A has: v2 never removes wood, but a tween the other way (or
  // across a species change) must not leave it hanging in the air.
  if (leave > 0) {
    for (final oa in a.branches) {
      if (ib.branches.containsKey(oa.path)) continue;
      final parentPath = _parentPath(oa.path);
      final parent = parentPath == null ? null : tips[parentPath];
      final sx = parent != null ? parent.x : oa.x0;
      final sy = parent != null ? parent.y : oa.y0;
      final branch = oa.copyWith(
        x0: sx,
        y0: sy,
        cx: sx + (oa.cx - oa.x0) * leave,
        cy: sy + (oa.cy - oa.y0) * leave,
        x1: sx + (oa.x1 - oa.x0) * leave,
        y1: sy + (oa.y1 - oa.y0) * leave,
        w0: oa.w0 * leave,
        w1: oa.w1 * leave,
      );
      tips[oa.path] = (x: branch.x1, y: branch.y1);
      branches.add(branch);
    }
  }

  // --- Leaves ------------------------------------------------------------------

  final leaves = <Leaf>[];
  final leafAt = <String, Leaf>{};
  // Leaving leaves first, so they sit under the foliage that stays.
  if (leave > 0) {
    for (final la in a.leaves) {
      if (ib.leaves.containsKey(la.path)) continue;
      final owner = _leafOwner(la.path, la.kind, ia);
      final at = _ride((x: la.x, y: la.y), _tipOf(ia, owner), owner != null ? tips[owner] : null, 1);
      final leaf = la.copyWith(x: at.x, y: at.y, size: la.size * leave, fade: la.fade * leave);
      leaves.add(leaf);
      leafAt[la.path] = leaf;
    }
  }
  for (final lb in b.leaves) {
    final la = ia.leaves[lb.path];
    final ownerB = _leafOwner(lb.path, lb.kind, ib);
    final tip = ownerB != null ? tips[ownerB] : null;
    final tipB = _tipOf(ib, ownerB);
    Leaf leaf;
    if (la != null) {
      final tipA = _tipOf(ia, _leafOwner(la.path, la.kind, ia));
      double x;
      double y;
      if (tip != null && tipA != null && tipB != null) {
        x = tip.x + _lerp(la.x - tipA.x, lb.x - tipB.x, p);
        y = tip.y + _lerp(la.y - tipA.y, lb.y - tipB.y, p);
      } else {
        x = _lerp(la.x, lb.x, p);
        y = _lerp(la.y, lb.y, p);
      }
      leaf = lb.copyWith(
        x: x,
        y: y,
        size: _lerp(la.size, lb.size, p),
        angle: _lerp(la.angle, lb.angle, p),
        fade: _lerp(la.fade, lb.fade, p),
      );
    } else {
      final at = _ride((x: lb.x, y: lb.y), tipB, tip, open);
      leaf = lb.copyWith(x: at.x, y: at.y, size: lb.size * open);
    }
    leaves.add(leaf);
    leafAt[lb.path] = leaf;
  }

  // --- Blossom: on its leaf --------------------------------------------------

  final blossoms = <Ornament>[];
  Ornament blossomOn(Ornament o, double presence) {
    final leaf = leafAt[o.path];
    // Capped like the generator caps it (`blossomMaxSize`), so it never snaps at t = 1.
    if (leaf != null) return o.copyWith(x: leaf.x, y: leaf.y, size: math.min(leaf.size, o.size) * presence);
    return o.copyWith(size: o.size * presence);
  }

  if (leave > 0) {
    for (final oa in a.blossoms) {
      if (!ib.blossoms.containsKey(oa.path)) blossoms.add(blossomOn(oa, leave));
    }
  }
  for (final ob in b.blossoms) {
    blossoms.add(blossomOn(ob, ia.blossoms.containsKey(ob.path) ? 1 : open));
  }

  // --- Fruit: on its twig ----------------------------------------------------

  final fruits = <Ornament>[];
  if (leave > 0) {
    for (final oa in a.fruits) {
      if (ib.fruits.containsKey(_fruitKey(oa))) continue;
      final owner = _fruitOwner(oa.path, ia);
      final at = _ride((x: oa.x, y: oa.y), _tipOf(ia, owner), owner != null ? tips[owner] : null, 1);
      fruits.add(oa.copyWith(x: at.x, y: at.y, size: oa.size * leave));
    }
  }
  for (final ob in b.fruits) {
    final oa = ia.fruits[_fruitKey(ob)];
    final ownerB = _fruitOwner(ob.path, ib);
    final tip = ownerB != null ? tips[ownerB] : null;
    final tipB = _tipOf(ib, ownerB);
    if (oa != null) {
      final tipA = _tipOf(ia, _fruitOwner(oa.path, ia));
      double x;
      double y;
      if (tip != null && tipA != null && tipB != null) {
        x = tip.x + _lerp(oa.x - tipA.x, ob.x - tipB.x, p);
        y = tip.y + _lerp(oa.y - tipA.y, ob.y - tipB.y, p);
      } else {
        x = _lerp(oa.x, ob.x, p);
        y = _lerp(oa.y, ob.y, p);
      }
      fruits.add(ob.copyWith(x: x, y: y, size: _lerp(oa.size, ob.size, p)));
    } else {
      final at = _ride((x: ob.x, y: ob.y), tipB, tip, 1);
      fruits.add(ob.copyWith(x: at.x, y: at.y, size: ob.size * open));
    }
  }

  // --- Perch -----------------------------------------------------------------

  ({double x, double y})? perch;
  final pa = a.perch;
  final pb = b.perch;
  if (pa != null && pb != null) {
    perch = (x: _lerp(pa.x, pb.x, p), y: _lerp(pa.y, pb.y, p));
  } else if (pb != null && p >= 0.5) {
    // The bird moves up into the crown halfway, onto the twig as it is now.
    final path = _nearestPath(b, pb);
    perch = _ride(pb, path == null ? null : _tipOf(ib, path), path == null ? null : tips[path], 1);
  } else {
    perch = p < 0.5 ? pa : pb;
  }

  final bounds = TreeBounds(
    _lerp(a.bounds.minX, b.bounds.minX, p),
    _lerp(a.bounds.maxX, b.bounds.maxX, p),
    _lerp(a.bounds.minY, b.bounds.minY, p),
    _lerp(a.bounds.maxY, b.bounds.maxY, p),
  );

  return b.copyWith(
    branches: branches,
    leaves: leaves,
    blossoms: blossoms,
    fruits: fruits,
    perch: () => perch,
    bounds: bounds,
    growth: _lerp(a.growth, b.growth, p),
    health: _lerp(a.health, b.health, p),
    position: _lerp(a.position, b.position, p),
  );
}

/// The path of B's branch whose tip lies closest to a point (the perch sits on one).
String? _nearestPath(TreeScene scene, _Point at) {
  String? best;
  var bestD = double.infinity;
  for (final b in scene.branches) {
    final d = (b.x1 - at.x) * (b.x1 - at.x) + (b.y1 - at.y) * (b.y1 - at.y);
    if (d < bestD) {
      bestD = d;
      best = b.path;
    }
  }
  return best;
}
