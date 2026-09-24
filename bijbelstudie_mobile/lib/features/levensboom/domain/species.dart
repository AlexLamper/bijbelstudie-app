/// The thirteen boomsoorten, as generator parameters. Mirror of the website's
/// `lib/levensboom/species.ts`; the numbers are the table in
/// `docs/levensboom-spec.md` §4.4 and must stay identical, or the same seed
/// stops producing the same tree on the two platforms.
///
/// A species never adds a random draw of its own: every number here scales or
/// biases a draw the branching recursion already makes.
library;

import 'package:flutter/painting.dart';

/// Same ids, same order as the website's `SPECIES_IDS`.
enum TreeSpecies {
  eik,
  olijf,
  vijg,
  palm,
  amandel,
  ceder,
  mosterd,
  appel,
  granaatappel,
  sycomoor,
  wilg,
  acacia,
  cipres,
}

const TreeSpecies kDefaultSpecies = TreeSpecies.eik;

const Map<TreeSpecies, String> kSpeciesIds = {
  TreeSpecies.eik: 'eik',
  TreeSpecies.olijf: 'olijf',
  TreeSpecies.vijg: 'vijg',
  TreeSpecies.palm: 'palm',
  TreeSpecies.amandel: 'amandel',
  TreeSpecies.ceder: 'ceder',
  TreeSpecies.mosterd: 'mosterd',
  TreeSpecies.appel: 'appel',
  TreeSpecies.granaatappel: 'granaatappel',
  TreeSpecies.sycomoor: 'sycomoor',
  TreeSpecies.wilg: 'wilg',
  TreeSpecies.acacia: 'acacia',
  TreeSpecies.cipres: 'cipres',
};

TreeSpecies speciesFromId(String? id) {
  for (final entry in kSpeciesIds.entries) {
    if (entry.value == id) return entry.key;
  }
  return kDefaultSpecies;
}

/// How the renderer draws a leaf. Geometry does not care.
///
/// `lance` is a long willow leaf, `scale` the short overlapping foliage of a
/// cypress, `feather` a pinnate acacia leaf (a rib with tiny leaflets).
enum LeafShape { oval, narrow, large, needle, frond, almond, lance, scale, feather }

/// How the renderer draws the vrucht. Geometry does not care.
enum FruitStyle {
  acorn,
  olive,
  fig,
  dates,
  almond,
  cone,
  apple,
  pomegranate,
  catkin,
  pod,
  berry,
}

/// `branching` is the recursive fan every deciduous tree uses. `palm` is one
/// curved trunk of segments with a crown of fronds. `conical` keeps a leader
/// going straight up and sends short, near-horizontal side branches out of
/// every node, longer at the bottom - the cedar silhouette.
enum TreeForm { branching, palm, conical }

/// `seasonal` blossoms in spring from the `blossom` trait level on; `always`
/// blossoms every spring regardless of level (the amandel, Jeremia 1:11);
/// `never` is for the trees that simply do not.
enum BlossomMode { never, seasonal, always }

class SpeciesParams {
  const SpeciesParams({
    this.form = TreeForm.branching,
    this.trunkLenMul = 1,
    this.trunkWidthMul = 1,
    this.spreadBase = 26,
    this.spreadJitter = 14,
    this.curveAmp = 10,
    this.childLenRatio = 0.74,
    this.childWidthRatio = 0.68,
    this.thirdChildBias = 0,
    this.leanMul = 1,
    this.droopBase = 0,
    this.leafCountMul = 1,
    this.leafSizeMul = 1,
    required this.leafShape,
    required this.fruitStyle,
    this.blossom = BlossomMode.seasonal,
    this.blossomColor,
    this.evergreen = false,
    this.leaf,
    this.leafAlt,
    required this.fruit,
    required this.fruitAlt,
  });

  final TreeForm form;
  final double trunkLenMul;
  final double trunkWidthMul;

  /// Degrees. The fan each node opens; jitter is the seeded spread on top.
  final double spreadBase;
  final double spreadJitter;

  /// Degrees. How far one branch is allowed to bend along its own length.
  final double curveAmp;
  final double childLenRatio;
  final double childWidthRatio;

  /// Added to the chance of a third child at a node.
  final double thirdChildBias;

  /// Multiplies the trunk's seeded lean.
  final double leanMul;

  /// 0..1. How far branch tips hang toward straight down when the tree is
  /// perfectly healthy - the weeping willow. Added to the wilt droop, which is
  /// why it is a generator parameter and not paint. Zero for every species
  /// that existed before it, so their fixtures did not move.
  final double droopBase;
  final double leafCountMul;
  final double leafSizeMul;
  final LeafShape leafShape;
  final FruitStyle fruitStyle;
  final BlossomMode blossom;

  /// The blossom's own colour. `null` keeps the seasonal pink. Palette only.
  final Color? blossomColor;

  /// Keeps its leaves through autumn and winter. Palette only.
  final bool evergreen;

  /// Foliage colour. `null` keeps the seasonal default.
  final Color? leaf;
  final Color? leafAlt;
  final Color fruit;
  final Color fruitAlt;
}

const Map<TreeSpecies, SpeciesParams> kSpecies = {
  // The tree everyone had before species existed. Every default above is the
  // old generator's constant, so an untouched account keeps its silhouette.
  TreeSpecies.eik: SpeciesParams(
    leafShape: LeafShape.oval,
    fruitStyle: FruitStyle.acorn,
    fruit: Color(0xFF8B5A2B),
    fruitAlt: Color(0xFF5C3A1B),
  ),
  TreeSpecies.olijf: SpeciesParams(
    trunkLenMul: 0.8,
    trunkWidthMul: 1.3,
    spreadBase: 36,
    spreadJitter: 16,
    curveAmp: 18,
    childLenRatio: 0.7,
    childWidthRatio: 0.7,
    thirdChildBias: 0.1,
    leanMul: 1.4,
    leafCountMul: 1.15,
    leafSizeMul: 0.85,
    leafShape: LeafShape.narrow,
    fruitStyle: FruitStyle.olive,
    evergreen: true,
    leaf: Color(0xFF7FA37A),
    leafAlt: Color(0xFFA6BFA3),
    fruit: Color(0xFF3B4A2A),
    fruitAlt: Color(0xFF6B7F3A),
  ),
  TreeSpecies.vijg: SpeciesParams(
    trunkLenMul: 0.75,
    trunkWidthMul: 1.3,
    spreadBase: 40,
    spreadJitter: 12,
    curveAmp: 12,
    childLenRatio: 0.72,
    childWidthRatio: 0.75,
    thirdChildBias: 0.15,
    leafCountMul: 0.55,
    leafSizeMul: 1.35,
    leafShape: LeafShape.large,
    fruitStyle: FruitStyle.fig,
    blossom: BlossomMode.never,
    leaf: Color(0xFF3F8F4F),
    leafAlt: Color(0xFF4FA25E),
    fruit: Color(0xFF5B2C6F),
    fruitAlt: Color(0xFF7A3E8F),
  ),
  TreeSpecies.palm: SpeciesParams(
    form: TreeForm.palm,
    trunkLenMul: 1.45,
    trunkWidthMul: 0.9,
    curveAmp: 6,
    leanMul: 1.2,
    leafSizeMul: 1,
    leafShape: LeafShape.frond,
    fruitStyle: FruitStyle.dates,
    blossom: BlossomMode.never,
    evergreen: true,
    leaf: Color(0xFF4F9A57),
    leafAlt: Color(0xFF6BB36F),
    fruit: Color(0xFFB5651D),
    fruitAlt: Color(0xFF8A4A12),
  ),
  TreeSpecies.amandel: SpeciesParams(
    trunkLenMul: 1.05,
    trunkWidthMul: 0.85,
    spreadBase: 22,
    spreadJitter: 10,
    curveAmp: 8,
    childLenRatio: 0.76,
    childWidthRatio: 0.66,
    thirdChildBias: 0.05,
    leanMul: 0.8,
    leafCountMul: 0.9,
    leafSizeMul: 0.9,
    leafShape: LeafShape.almond,
    fruitStyle: FruitStyle.almond,
    blossom: BlossomMode.always,
    blossomColor: Color(0xFFFBD3E0),
    leaf: Color(0xFF6DAE70),
    leafAlt: Color(0xFF8CC58E),
    fruit: Color(0xFFD9C7A0),
    fruitAlt: Color(0xFFB89B6A),
  ),
  TreeSpecies.ceder: SpeciesParams(
    form: TreeForm.conical,
    trunkLenMul: 1.15,
    trunkWidthMul: 1.1,
    spreadBase: 30,
    spreadJitter: 8,
    curveAmp: 5,
    childLenRatio: 0.68,
    childWidthRatio: 0.7,
    thirdChildBias: 0.2,
    leanMul: 0.5,
    leafCountMul: 1.6,
    leafSizeMul: 0.8,
    leafShape: LeafShape.needle,
    fruitStyle: FruitStyle.cone,
    blossom: BlossomMode.never,
    evergreen: true,
    leaf: Color(0xFF2F6B4F),
    leafAlt: Color(0xFF3F7F5F),
    fruit: Color(0xFF6B4E2A),
    fruitAlt: Color(0xFF4A361D),
  ),
  // The smallest seed. Many thin twigs, tiny leaves, and yellow flowers every
  // spring whatever the level - the point of the parable is that it blooms.
  TreeSpecies.mosterd: SpeciesParams(
    trunkLenMul: 0.85,
    trunkWidthMul: 0.8,
    spreadBase: 34,
    spreadJitter: 16,
    curveAmp: 14,
    childLenRatio: 0.72,
    childWidthRatio: 0.62,
    thirdChildBias: 0.3,
    leanMul: 1.1,
    leafCountMul: 1.3,
    leafSizeMul: 0.6,
    leafShape: LeafShape.oval,
    fruitStyle: FruitStyle.pod,
    blossom: BlossomMode.always,
    blossomColor: Color(0xFFF3D45A),
    leaf: Color(0xFF8DBB5E),
    leafAlt: Color(0xFFA9CF74),
    fruit: Color(0xFF9BA85A),
    fruitAlt: Color(0xFF6F7C3A),
  ),
  TreeSpecies.appel: SpeciesParams(
    trunkLenMul: 0.9,
    trunkWidthMul: 1.05,
    spreadBase: 32,
    spreadJitter: 12,
    curveAmp: 10,
    childLenRatio: 0.72,
    childWidthRatio: 0.68,
    thirdChildBias: 0.12,
    leanMul: 0.9,
    leafCountMul: 1.05,
    leafSizeMul: 0.95,
    leafShape: LeafShape.oval,
    fruitStyle: FruitStyle.apple,
    blossomColor: Color(0xFFFBE4EC),
    leaf: Color(0xFF5FA85A),
    leafAlt: Color(0xFF7CC077),
    fruit: Color(0xFFC8382E),
    fruitAlt: Color(0xFF8E2320),
  ),
  TreeSpecies.granaatappel: SpeciesParams(
    trunkLenMul: 0.7,
    trunkWidthMul: 1,
    spreadBase: 38,
    spreadJitter: 14,
    curveAmp: 14,
    childLenRatio: 0.7,
    childWidthRatio: 0.66,
    thirdChildBias: 0.2,
    leafCountMul: 1.2,
    leafSizeMul: 0.75,
    leafShape: LeafShape.narrow,
    fruitStyle: FruitStyle.pomegranate,
    blossomColor: Color(0xFFE8532F),
    leaf: Color(0xFF4E9A4A),
    leafAlt: Color(0xFF6CB35F),
    fruit: Color(0xFFB8322F),
    fruitAlt: Color(0xFF7E1F1D),
  ),
  // Zacheüs' tree: low, wide, thick enough to climb.
  TreeSpecies.sycomoor: SpeciesParams(
    trunkLenMul: 0.7,
    trunkWidthMul: 1.6,
    spreadBase: 46,
    spreadJitter: 12,
    curveAmp: 12,
    childLenRatio: 0.7,
    childWidthRatio: 0.74,
    thirdChildBias: 0.2,
    leafCountMul: 0.75,
    leafSizeMul: 1.2,
    leafShape: LeafShape.large,
    fruitStyle: FruitStyle.fig,
    blossom: BlossomMode.never,
    leaf: Color(0xFF5E9E4E),
    leafAlt: Color(0xFF7DB566),
    fruit: Color(0xFFD9A24A),
    fruitAlt: Color(0xFFA87428),
  ),
  // The one species with a droop of its own: long thin branches that hang.
  TreeSpecies.wilg: SpeciesParams(
    trunkWidthMul: 1.15,
    spreadBase: 30,
    spreadJitter: 14,
    curveAmp: 12,
    childLenRatio: 0.8,
    childWidthRatio: 0.6,
    thirdChildBias: 0.15,
    leanMul: 1.2,
    droopBase: 0.5,
    leafCountMul: 1.2,
    leafSizeMul: 0.9,
    leafShape: LeafShape.lance,
    fruitStyle: FruitStyle.catkin,
    blossom: BlossomMode.never,
    leaf: Color(0xFF8FB86A),
    leafAlt: Color(0xFFB0CC8A),
    fruit: Color(0xFFD9D27A),
    fruitAlt: Color(0xFFA9A24A),
  ),
  // A long stem and a flat, wide crown of feathery leaves.
  TreeSpecies.acacia: SpeciesParams(
    trunkLenMul: 1.25,
    trunkWidthMul: 0.9,
    spreadBase: 50,
    spreadJitter: 10,
    curveAmp: 6,
    childLenRatio: 0.6,
    childWidthRatio: 0.62,
    thirdChildBias: 0.25,
    leanMul: 1.3,
    leafCountMul: 1.2,
    leafSizeMul: 0.7,
    leafShape: LeafShape.feather,
    fruitStyle: FruitStyle.pod,
    blossomColor: Color(0xFFF6E27A),
    leaf: Color(0xFF6E9E5A),
    leafAlt: Color(0xFF8FB574),
    fruit: Color(0xFF8B6B3A),
    fruitAlt: Color(0xFF5E4626),
  ),
  // The ceder's narrow cousin: same spine, a much tighter fan.
  TreeSpecies.cipres: SpeciesParams(
    form: TreeForm.conical,
    trunkLenMul: 1.3,
    trunkWidthMul: 0.8,
    spreadBase: 12,
    spreadJitter: 6,
    curveAmp: 3,
    childLenRatio: 0.6,
    childWidthRatio: 0.7,
    thirdChildBias: 0.2,
    leanMul: 0.3,
    leafCountMul: 1.5,
    leafSizeMul: 0.7,
    leafShape: LeafShape.scale,
    fruitStyle: FruitStyle.berry,
    blossom: BlossomMode.never,
    evergreen: true,
    leaf: Color(0xFF2E5E3E),
    leafAlt: Color(0xFF3D7450),
    fruit: Color(0xFF7A6A4A),
    fruitAlt: Color(0xFF55492F),
  ),
};

SpeciesParams speciesParams(TreeSpecies species) => kSpecies[species]!;
