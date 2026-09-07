/// Colour for the tree. Pure function of season, clock and health - no RNG,
/// which is why the parity fixtures can ignore it and stay clock-independent.
///
/// Mirror of the website's `lib/levensboom/palette.ts`; the hex values are the
/// table in `docs/levensboom-spec.md` §7.
library;

import 'package:flutter/painting.dart';

enum Season { spring, summer, autumn, winter }

/// The website calls this `timeOfDay`; the enum is named differently here only
/// because `TimeOfDay` is already Material's clock-time class and every file
/// that draws the tree also imports Material.
enum DayPhase { dawn, day, dusk, night }

class TreePalette {
  const TreePalette({
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
    required this.ground,
    required this.night,
  });

  final Color skyTop, skyBottom, glow, light, bark, barkLit, leaf, leafAlt;
  final Color? blossom;
  final Color fruit, ground;
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
  // leaf, leafAlt, blossom, fruit, ground
  Season.spring: [
    Color(0xFF6FBF73),
    Color(0xFF8FD694),
    Color(0xFFF7B8CE),
    Color(0xFFE4572E),
    Color(0xFF4E7C43),
  ],
  Season.summer: [
    Color(0xFF3F8F4F),
    Color(0xFF57A862),
    Color(0xFFF2A2C0),
    Color(0xFFE0483B),
    Color(0xFF43703C),
  ],
  Season.autumn: [
    Color(0xFFC9772E),
    Color(0xFFE0A03C),
    null,
    Color(0xFFB8442B),
    Color(0xFF6B5A32),
  ],
  Season.winter: [
    Color(0xFF7D8B7A),
    Color(0xFF9AA79A),
    null,
    Color(0xFFA3452E),
    Color(0xFF5B6660),
  ],
};

const _bark = Color(0xFF4A3A2E);
const _barkLit = Color(0xFF6B5442);
const _nightMix = Color(0xFF1B2340);
const _wiltMix = Color(0xFF8A8F7A);

Color _mix(Color a, Color b, double amount) =>
    Color.lerp(a, b, amount.clamp(0.0, 1.0))!;

/// `month` is 1-based, as `DateTime.month` gives it.
Season seasonForMonth(int month) {
  if (month == 12 || month <= 2) return Season.winter;
  if (month <= 5) return Season.spring;
  if (month <= 8) return Season.summer;
  return Season.autumn;
}

DayPhase timeOfDayForHour(int hour) {
  if (hour < 6 || hour >= 21) return DayPhase.night;
  if (hour < 9) return DayPhase.dawn;
  if (hour < 18) return DayPhase.day;
  return DayPhase.dusk;
}

TreePalette buildPalette(Season season, DayPhase timeOfDay, {double health = 1}) {
  final sky = _sky[timeOfDay]!;
  final foliage = _foliage[season]!;
  final night = timeOfDay == DayPhase.night;

  Color desaturate(Color c) => night ? _mix(c, _nightMix, 0.25) : c;
  Color wilt(Color c) => _mix(c, _wiltMix, (1 - health) * 0.4);

  return TreePalette(
    skyTop: sky[0],
    skyBottom: sky[1],
    glow: sky[2],
    light: sky[3],
    bark: desaturate(_bark),
    barkLit: desaturate(_barkLit),
    leaf: desaturate(wilt(foliage[0]!)),
    leafAlt: desaturate(wilt(foliage[1]!)),
    blossom: foliage[2] == null ? null : desaturate(foliage[2]!),
    fruit: desaturate(foliage[3]!),
    ground: desaturate(foliage[4]!),
    night: night,
  );
}

/// The palette for "now" on whatever device is asking.
TreePalette paletteForNow({double health = 1, DateTime? now}) {
  final at = now ?? DateTime.now();
  return buildPalette(
    seasonForMonth(at.month),
    timeOfDayForHour(at.hour),
    health: health,
  );
}
