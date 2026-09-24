/// One generator run per distinct tree, shared by every painter on screen.
/// Mirror of the website's `lib/levensboom/sceneCache.ts`.
///
/// The tab icon, the dashboard header, the profile circle and a studio full of
/// tiles all draw the same account at the same position; without this each of
/// them re-runs the generator. The key is what decides the drawing (growth v2,
/// plan §4.10): the model, the seed and species, the level (traits and fruit),
/// the floor, an `at` override, the effective position bucketed - by default
/// to 1/50 of a step - so an XP tick does not regenerate a tree that could not
/// show the difference anyway, and the health. The scene is generated *at* the
/// bucketed position, so one key is always one drawing, whichever caller
/// filled it.
library;

import 'dart:math' as math;

import 'growth.dart';
import 'species.dart';
import 'tree_generator.dart';

const int _maxEntries = 48;
final Map<String, TreeScene> _cache = {};

/// Default position bucket: 1/50 of a step.
const int kPositionBucket = 50;

double _bucketed(double value, int bucket) => bucket > 0 ? (value * bucket).round() / bucket : value;

/// The generator input a cache key stands for: position bucketed, health to hundredths.
({String key, int level, double frac, double health, GrowthFloor? floor, TreeAt? at}) _normalise({
  required String seed,
  required int level,
  required double frac,
  required double health,
  required TreeSpecies species,
  required GrowthFloor? floor,
  required TreeAt? at,
  required int bucket,
}) {
  final lvl = level < 1 ? 1 : level;
  final f = frac.isFinite ? math.min(1.0, math.max(0.0, frac)) : 0.0;
  final fl = isFloor(floor) ? floor : null;
  final h = (health * 100).round() / 100;

  TreeAt? genAt;
  var genFrac = f;
  double position;
  if (at != null) {
    // The step is read before bucketing, so rounding 3.99 up never adds a step.
    final raw = at.position.isNaN ? 1.0 : math.max(1.0, at.position);
    final s = at.step ?? raw + 1e-9;
    final step = s.isFinite ? math.max(1, s.floor()) : 1;
    position = math.max(1.0, _bucketed(raw, bucket));
    genAt = TreeAt(position: position, step: step);
  } else {
    position = _bucketed(effectivePosition(lvl, f, fl), bucket);
    // Back from the bucketed position to the frac that lands on it; the level
    // (and with it the step, traits and fruit) is untouched.
    genFrac = bucket > 0 ? math.min(1.0, math.max(0.0, untaper(position, fl) - lvl)) : f;
  }

  final key = [
    'v$growthModel',
    seed,
    kSpeciesIds[species],
    lvl,
    fl != null ? '${fl.from},${fl.to}' : '-',
    genAt != null ? '@${genAt.step}' : '',
    position.toStringAsFixed(bucket > 0 ? 4 : 6),
    h.toStringAsFixed(2),
  ].join('|');
  return (key: key, level: lvl, frac: genFrac, health: h, floor: fl, at: genAt);
}

String sceneKey({
  required String seed,
  required int level,
  required double frac,
  double health = 1,
  TreeSpecies species = kDefaultSpecies,
  GrowthFloor? floor,
  TreeAt? at,
  int bucket = kPositionBucket,
}) {
  return _normalise(
    seed: seed,
    level: level,
    frac: frac,
    health: health,
    species: species,
    floor: floor,
    at: at,
    bucket: bucket,
  ).key;
}

/// The scene for these inputs, generated at most once per key. [bucket] is how
/// many positions per step are told apart (0: exact).
TreeScene cachedTree({
  required String seed,
  required int level,
  required double frac,
  double health = 1,
  TreeSpecies species = kDefaultSpecies,
  GrowthFloor? floor,
  TreeAt? at,
  int bucket = kPositionBucket,
}) {
  final n = _normalise(
    seed: seed,
    level: level,
    frac: frac,
    health: health,
    species: species,
    floor: floor,
    at: at,
    bucket: bucket,
  );
  final hit = _cache.remove(n.key);
  if (hit != null) {
    // Re-insert so insertion order doubles as recency.
    _cache[n.key] = hit;
    return hit;
  }
  final scene = generateTree(
    seed: seed,
    level: n.level,
    frac: n.frac,
    health: n.health,
    species: species,
    floor: n.floor,
    at: n.at,
  );
  _cache[n.key] = scene;
  if (_cache.length > _maxEntries) {
    _cache.remove(_cache.keys.first);
  }
  return scene;
}
