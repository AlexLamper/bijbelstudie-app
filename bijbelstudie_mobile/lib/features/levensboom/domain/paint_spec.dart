/// Growth v2 render-only primitives both renderers share (plan §4.4 "new
/// drawing primitives", §4.5 maturing): the seed leaf's shape and colour, and
/// the bark knots, moss and root flare of an old tree. The pure half of the
/// website's `lib/levensboom/paint.ts` - its numbers and functions, 1:1; the
/// painter that draws them is `present/`'s business.
///
/// Paint, not topology: nothing here feeds back into the generator, and
/// season, time and health only reach it through the palette. Colours are
/// mixes of existing palette tokens only ([mixColor], the web's `mix`). All
/// geometry is in tree units, on the scene's own branch geometry, so a
/// renderer applies its camera exactly as it does to the branches.
///
/// Contract: `docs/levensboom-spec.md` §10.6 in the website repo.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'growth.dart';
import 'palette.dart';
import 'rng.dart';
import 'species.dart';
import 'tree_generator.dart';

// ---------------------------------------------------------------------------
// Seed leaves (kind cotyledon)
// ---------------------------------------------------------------------------

/// A seed leaf is drawn in its own rotated frame (+x along `leaf.angle`), with
/// `s` = the leaf's pixel size exactly as a species leaf gets it:
///
///     broad-leaved   ellipse centre (0.55·s, 0), radii (0.62·s, 0.46·s)  - rounder and fleshier than any species leaf
///     conical form   ellipse centre (0.75·s, 0), radii (0.85·s, 0.16·s)  - a conifer's seed leaves are needles
///
/// Colour ([cotyledonColor]):
///
///     base  = mix(leaf or leafAlt (leaf.phase > 0.5), light, 0.14)          - slightly lighter than the canopy
///     faded = mix(mix(base, barkLit, 0.4), glow, 0.3)                        - a pale, yellowing olive
///     age   = step >= 3 ? clamp(0.3 + 0.25·(position − 3), 0, 0.8) : 0
///     fill  = mix(base, faded, age)
///
/// The website's `COTYLEDON`.
class CotyledonPaint {
  const CotyledonPaint._();

  final double cx = 0.55;
  final double rx = 0.62;
  final double ry = 0.46;
  final double needleCx = 0.75;
  final double needleRx = 0.85;
  final double needleRy = 0.16;
  final double lighten = 0.14;
  final double fadeBark = 0.4;
  final double fadeGlow = 0.3;
  final int yellowFromStep = 3;
  final double yellowStart = 0.3;
  final double yellowPerStep = 0.25;
  final double yellowMax = 0.8;
}

const CotyledonPaint cotyledonPaint = CotyledonPaint._();

({double cx, double rx, double ry}) cotyledonShape(TreeForm form, double size) {
  const c = cotyledonPaint;
  if (form == TreeForm.conical) return (cx: c.needleCx * size, rx: c.needleRx * size, ry: c.needleRy * size);
  return (cx: c.cx * size, rx: c.rx * size, ry: c.ry * size);
}

/// [step] defaults to floor([position]), as on the website.
Color cotyledonColor(TreePalette palette, bool alt, {int? step, required double position}) {
  const c = cotyledonPaint;
  final base = mixColor(alt ? palette.leafAlt : palette.leaf, palette.light, c.lighten);
  final s = step ?? (position.isFinite ? position.floor() : 0);
  if (s < c.yellowFromStep) return base;
  final age = math.min(c.yellowMax, math.max(0.0, c.yellowStart + c.yellowPerStep * (position - c.yellowFromStep)));
  final faded = mixColor(mixColor(base, palette.barkLit, c.fadeBark), palette.glow, c.fadeGlow);
  return mixColor(base, faded, age);
}

/// A temporary leaf (seed leaf, seedling whorl) fades as it shrinks: opacity
/// `alphaMin + (1 − alphaMin) · leaf.fade`, times the bud opacity. The
/// website's `LEAF_FADE`.
class LeafFadePaint {
  const LeafFadePaint._();

  final double alphaMin = 0.3;
}

const LeafFadePaint leafFade = LeafFadePaint._();

double leafFadeAlpha(double? fade) {
  final f = fade == null ? 1.0 : math.min(1.0, math.max(0.0, fade));
  return leafFade.alphaMin + (1 - leafFade.alphaMin) * f;
}

// ---------------------------------------------------------------------------
// Ground mound and shadow under the trunk
// ---------------------------------------------------------------------------

/// The low mound the trunk stands in, sized to the trunk (growth v2: a kiem
/// stands on a handful of earth, an old tree on a swell of it). With w the
/// trunk's base width in tree units (branch 'T', `w0`; 5 for a scene without
/// one, i.e. a v1 tree):
///
///     scene     mound rx = clamp(3 + 2.2·w, 4, 17), ry = 0.16·rx, centred 0.2 below the earth band's top edge;
///               shadow rx = 0.78·mound rx, ry = 0.115·mound rx, centred 0.6 below the trunk base, bark at 0.2-0.28 alpha
///     portrait  disc rx = max(2.4, 1.9 + 1.1·w), ry = min(0.16·rx, 1.6) tree units on the pivot; shadow 0.7·rx, 0.7·ry, 0.4 lower
///
/// All in tree units times the camera scale, never below 3 px (mound) / 2 px
/// (shadow) so an avatar keeps a foothold. The website's `MOUND`.
class MoundPaint {
  const MoundPaint._();

  final double base = 3;
  final double perWidth = 2.2;
  final double min = 4;
  final double max = 17;
  final double aspect = 0.16;
  final double shadowRx = 0.78;
  final double shadowAspect = 0.115;
  final double portraitBase = 1.9;
  final double portraitPerWidth = 1.1;
  final double portraitMin = 2.4;
  final double portraitMaxRy = 1.6;
  final double defaultWidth = 5;
}

const MoundPaint mound = MoundPaint._();

double trunkWidthOf(TreeScene scene) {
  for (final b in scene.branches) {
    if (b.path == 'T') return b.w0 > 0 ? b.w0 : mound.defaultWidth;
  }
  return mound.defaultWidth;
}

/// Scene mound and shadow radii in tree units.
({double rx, double ry, double shadowRx, double shadowRy}) moundFor(double trunkWidth) {
  final rx = math.min(mound.max, math.max(mound.min, mound.base + mound.perWidth * trunkWidth));
  return (rx: rx, ry: rx * mound.aspect, shadowRx: rx * mound.shadowRx, shadowRy: rx * mound.shadowAspect);
}

/// Portrait disc radii in tree units.
({double rx, double ry}) portraitDiscFor(double trunkWidth) {
  final rx = math.max(mound.portraitMin, mound.portraitBase + mound.portraitPerWidth * trunkWidth);
  return (rx: rx, ry: math.min(rx * mound.aspect, mound.portraitMaxRy));
}

// ---------------------------------------------------------------------------
// Maturing: knots, moss, root flare (by position, plan §4.5)
// ---------------------------------------------------------------------------

/// One seeded stream, `"<seed>:mature"`, always drawn in full and in this order
/// whatever the position, so a detail that appears later never moves one that
/// is already there:
///
///     knots  6 × (along, s, size)       mossTufts  7 × (along, s, size)       roots  2 × (spread), left then right
///
/// where `s` gives both the side (s < 0.5 ? −1 : +1) and how far out (|2·s − 1|).
///
/// The trunk is the branch with path 'T' (a palm's first segment). With u a
/// share of its length, P(u) the point on its quadratic curve, n(u) the unit
/// normal (−dy, dx)/|d| of the curve's direction d (so +n is the trunk's right
/// edge for a trunk growing up), and hw(u) = (w0 + (w1 − w0)·u) / 2 its half
/// width:
///
/// KNOTS - from position 22, not on a palm. count = min(6, 1 + floor((position − 22) / 3)).
///   knot i: u = 0.18 + 0.6·along;  side = s < 0.5 ? −1 : +1;  lateral = 0.2 + 0.3·|2·s − 1|
///   centre = P(u) + n(u)·side·lateral·hw(u);  rx = hw(u)·(0.28 + 0.14·size);  ry = 0.62·rx
///   rotated to the trunk's heading at u. Painted as a rim ellipse (1.3·rx, 1.4·ry) in barkLit at
///   opacity 0.55, then the knot in mix(bark, groundDeep, 0.5) at opacity 0.9.
///
/// MOSS - from position 26, not on a palm. count = min(7, 3 + floor((position − 26) / 2)).
///   tuft j: u = 0.02 + 0.1·along;  side as above;  lateral = 0.55 + 0.4·|2·s − 1|
///   centre = P(u) + n(u)·side·lateral·hw(u);  r = w0·(0.11 + 0.08·size)·min(1, 0.6 + 0.4·(position − 26) / 6)
///   fill mix(size < 0.5 ? leaf : leafAlt, groundDeep, 0.45) at opacity 0.85.
///
/// ROOT FLARE - from position 30, every form. amount = 0.35 + 0.65·min(1, (position − 30) / 6).
///   base (x0, y0) = the trunk's start;  hw0 = hw(0);  rise = hw0·(1.2 + 0.8·amount)
///   u = min(0.25, rise / trunk length);  top = P(u) + n(u)·side·hw(u)   (side −1 left, +1 right)
///   toe  = (x0 + side·(hw0 + hw0·(0.6 + 0.8·amount)·(0.8 + 0.4·spread)), GROUND_Y + 0.3)
///   ctrl = (x0 + side·1.08·hw0, GROUND_Y − 0.15·rise)
///   outline: M top · Q ctrl toe · L (toe.x, GROUND_Y + 0.9) · L (x0, GROUND_Y + 0.9) · L (x0, top.y) · Z
///   drawn behind the trunk; on the canvas (lit trunk) the left foot in mix(barkLit, bark, 0.5) and the
///   right in bark.
///
/// The website's `MATURE_PAINT`.
class MaturePaint {
  const MaturePaint._();

  final int knotMax = 6;
  final double knotEvery = 3;
  final List<double> knotAlong = const [0.18, 0.6];
  final List<double> knotLateral = const [0.2, 0.3];
  final List<double> knotSize = const [0.28, 0.14];
  final double knotAspect = 0.62;
  final int mossMax = 7;
  final int mossFirst = 3;
  final double mossEvery = 2;
  final List<double> mossAlong = const [0.02, 0.1];
  final List<double> mossLateral = const [0.55, 0.4];
  final List<double> mossSize = const [0.11, 0.08];
  final double mossGrowSteps = 6;
  final double flareMin = 0.35;
  final double flareSteps = 6;
  final List<double> flareRise = const [1.2, 0.8];
  final List<double> flareReach = const [0.6, 0.8];
  final List<double> flareSpread = const [0.8, 0.4];
  final double flareMaxAlong = 0.25;
}

const MaturePaint maturePaint = MaturePaint._();

class Knot {
  const Knot({required this.x, required this.y, required this.rx, required this.ry, required this.angle});

  final double x, y, rx, ry;

  /// Degrees.
  final double angle;
}

class MossTuft {
  const MossTuft({required this.x, required this.y, required this.r, required this.alt});

  final double x, y, r;
  final bool alt;
}

class RootFoot {
  const RootFoot({
    required this.side,
    required this.top,
    required this.ctrl,
    required this.toe,
    required this.baseX,
    required this.bottomY,
  });

  /// -1 left, +1 right.
  final int side;
  final ({double x, double y}) top;
  final ({double x, double y}) ctrl;
  final ({double x, double y}) toe;
  final double baseX;

  /// Bottom edge of the foot, just under the ground line.
  final double bottomY;
}

class MatureDetails {
  const MatureDetails({required this.knots, required this.moss, required this.roots});

  static const MatureDetails empty = MatureDetails(knots: [], moss: [], roots: []);

  final List<Knot> knots;
  final List<MossTuft> moss;
  final List<RootFoot> roots;
}

/// V8's `Math.hypot` for two arguments (scaled, Kahan-summed), so the Dart
/// numbers match the website's to the bit; `sqrt(dx² + dy²)` can differ in the
/// last ulp.
double _hypot(double a, double b) {
  if (a.isInfinite || b.isInfinite) return double.infinity;
  if (a.isNaN || b.isNaN) return double.nan;
  final values = [a.abs(), b.abs()];
  var max = 0.0;
  for (final v in values) {
    if (v > max) max = v;
  }
  if (max == 0) return 0;
  var sum = 0.0;
  var compensation = 0.0;
  for (final v in values) {
    final n = v / max;
    final summand = n * n - compensation;
    final preliminary = sum + summand;
    compensation = (preliminary - sum) - summand;
    sum = preliminary;
  }
  return math.sqrt(sum) * max;
}

({double x, double y, double nx, double ny, double heading, double hw}) _trunkAt(Branch trunk, double u) {
  final v = 1 - u;
  final x = v * v * trunk.x0 + 2 * v * u * trunk.cx + u * u * trunk.x1;
  final y = v * v * trunk.y0 + 2 * v * u * trunk.cy + u * u * trunk.y1;
  final dx = 2 * v * (trunk.cx - trunk.x0) + 2 * u * (trunk.x1 - trunk.cx);
  final dy = 2 * v * (trunk.cy - trunk.y0) + 2 * u * (trunk.y1 - trunk.cy);
  final h = _hypot(dx, dy);
  final length = h == 0 || h.isNaN ? 1.0 : h;
  return (
    x: x,
    y: y,
    nx: -dy / length,
    ny: dx / length,
    heading: (math.atan2(dy, dx) * 180) / math.pi,
    hw: (trunk.w0 + (trunk.w1 - trunk.w0) * u) / 2,
  );
}

/// The maturing details for a scene, in tree units. Empty below step 22.
MatureDetails matureDetails(TreeScene scene, String seed) {
  final position = scene.position;
  if (!(position >= mature.knotsFrom)) return MatureDetails.empty;
  Branch? trunk;
  for (final b in scene.branches) {
    if (b.path == 'T') {
      trunk = b;
      break;
    }
  }
  if (trunk == null) return MatureDetails.empty;

  final rand = seededRng('$seed:mature');
  const p = maturePaint;
  List<List<double>> draws(int n) => [
    for (var i = 0; i < n; i += 1) [rand(), rand(), rand()],
  ];
  final knotDraws = draws(p.knotMax);
  final mossDraws = draws(p.mossMax);
  final rootDraws = [rand(), rand()];
  final palm = scene.form == TreeForm.palm;

  final knots = <Knot>[];
  if (!palm) {
    final count = math.min(p.knotMax, 1 + ((position - mature.knotsFrom) / p.knotEvery).floor());
    for (var i = 0; i < count; i += 1) {
      final along = knotDraws[i][0];
      final sideU = knotDraws[i][1];
      final size = knotDraws[i][2];
      final at = _trunkAt(trunk, p.knotAlong[0] + p.knotAlong[1] * along);
      final side = sideU < 0.5 ? -1 : 1;
      final lateral = p.knotLateral[0] + p.knotLateral[1] * (2 * sideU - 1).abs();
      final rx = at.hw * (p.knotSize[0] + p.knotSize[1] * size);
      knots.add(
        Knot(
          x: at.x + at.nx * side * lateral * at.hw,
          y: at.y + at.ny * side * lateral * at.hw,
          rx: rx,
          ry: rx * p.knotAspect,
          angle: at.heading,
        ),
      );
    }
  }

  final moss = <MossTuft>[];
  if (!palm && position >= mature.mossFrom) {
    final count = math.min(p.mossMax, p.mossFirst + ((position - mature.mossFrom) / p.mossEvery).floor());
    final grow = math.min(1.0, 0.6 + (0.4 * (position - mature.mossFrom)) / p.mossGrowSteps);
    for (var j = 0; j < count; j += 1) {
      final along = mossDraws[j][0];
      final sideU = mossDraws[j][1];
      final size = mossDraws[j][2];
      final at = _trunkAt(trunk, p.mossAlong[0] + p.mossAlong[1] * along);
      final side = sideU < 0.5 ? -1 : 1;
      final lateral = p.mossLateral[0] + p.mossLateral[1] * (2 * sideU - 1).abs();
      moss.add(
        MossTuft(
          x: at.x + at.nx * side * lateral * at.hw,
          y: at.y + at.ny * side * lateral * at.hw,
          r: trunk.w0 * (p.mossSize[0] + p.mossSize[1] * size) * grow,
          alt: size >= 0.5,
        ),
      );
    }
  }

  final roots = <RootFoot>[];
  if (position >= mature.flareFrom) {
    final amount = p.flareMin + (1 - p.flareMin) * math.min(1.0, (position - mature.flareFrom) / p.flareSteps);
    final length = math.max(1e-6, _hypot(trunk.x1 - trunk.x0, trunk.y1 - trunk.y0));
    final hw0 = trunk.w0 / 2;
    final rise = hw0 * (p.flareRise[0] + p.flareRise[1] * amount);
    final at = _trunkAt(trunk, math.min(p.flareMaxAlong, rise / length));
    const sides = [-1, 1];
    for (var i = 0; i < sides.length; i += 1) {
      final side = sides[i];
      final reach =
          hw0 + hw0 * (p.flareReach[0] + p.flareReach[1] * amount) * (p.flareSpread[0] + p.flareSpread[1] * rootDraws[i]);
      roots.add(
        RootFoot(
          side: side,
          top: (x: at.x + at.nx * side * at.hw, y: at.y + at.ny * side * at.hw),
          ctrl: (x: trunk.x0 + side * 1.08 * hw0, y: kGroundY - 0.15 * rise),
          toe: (x: trunk.x0 + side * reach, y: kGroundY + 0.3),
          baseX: trunk.x0,
          bottomY: kGroundY + 0.9,
        ),
      );
    }
  }

  return MatureDetails(knots: knots, moss: moss, roots: roots);
}

/// Knot colours: the dark knot and its lit rim.
({Color knot, Color rim}) knotColors(TreePalette palette) {
  return (knot: mixColor(palette.bark, palette.groundDeep, 0.5), rim: palette.barkLit);
}

Color mossColor(TreePalette palette, bool alt) {
  return mixColor(alt ? palette.leafAlt : palette.leaf, palette.groundDeep, 0.45);
}

Color rootColor(TreePalette palette, int side) {
  return side < 0 ? mixColor(palette.barkLit, palette.bark, 0.5) : palette.bark;
}
