/// One generator run per distinct tree, shared by every painter on screen.
///
/// The tab icon, the dashboard header, the profile circle and a studio full of
/// tiles all draw the same account at the same level; without this each of
/// them re-runs the recursion. Small avatars also bucket `frac` so an XP tick
/// does not regenerate a 24 px tree that could not show the difference.
library;

import 'species.dart';
import 'tree_generator.dart';

const int _maxEntries = 48;
final Map<String, TreeScene> _cache = {};

String sceneKey({
  required String seed,
  required int level,
  required double frac,
  required double health,
  required TreeSpecies species,
  int fracBucket = 0,
}) {
  final f = fracBucket > 0 ? (frac * fracBucket).round() / fracBucket : frac;
  return '$seed|${kSpeciesIds[species]}|${level < 1 ? 1 : level}|'
      '${f.toStringAsFixed(3)}|${health.toStringAsFixed(2)}';
}

TreeScene cachedTree({
  required String seed,
  required int level,
  required double frac,
  double health = 1,
  TreeSpecies species = kDefaultSpecies,
  int fracBucket = 0,
}) {
  final key = sceneKey(
    seed: seed,
    level: level,
    frac: frac,
    health: health,
    species: species,
    fracBucket: fracBucket,
  );
  final hit = _cache.remove(key);
  if (hit != null) {
    // Re-insert so insertion order doubles as recency.
    _cache[key] = hit;
    return hit;
  }
  final f = fracBucket > 0 ? (frac * fracBucket).round() / fracBucket : frac;
  final scene = generateTree(
    seed: seed,
    level: level,
    frac: f,
    health: health,
    species: species,
  );
  _cache[key] = scene;
  if (_cache.length > _maxEntries) {
    _cache.remove(_cache.keys.first);
  }
  return scene;
}
