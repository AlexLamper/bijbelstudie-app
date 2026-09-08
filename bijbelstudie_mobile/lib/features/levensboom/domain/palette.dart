/// Colour for the tree. Pure function of season, clock, health, scene and
/// species - no RNG, which is why the parity fixtures can ignore it and stay
/// clock-independent.
///
/// Mirror of the website's `lib/levensboom/palette.ts`; the hex values are the
/// table in `docs/levensboom-spec.md` §7.
library;

import 'package:flutter/painting.dart';

import 'scenes.dart';
import 'species.dart';

enum Season { spring, summer, autumn, winter }

/// The website calls this `timeOfDay`; the enum is named differently here only
/// because `TimeOfDay` is already Material's clock-time class and every file
/// that draws the tree also imports Material.
enum DayPhase { dawn, day, dusk, night }

class TreePalette {
  const TreePalette({
    required this.season,
    required this.timeOfDay,
    required this.scene,
    required this.skyTop,
    required this.skyBottom,
    required this.glow,
    required this.light,
    required this.bark,
    required this.barkLit,
    required this.leaf,
    required this.leafAlt,
    required this.blossom,
    required this.fruit,
    required this.fruitAlt,
    required this.ground,
    required this.groundDeep,
    required this.far,
    required this.farAlt,
    required this.water,
    required this.accent,
    required this.night,
  });

  /// Carried through so a renderer can draw the seasonal events of the
  /// `seasons` trait without re-deriving the month it already resolved.
  final Season season;

  /// After the scene's say: a `forceNight` scene reports night at noon.
  final DayPhase timeOfDay;
  final TreeSceneId scene;

  final Color skyTop, skyBottom, glow, light, bark, barkLit, leaf, leafAlt;
  final Color? blossom;
  final Color fruit, fruitAlt, ground, groundDeep;

  /// Distant shapes behind the tree: hills, dunes, the range, the wall.
  final Color far, farAlt;
  final Color? water;
  final Color accent;
  final bool night;
}

const _sky = <DayPhase, List<Color>>{
  // top, bottom, glow, light
  DayPhase.dawn: [
    Color(0xFF2E3A59),
    Color(0xFFF7C6A0),
    Color(0xFFFFD9A0),
    Color(0xFFFFE8CC),
  ],
  DayPhase.day: [
    Color(0xFF7EC8E3),
    Color(0xFFDFF3F7),
    Color(0xFFFFF4D6),
    Color(0xFFFFFFFF),
  ],
  DayPhase.dusk: [
    Color(0xFF4B3B6B),
    Color(0xFFE9906B),
    Color(0xFFFFC38A),
    Color(0xFFFFD9B3),
  ],
  DayPhase.night: [
    Color(0xFF0B1027),
    Color(0xFF232C4D),
    Color(0xFF3E4E80),
    Color(0xFFC9D6FF),
  ],
};

const _foliage = <Season, List<Color?>>{
  // leaf, leafAlt, blossom, ground
  Season.spring: [
    Color(0xFF6FBF73),
    Color(0xFF8FD694),
    Color(0xFFF7B8CE),
    Color(0xFF4E7C43),
  ],
  Season.summer: [
    Color(0xFF3F8F4F),
    Color(0xFF57A862),
    Color(0xFFF2A2C0),
    Color(0xFF43703C),
  ],
  Season.autumn: [
    Color(0xFFC9772E),
    Color(0xFFE0A03C),
    null,
    Color(0xFF6B5A32),
  ],
  Season.winter: [
    Color(0xFF7D8B7A),
    Color(0xFF9AA79A),
    null,
    Color(0xFF5B6660),
  ],
};

const _bark = Color(0xFF4A3A2E);
const _barkLit = Color(0xFF6B5442);
const _nightMix = Color(0xFF1B2340);
const _wiltMix = Color(0xFF8A8F7A);
const _winterMix = Color(0xFF8A9A8A);
const _almondBlossom = Color(0xFFFBD3E0);

Color _mix(Color a, Color b, double amount) =>
    Color.lerp(a, b, amount.clamp(0.0, 1.0))!;

/// `month` is 1-based, as `DateTime.month` gives it.
Season seasonForMonth(int month) {
  if (month == 12 || month <= 2) return Season.winter;
  if (month <= 5) return Season.spring;
  // September is still green in the Netherlands; autumn colours from October.
  if (month <= 9) return Season.summer;
  return Season.autumn;
}

DayPhase timeOfDayForHour(int hour) {
  if (hour < 6 || hour >= 21) return DayPhase.night;
  if (hour < 9) return DayPhase.dawn;
  if (hour < 18) return DayPhase.day;
  return DayPhase.dusk;
}

TreePalette buildPalette(
  Season season,
  DayPhase timeOfDay, {
  double health = 1,
  TreeSceneId scene = kDefaultScene,
  TreeSpecies species = kDefaultSpecies,
}) {
  final spec = sceneSpec(scene);
  final sp = speciesParams(species);
  final tod = spec.forceNight ? DayPhase.night : timeOfDay;
  final override = spec.sky[tod];
  final sky = _sky[tod]!;
  final foliage = _foliage[season]!;
  final night = tod == DayPhase.night;

  Color desaturate(Color c) => night ? _mix(c, _nightMix, 0.25) : c;
  Color wilt(Color c) => _mix(c, _wiltMix, (1 - health) * 0.4);

  // A species with its own green keeps it in spring and summer. Deciduous ones
  // turn with the season like the eik; evergreens only dull a little in winter.
  var leaf = foliage[0]!;
  var leafAlt = foliage[1]!;
  final ownLeaf = sp.leaf;
  final ownLeafAlt = sp.leafAlt;
  if (ownLeaf != null && ownLeafAlt != null) {
    final turning = season == Season.autumn || season == Season.winter;
    if (!turning) {
      leaf = ownLeaf;
      leafAlt = ownLeafAlt;
    } else if (sp.evergreen) {
      final dull = season == Season.winter ? 0.3 : 0.1;
      leaf = _mix(ownLeaf, _winterMix, dull);
      leafAlt = _mix(ownLeafAlt, _winterMix, dull);
    }
  }

  final seasonBlossom = foliage[2];
  final blossom = seasonBlossom == null
      ? null
      : (sp.blossom == BlossomMode.always ? _almondBlossom : seasonBlossom);
  final ground = spec.groundTop ?? foliage[3]!;
  final groundDeep = spec.groundBottom ?? _mix(foliage[3]!, _bark, 0.7);

  return TreePalette(
    season: season,
    timeOfDay: tod,
    scene: scene,
    skyTop: override?.top ?? sky[0],
    skyBottom: override?.bottom ?? sky[1],
    glow: override?.glow ?? sky[2],
    light: override?.light ?? sky[3],
    bark: desaturate(_bark),
    barkLit: desaturate(_barkLit),
    leaf: desaturate(wilt(leaf)),
    leafAlt: desaturate(wilt(leafAlt)),
    blossom: blossom == null ? null : desaturate(blossom),
    fruit: desaturate(sp.fruit),
    fruitAlt: desaturate(sp.fruitAlt),
    ground: desaturate(ground),
    groundDeep: desaturate(groundDeep),
    far: desaturate(spec.far),
    farAlt: desaturate(spec.farAlt),
    water: spec.water == null ? null : desaturate(spec.water!),
    accent: spec.accent,
    night: night,
  );
}

/// The palette for "now" on whatever device is asking.
TreePalette paletteForNow({
  double health = 1,
  DateTime? now,
  TreeSceneId scene = kDefaultScene,
  TreeSpecies species = kDefaultSpecies,
}) {
  final at = now ?? DateTime.now();
  return buildPalette(
    seasonForMonth(at.month),
    timeOfDayForHour(at.hour),
    health: health,
    scene: scene,
    species: species,
  );
}
