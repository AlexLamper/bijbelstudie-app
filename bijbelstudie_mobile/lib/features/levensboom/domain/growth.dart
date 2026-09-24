/// Growth v2: how far along a tree is, and the table that turns that into
/// wood. Mirror of the website's `lib/levensboom/growth.ts` - every function
/// and every number there exists here too, under the same name in
/// lowerCamelCase, except `LEGACY_EQUIV`, `legacyEquivalent` and
/// `floorForLegacyXp`, which are server-only: the app gets the floor
/// ready-made in `levensboom.growth.floor`.
///
/// Plan: LEVENSBOOM_GROWTH_PLAN.md §4-§5. Contract: docs/levensboom-spec.md.
///
/// Three numbers describe a tree:
///
///     raw position  r = level + frac            frac = xpIntoLevel / xpForNextLevel
///     position      e = taper(r, floor)         = r for an account without a floor
///     step          k = floor(taper(level))     changes only at a level-up
///
/// `k` decides the topology (which branches and leaves exist), `e` the
/// continuous size (lengths, widths, the camera). Steps 1-20 are the named
/// growth; past 20 the tree matures and every step is a jaarring.
///
/// The arithmetic is written in the same order as the TypeScript, with no
/// `pow` or `exp`, so both platforms produce bit-identical doubles
/// (`test/levensboom_growth_test.dart` holds the web's own outputs). Where
/// the TypeScript would carry a NaN into `Math.floor`, Dart would throw, so
/// those few spots read NaN as position 1 instead.
///
/// Two names differ because Dart has one namespace for constants and
/// functions: the tables `FILL_SCENE` / `FILL_PORTRAIT` are
/// [fillSceneTable] / [fillPortraitTable], next to the functions [fillScene]
/// and [fillPortrait].
library;

import 'dart:math' as math;

import 'growth_ref.dart';
import 'species.dart';
import 'stages.dart';

const int growthModel = 2;
const int stepsTotal = 20;

/// [stepsTotal] under a name [GrowthInfo]'s own field does not shadow.
const int _stepsTotal = stepsTotal;

/// A legacy account's head start: at raw position [from] the tree is at [to].
class GrowthFloor {
  const GrowthFloor({required this.from, required this.to});

  final double from;
  final double to;

  /// A valid floor, or null: anything malformed reads as "no floor", which is
  /// what [isFloor] decides on the web too.
  static GrowthFloor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final from = raw['from'];
    final to = raw['to'];
    if (from is! num || to is! num) return null;
    final floor = GrowthFloor(from: from.toDouble(), to: to.toDouble());
    return isFloor(floor) ? floor : null;
  }

  Map<String, Object?> toJson() => {'from': from, 'to': to};

  @override
  bool operator ==(Object other) => other is GrowthFloor && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'GrowthFloor($from → $to)';
}

double _clamp(double value, double min, double max) => math.min(max, math.max(min, value));

double _round(double value, int decimals) {
  var m = 1.0;
  for (var i = 0; i < decimals; i++) {
    m *= 10;
  }
  // `roundToDouble` rounds half away from zero, `Math.round` half up: the
  // same for the positive positions this rounds, and it never throws.
  return (value * m).roundToDouble() / m;
}

/// `Math.max(1, Math.floor(level))`, with a non-finite level reading as 1.
int _wholeLevel(num level) => level.isFinite ? math.max(1, level.floor()) : 1;

/// A whole number from JSON, or null for anything else (a string, NaN, a map).
int? _int(Object? raw) => raw is num && raw.isFinite ? raw.toInt() : null;

/// Floating-point slack for "is this position a whole step".
const double _stepEpsilon = 1e-9;

// ---------------------------------------------------------------------------
// Position, taper, step
// ---------------------------------------------------------------------------

double rawPosition(num level, double frac) {
  return _wholeLevel(level) + _clamp(frac.isFinite ? frac : 0.0, 0, 1);
}

bool isFloor(GrowthFloor? floor) {
  return floor != null &&
      floor.from.isFinite &&
      floor.to.isFinite &&
      floor.from >= 1 &&
      floor.to > floor.from;
}

/// Where the head start has fully tapered off: step 20, or three steps past the floor.
double floorEnd(GrowthFloor floor) {
  return math.max(stepsTotal.toDouble(), floor.to + 3);
}

/// Raw position to effective position (plan §5.5).
///
/// taper(from) = to, continuous, strictly increasing, never below r, and equal
/// to r from [floorEnd] on. Below `from` (XP only ever grows, so this is a
/// defensive branch) the head start is simply added.
double taper(double r, GrowthFloor? floor) {
  if (!isFloor(floor)) return r;
  final f = floor!;
  final end = floorEnd(f);
  if (r >= end) return r;
  if (r <= f.from) return r + (f.to - f.from);
  return f.to + ((r - f.from) * (end - f.to)) / (end - f.from);
}

/// The inverse of [taper]: the raw position at which the tree reaches `e`.
double untaper(double e, GrowthFloor? floor) {
  if (!isFloor(floor)) return e;
  final f = floor!;
  final end = floorEnd(f);
  if (e >= end) return e;
  if (e <= f.to) return e - (f.to - f.from);
  return f.from + ((e - f.to) * (end - f.from)) / (end - f.to);
}

double effectivePosition(num level, double frac, [GrowthFloor? floor]) {
  return taper(rawPosition(level, frac), floor);
}

/// The structural step: which branches exist. Changes only at a level-up.
int structuralStep(num level, [GrowthFloor? floor]) {
  return math.max(1, (taper(_wholeLevel(level).toDouble(), floor) + _stepEpsilon).floor());
}

/// The first level at which an account with this floor stands on `step`.
int levelForStep(num step, [GrowthFloor? floor]) {
  final target = step.isFinite ? math.max(1, step.floor()) : 1;
  var level = math.max(1, (untaper(target.toDouble(), floor) - _stepEpsilon).ceil());
  // untaper is exact up to rounding; settle the last ulp against the forward map.
  while (level > 1 && structuralStep(level - 1, floor) >= target) {
    level -= 1;
  }
  while (structuralStep(level, floor) < target) {
    level += 1;
  }
  return level;
}

int ringsForStep(num step) {
  return math.max(0, (step.isFinite ? step.floor() : 0) - stepsTotal);
}

// ---------------------------------------------------------------------------
// XP (Appendix A; the website's `client.ts`)
// ---------------------------------------------------------------------------

/// Total XP at which `level` starts: `50·(L-1)·L`.
int xpForLevel(int level) => level <= 1 ? 0 : 50 * (level - 1) * level;

int levelForXp(num xp) {
  var level = 1;
  while (level < 200 && xp >= xpForLevel(level + 1)) {
    level += 1;
  }
  return level;
}

/// level + frac under the XP curve (Appendix A).
double positionForXp(num xp) {
  final safe = math.max(0.0, xp.isFinite ? xp.toDouble() : 0.0);
  final level = levelForXp(safe);
  final floorXp = xpForLevel(level);
  final span = math.max(1, xpForLevel(level + 1) - floorXp);
  return level + _clamp((safe - floorXp) / span, 0, 1);
}

// ---------------------------------------------------------------------------
// The growth block the API serves (plan §6.1)
// ---------------------------------------------------------------------------

class GrowthPhase {
  const GrowthPhase({
    required this.id,
    required this.name,
    required this.index,
    required this.fromStep,
    required this.toStep,
    required this.blurb,
  });

  final String id;
  final String name;
  final int index;
  final int fromStep;

  /// Null on the open-ended last phase.
  final int? toStep;
  final String blurb;

  /// The server's phase, or null when it is not a usable phase block.
  static GrowthPhase? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) return null;
    final local = stageById(id);
    return GrowthPhase(
      id: id,
      name: name,
      index: _int(raw['index']) ?? (local == null ? 0 : kStages.indexOf(local)),
      fromStep: _int(raw['fromStep']) ?? local?.from ?? 1,
      toStep: raw.containsKey('toStep') ? _int(raw['toStep']) : local?.to,
      blurb: raw['blurb'] is String ? raw['blurb'] as String : local?.blurb ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'index': index,
    'fromStep': fromStep,
    'toStep': toStep,
    'blurb': blurb,
  };
}

class GrowthNextPhase {
  const GrowthNextPhase({required this.id, required this.name, required this.fromStep});

  final String id;
  final String name;
  final int fromStep;

  static GrowthNextPhase? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final fromStep = _int(raw['fromStep']);
    if (id is! String || name is! String || fromStep == null) return null;
    return GrowthNextPhase(id: id, name: name, fromStep: fromStep);
  }

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'fromStep': fromStep};
}

class GrowthInfo {
  const GrowthInfo({
    this.model = growthModel,
    required this.position,
    required this.step,
    this.stepsTotal = _stepsTotal,
    required this.rings,
    required this.phase,
    required this.nextPhase,
    required this.floor,
  });

  final int model;

  /// Effective position `e`, 4 decimals.
  final double position;
  final int step;
  final int stepsTotal;
  final int rings;
  final GrowthPhase phase;
  final GrowthNextPhase? nextPhase;
  final GrowthFloor? floor;

  /// The phase in the shape the rest of the app reads ([StageInfo]), with the
  /// server's words when it served them. A phase id this build does not know
  /// falls back to the local table for [step].
  StageInfo get stage {
    final known = stageById(phase.id);
    if (known == null) return phaseForStep(step);
    return StageInfo(
      def: StageDef(
        stage: known.stage,
        name: phase.name,
        from: phase.fromStep,
        to: phase.toStep,
        blurb: phase.blurb,
      ),
      index: phase.index,
      nextLevel: nextPhase?.fromStep,
      nextName: nextPhase?.name,
    );
  }

  /// Parses `levensboom.growth`, defensively. Anything missing or malformed
  /// is computed locally from [level] and [frac] (with the served floor, when
  /// there is one); no block at all - a server older than growth v2 - is the
  /// local computation without a floor.
  static GrowthInfo fromJson(Object? raw, {required int level, required double frac}) {
    if (raw is! Map) return growthInfo(level, frac);
    final floor = GrowthFloor.fromJson(raw['floor']);
    final local = growthInfo(level, frac, floor);

    final servedPosition = raw['position'];
    final position = servedPosition is num && servedPosition.isFinite && servedPosition >= 1
        ? servedPosition.toDouble()
        : local.position;
    final servedStep = _int(raw['step']);
    final step = servedStep != null && servedStep >= 1 ? servedStep : local.step;

    final phase = GrowthPhase.fromJson(raw['phase']);
    final GrowthPhase shownPhase;
    final GrowthNextPhase? next;
    if (phase != null) {
      shownPhase = phase;
      next = raw.containsKey('nextPhase')
          ? GrowthNextPhase.fromJson(raw['nextPhase'])
          : _phaseBlock(step).next;
    } else {
      final block = _phaseBlock(step);
      shownPhase = block.phase;
      next = block.next;
    }

    return GrowthInfo(
      model: _int(raw['model']) ?? growthModel,
      position: position,
      step: step,
      stepsTotal: _int(raw['stepsTotal']) ?? _stepsTotal,
      rings: _int(raw['rings']) ?? ringsForStep(step),
      phase: shownPhase,
      nextPhase: next,
      floor: floor,
    );
  }

  Map<String, Object?> toJson() => {
    'model': model,
    'position': position,
    'step': step,
    'stepsTotal': stepsTotal,
    'rings': rings,
    'phase': phase.toJson(),
    'nextPhase': nextPhase?.toJson(),
    'floor': floor?.toJson(),
  };
}

({GrowthPhase phase, GrowthNextPhase? next}) _phaseBlock(int step) {
  final phase = phaseForStep(step);
  final next = phase.index + 1 < kStages.length ? kStages[phase.index + 1] : null;
  return (
    phase: GrowthPhase(
      id: phase.id,
      name: phase.name,
      index: phase.index,
      fromStep: phase.from,
      toStep: phase.to,
      blurb: phase.blurb,
    ),
    next: next == null ? null : GrowthNextPhase(id: next.id, name: next.name, fromStep: next.from),
  );
}

GrowthInfo growthInfo(int level, double frac, [GrowthFloor? floor]) {
  final f = isFloor(floor) ? floor : null;
  final step = structuralStep(level, f);
  final block = _phaseBlock(step);
  return GrowthInfo(
    model: growthModel,
    position: _round(effectivePosition(level, frac, f), 4),
    step: step,
    stepsTotal: stepsTotal,
    rings: ringsForStep(step),
    phase: block.phase,
    nextPhase: block.next,
    floor: f,
  );
}

// ---------------------------------------------------------------------------
// The design table (placeholder numbers until the design pass - plan §10)
// ---------------------------------------------------------------------------

class FormTable {
  const FormTable({
    required this.size,
    required this.sizeMax,
    required this.sizeMatureHalf,
    required this.birth,
    required this.birthSpread,
    required this.thirdDelay,
    required this.thirdChance,
    required this.leavesPerTip,
    required this.leafBonusAt,
    required this.innerKeep,
    required this.cotyledons,
    required this.cotyledonDeath,
    required this.seedlingPairs,
    required this.pairDeath,
    required this.palmSegments,
    required this.palmFronds,
  });

  /// Continuous size 0..1 at steps 1..20 (index = step - 1); linear in between.
  final List<double> size;

  /// Where size tends to past step 20 (maturing, asymptotic).
  final double sizeMax;

  /// Steps past 20 at which half the remaining size is reached.
  final double sizeMatureHalf;

  /// Base birth step per depth (index = depth). Deeper nodes never exist.
  final List<int> birth;

  /// A node is born up to `floor(birthJitter * spread)` steps late, per depth.
  final List<int> birthSpread;

  /// Extra steps before a third (middle) child can appear.
  final int thirdDelay;

  /// Chance of a third child at step k (index = k - 1, the last value holds). Non-decreasing.
  final List<double> thirdChance;

  /// Leaves on a tip at step k before `leafCountMul` (index = k - 1, the last value holds).
  final List<double> leavesPerTip;

  /// Steps at which every tip gains one more leaf (maturing density).
  final List<int> leafBonusAt;

  /// Steps a node keeps its own leaves after its first child appears.
  final int innerKeep;

  /// Seed leaves: how many, and the step at which they are gone.
  final int cotyledons;
  final int cotyledonDeath;

  /// Seedling leaf pairs on the stem: pair j appears at step j + 1; all are gone at [pairDeath].
  final int seedlingPairs;
  final int pairDeath;

  /// Palm only: the step each trunk segment appears (index = segment).
  final List<int> palmSegments;

  /// Palm only: fronds at step k (index = k - 1, the last value holds, before [leafBonusAt]).
  final List<int> palmFronds;
}

const List<double> _sizeV2 = [
  0.0, 0.064, 0.115, 0.162, 0.207, 0.251, 0.293, 0.334, 0.374, 0.413, 0.452, 0.49, 0.528, 0.565, 0.602, 0.638,
  0.674, 0.71, 0.745, 0.78,
];

const List<double> _thirdChanceV2 = [
  0.15, 0.163, 0.173, 0.182, 0.191, 0.2, 0.209, 0.217, 0.225, 0.233, 0.24, 0.248, 0.256, 0.263, 0.27, 0.278, 0.285,
  0.292, 0.299, 0.306,
];

/// Conifers fork three ways far less often: their tiers are shelves, not crowns.
const List<double> _thirdChanceConical = [
  0.06, 0.065, 0.069, 0.073, 0.076, 0.08, 0.084, 0.087, 0.09, 0.093, 0.096, 0.099, 0.102, 0.105, 0.108, 0.111, 0.114,
  0.117, 0.12, 0.122,
];

const List<double> _leavesV2 = [
  2, 2.07, 2.28, 2.48, 2.67, 2.86, 3.03, 3.2, 3.37, 3.53, 3.7, 3.86, 4.02, 4.18, 4.33, 4.48, 4.63, 4.78, 4.93, 5.08,
];

const Map<TreeForm, FormTable> formTables = {
  TreeForm.branching: FormTable(
    size: _sizeV2,
    sizeMax: 1.05,
    sizeMatureHalf: 12,
    birth: [1, 5, 8, 11, 14, 18],
    birthSpread: [0, 2, 2, 2, 3, 3],
    thirdDelay: 2,
    thirdChance: _thirdChanceV2,
    leavesPerTip: _leavesV2,
    leafBonusAt: [30],
    innerKeep: 3,
    cotyledons: 2,
    cotyledonDeath: 5,
    seedlingPairs: 4,
    pairDeath: 9,
    palmSegments: [],
    palmFronds: [],
  ),
  TreeForm.conical: FormTable(
    size: _sizeV2,
    sizeMax: 1.05,
    sizeMatureHalf: 12,
    birth: [1, 4, 8, 12, 16, 20],
    birthSpread: [0, 1, 2, 2, 2, 2],
    thirdDelay: 2,
    thirdChance: _thirdChanceConical,
    leavesPerTip: _leavesV2,
    leafBonusAt: [30],
    innerKeep: 1,
    cotyledons: 5,
    cotyledonDeath: 6,
    seedlingPairs: 3,
    pairDeath: 8,
    palmSegments: [],
    palmFronds: [],
  ),
  TreeForm.palm: FormTable(
    size: _sizeV2,
    sizeMax: 1.05,
    sizeMatureHalf: 12,
    birth: [1],
    birthSpread: [0],
    thirdDelay: 0,
    thirdChance: [0],
    leavesPerTip: [0],
    leafBonusAt: [25, 30, 35],
    innerKeep: 0,
    cotyledons: 0,
    cotyledonDeath: 1,
    seedlingPairs: 0,
    pairDeath: 1,
    palmSegments: [1, 8, 9, 10, 12, 14],
    palmFronds: [2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11],
  ),
};

/// Geometry constants shared by every form (the website's `GEOMETRY`).
class GrowthGeometry {
  const GrowthGeometry._();

  /// New wood appears at this share of its length, then elongates over [rampSteps].
  final double minBud = 0.25;
  final double rampSteps = 1.5;

  /// Trunk: length (4 + 36·size) and width (0.8 + 6.2·size), times the species multipliers.
  final double trunkLenBase = 4;
  final double trunkLenGrow = 36;
  final double trunkWidthBase = 0.8;
  final double trunkWidthGrow = 6.2;

  /// Green stem to bark: the trunk starts turning at [woodStart], other wood [woodDelay] steps after it appears.
  final double woodStart = 3;
  final double woodDelay = 1;
  final double woodSteps = 3;

  /// How much of a species' `leafCountMul` reaches the leaves per tip (the rest would blow the leaf budget).
  final double leafMulWeight = 0.6;

  /// Degrees of seeded jitter per child slot.
  final double slotJitter = 8;

  /// Degrees of seeded trunk lean, times the species' `leanMul`.
  final double lean = 6;

  /// Droop (wilt + weeping) grows with depth up to this depth.
  final int droopDepth = 5;

  /// Conical side branches shorten with depth up to this depth.
  final int conicalDepth = 6;

  /// Twin trunk (trait `twin`): offset, angle, length and width share, and how fast its depths follow.
  final double twinOffset = 6;
  final double twinAngle = 14;
  final double twinLen = 0.62;
  final double twinWidth = 0.55;
  final double twinDepthSteps = 1;

  /// A twin node is born up to `twinBirthSpread - 1` steps late.
  final int twinBirthSpread = 2;
  final int twinMaxDepth = 3;
}

const GrowthGeometry geometry = GrowthGeometry._();

/// The seedling (steps 1-6, plan §4.4; the website's `SEEDLING`). Seed leaves
/// sit where the step-1 stem ended and stay at that height while the stem
/// grows past them; leaf pair j appears at step j + 1, at [pairHeight] of the
/// stem's length at that step. Angles are degrees off the stem's heading.
class GrowthSeedling {
  const GrowthSeedling._();

  final double cotyledonAngle = 58;

  /// More than two seed leaves (a conifer's whorl) fan evenly over ±[cotyledonFan].
  final double cotyledonFan = 70;
  final double cotyledonDistance = 1.4;
  final double cotyledonSize = 1.6;

  /// Seed-leaf size factor per step (index = step - 1, the last value holds): they yellow and shrink.
  final List<double> cotyledonShrink = const [1, 1, 0.85, 0.7];
  final double pairAngle = 50;
  final double pairAngleJitter = 15;
  final double pairDistance = 0.9;
  final double pairSize = 1.3;
  final double pairSizeJitter = 0.4;
  final double pairHeight = 0.92;

  /// A palm's first segment stays a stub ([palmEmergeMin] of its length) until it emerges over these steps.
  final double palmEmergeSteps = 7;
  final double palmEmergeMin = 0.15;
}

const GrowthSeedling seedling = GrowthSeedling._();

/// Where palm frond i sits in the fan, -1..1 (times 95°). A fixed order, so a
/// new frond fills a gap and the fronds already there never re-fan. The
/// website's `PALM_FROND_FAN`.
const List<double> palmFrondFan = [
  -0.3, 0.3, -0.75, 0.75, 0, -0.55, 0.55, -1, 1, -0.15, 0.15, -0.9, 0.9, -0.4, 0.4, 0.05,
];

/// Render-only maturing details, by position (plan §4.5; the website's `MATURE`).
class GrowthMature {
  const GrowthMature._();

  final double knotsFrom = 22;
  final double mossFrom = 26;
  final double flareFrom = 30;
}

const GrowthMature mature = GrowthMature._();

T _tableAt<T extends num>(List<T> table, int step, T empty) {
  if (table.isEmpty) return empty;
  return table[math.min(table.length, math.max(1, step)) - 1];
}

/// Continuous size 0..sizeMax at position e.
double sizeAt(TreeForm form, double e) {
  final t = formTables[form]!;
  final n = t.size.length;
  final p = e.isNaN ? 1.0 : math.max(1.0, e);
  if (p >= n) {
    final top = t.size[n - 1];
    final past = p - n;
    return top + (t.sizeMax - top) * (past / (past + t.sizeMatureHalf));
  }
  final i = p.floor();
  final a = t.size[i - 1];
  final b = t.size[i];
  return a + (b - a) * (p - i);
}

/// Size at a whole step: the only size topology may read. A literal, so exact on both platforms.
double sizeAtStep(TreeForm form, int step) {
  final t = formTables[form]!;
  return _tableAt(t.size, math.min(step, t.size.length), 0.0);
}

double thirdChanceAt(TreeForm form, int step) {
  return _tableAt(formTables[form]!.thirdChance, step, 0.0);
}

int bonusLeaves(TreeForm form, int step) {
  var n = 0;
  for (final at in formTables[form]!.leafBonusAt) {
    if (step >= at) n += 1;
  }
  return n;
}

int leavesPerTip(TreeForm form, int step, double leafCountMul) {
  final base = _tableAt(formTables[form]!.leavesPerTip, step, 0.0);
  final mul = 1 + (leafCountMul - 1) * geometry.leafMulWeight;
  return math.max(2, (base * mul).round()) + bonusLeaves(form, step);
}

int palmFronds(int step) {
  return _tableAt(formTables[TreeForm.palm]!.palmFronds, step, 0) + bonusLeaves(TreeForm.palm, step);
}

double _smoothstep(double t) {
  return t * t * (3 - 2 * t);
}

/// How far a node born at step `birth` has elongated at position e. `minBud` at birth, 1 after `rampSteps`.
double ramp(double e, num birth) {
  final t = _clamp((e - birth) / geometry.rampSteps, 0, 1);
  return geometry.minBud + (1 - geometry.minBud) * _smoothstep(t);
}

// ---------------------------------------------------------------------------
// Camera (plan §4.8)
// ---------------------------------------------------------------------------

/// Scene framing: on-screen tree height as a share of the height above the earth band, steps 1..20.
/// The website's `FILL_SCENE`.
const List<double> fillSceneTable = [
  0.22, 0.279, 0.322, 0.362, 0.398, 0.433, 0.467, 0.499, 0.53, 0.561, 0.591, 0.62, 0.649, 0.678, 0.706, 0.733, 0.76,
  0.787, 0.814, 0.84,
];

/// Portrait framing (discs from 32 px up): the same idea, fuller. The website's `FILL_PORTRAIT`.
const List<double> fillPortraitTable = [
  0.6, 0.63, 0.653, 0.673, 0.692, 0.71, 0.727, 0.744, 0.76, 0.776, 0.791, 0.807, 0.822, 0.836, 0.851, 0.865, 0.879,
  0.893, 0.906, 0.92,
];

/// Below this many pixels a portrait keeps fitting its own bounds: legibility beats the growth story.
const double portraitFitBelowPx = 32;

double _curveAt(List<double> table, double e) {
  final n = table.length;
  final p = e.isNaN ? 1.0 : _clamp(e, 1, n.toDouble());
  final i = math.min(n - 1, p.floor());
  final a = table[i - 1];
  final b = table[math.min(n - 1, i)];
  return a + (b - a) * (p - i);
}

double fillScene(double e) {
  return _curveAt(fillSceneTable, e);
}

double fillPortrait(double e) {
  return _curveAt(fillPortraitTable, e);
}

/// The reference height (tree units above the ground line) of a species at
/// position e: the median over sampled seeds, tabled by `npm run
/// tree:calibrate` on the website. The camera divides by this and not by the
/// user's own bounds, so it never jitters per user and a level-up zooms the
/// same way for everyone.
double referenceHeight(double e, TreeSpecies? species) {
  final row = hRef[kSpeciesIds[species ?? kDefaultSpecies]] ?? hRef[kSpeciesIds[kDefaultSpecies]]!;
  final n = refPositions.length;
  if (e <= refPositions[0]) return row[0];
  for (var i = 1; i < n; i += 1) {
    if (e <= refPositions[i]) {
      final x0 = refPositions[i - 1];
      final t = (e - x0) / (refPositions[i] - x0);
      return row[i - 1] + (row[i] - row[i - 1]) * t;
    }
  }
  return row[n - 1];
}
