import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/features/levensboom/domain/chime.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/palette.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/rng.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/traits.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/tree_generator.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/tree_state.dart';

/// The parity contract with the website (`docs/levensboom-spec.md` §8).
///
/// `tests/levensboom.test.ts` in the bijbelstudie repo asserts these exact
/// numbers from the TypeScript generator. If one side changes and the other
/// does not, a reader's tree stops being the same tree on their phone and on
/// the website — which is the one promise this feature makes.
void main() {
  const seed = '65f0c1a2b3c4d5e6f7a8b9c0';

  // The first eight draws, to nine decimals. Checked before the geometry so an
  // RNG drift is reported as an RNG drift rather than as a branch-count change.
  const stream = [
    '0.996028406',
    '0.644957670',
    '0.778042284',
    '0.421987313',
    '0.524449135',
    '0.999463710',
    '0.146377759',
    '0.699959147',
  ];

  group('rng', () {
    test('hashes the seed to a stable stream', () {
      expect(fnv1a32(seed), 3091915409);
    });

    test('produces the fixture stream', () {
      final rand = seededRng(seed);
      expect(
        [for (var i = 0; i < stream.length; i++) rand().toStringAsFixed(9)],
        stream,
      );
    });

    test('is reproducible per seed and different between seeds', () {
      final a = seededRng(seed);
      final b = seededRng(seed);
      final c = seededRng('65f0c1a2b3c4d5e6f7a8b9c1');
      final first = [for (var i = 0; i < 4; i++) a()];
      expect([for (var i = 0; i < 4; i++) b()], first);
      expect([for (var i = 0; i < 4; i++) c()], isNot(first));
    });
  });

  group('geometry', () {
    const fixtures = [
      (level: 1, frac: 0.0, branches: 16, leaves: 39, open: 20, blossoms: 0, fruits: 0, fireflies: 0, maxDepth: 3, traits: <String>[]),
      (level: 4, frac: 0.5, branches: 35, leaves: 168, open: 126, blossoms: 0, fruits: 0, fireflies: 0, maxDepth: 4, traits: ['canopy']),
      (level: 7, frac: 0.4, branches: 40, leaves: 231, open: 162, blossoms: 11, fruits: 0, fireflies: 0, maxDepth: 4, traits: ['canopy', 'blossom']),
      (level: 12, frac: 0.9, branches: 94, leaves: 616, open: 586, blossoms: 12, fruits: 3, fireflies: 0, maxDepth: 5, traits: ['canopy', 'blossom', 'fruit', 'bird']),
      (level: 20, frac: 0.25, branches: 328, leaves: 1400, open: 875, blossoms: 13, fruits: 7, fireflies: 12, maxDepth: 6, traits: ['canopy', 'blossom', 'fruit', 'bird', 'twin', 'fireflies']),
    ];

    for (final f in fixtures) {
      test('matches the parity fixture at level ${f.level}', () {
        final scene = generateTree(
          seed: seed,
          level: f.level,
          frac: f.frac,
          health: 1,
        );

        expect(scene.branches.length, f.branches, reason: 'branches');
        expect(scene.leaves.length, f.leaves, reason: 'leaves');
        expect(
          scene.leaves.where((l) => l.open).length,
          f.open,
          reason: 'open leaves',
        );
        expect(scene.blossoms.length, f.blossoms, reason: 'blossoms');
        expect(scene.fruits.length, f.fruits, reason: 'fruits');
        expect(scene.fireflies.length, f.fireflies, reason: 'fireflies');
        expect(scene.maxDepth, f.maxDepth, reason: 'maxDepth');
        expect(
          scene.traits.map((t) => kTraitIds[t]).toList(),
          f.traits,
          reason: 'traits',
        );
      });
    }

    test('grows without ever finishing, and stays bounded', () {
      expect(growthForLevel(20), greaterThan(growthForLevel(10)));
      expect(growthForLevel(200), lessThan(1));
      expect(maxDepthForLevel(200), lessThanOrEqualTo(7));

      final huge = generateTree(seed: seed, level: 400, frac: 1, health: 1);
      expect(huge.branches.length, lessThanOrEqualTo(kMaxBranches));
      expect(huge.leaves.length, lessThanOrEqualTo(kMaxLeaves));
    });

    test('starts from the ground at the trunk', () {
      final scene = generateTree(seed: seed, level: 6, frac: 0.5);
      expect(scene.branches.first.y0, kGroundY);
      expect(scene.branches.first.x0, kTrunkX);
    });

    test('unfurls leaves as xp accumulates within a level', () {
      final empty = generateTree(seed: seed, level: 9, frac: 0);
      final full = generateTree(seed: seed, level: 9, frac: 1);
      expect(empty.leaves.length, full.leaves.length);
      expect(
        full.leaves.where((l) => l.open).length,
        greaterThan(empty.leaves.where((l) => l.open).length),
      );
      expect(full.leaves.every((l) => l.open), isTrue);
    });

    test('wilts by shedding a scatter of leaves, never the tree', () {
      final healthy = generateTree(seed: seed, level: 12, frac: 0.9, health: 1);
      final wilted = generateTree(seed: seed, level: 12, frac: 0.9, health: 0.3);

      expect(healthy.leaves.where((l) => l.visible).length, 616);
      expect(wilted.leaves.where((l) => l.visible).length, 416);
      // Same skeleton either way: wilting is never a smaller tree.
      expect(wilted.branches.length, healthy.branches.length);
      expect(wilted.level, healthy.level);

      // And the leaves that come back are the same ones, because hardiness is
      // seeded rather than rolled per render.
      final again = generateTree(seed: seed, level: 12, frac: 0.9, health: 0.3);
      expect(
        again.leaves.map((l) => l.visible).toList(),
        wilted.leaves.map((l) => l.visible).toList(),
      );
    });

    test('gives two different users two different trees at the same level', () {
      final mine = generateTree(seed: seed, level: 10, frac: 0.5);
      final yours = generateTree(
        seed: 'ffffffffffffffffffffffff',
        level: 10,
        frac: 0.5,
      );
      expect(mine.branches.first.x1, isNot(closeTo(yours.branches.first.x1, 1e-6)));
    });
  });

  group('traits and fruit', () {
    test('unlock in the documented order', () {
      expect(traitsForLevel(1), isEmpty);
      expect(traitsForLevel(3), [TreeTrait.canopy]);
      expect(traitsForLevel(12), [
        TreeTrait.canopy,
        TreeTrait.blossom,
        TreeTrait.fruit,
        TreeTrait.bird,
      ]);
      expect(traitsForLevel(25).length, kTraitOrder.length);
      expect(nextTrait(1)?.key, TreeTrait.canopy);
      expect(nextTrait(1)?.value, 3);
      expect(nextTrait(999), isNull);
      expect(traitAtLevel(16), TreeTrait.twin);
      expect(traitAtLevel(17), isNull);
    });

    test('hands out the nine vruchten one every second level from 8', () {
      expect(fruitCount(7), 0);
      expect(fruitCount(8), 1);
      expect(fruitCount(9), 1);
      expect(fruitCount(10), 2);
      expect(fruitCount(24), 9);
      expect(fruitCount(200), 9);

      expect(fruitsForLevel(10).map((f) => f.name).toList(), [
        'Liefde',
        'Blijdschap',
      ]);
      expect(fruitAtLevel(8)?.name, 'Liefde');
      expect(fruitAtLevel(9), isNull);
      expect(fruitAtLevel(24)?.name, 'Zelfbeheersing');
      expect(fruitAtLevel(26), isNull);
      expect(fruitsForLevel(24).first.reference, 'Galaten 5:22-23');
    });
  });

  group('palette', () {
    test('reads the device clock without touching geometry', () {
      expect(seasonForMonth(1), Season.winter);
      expect(seasonForMonth(4), Season.spring);
      expect(seasonForMonth(7), Season.summer);
      expect(seasonForMonth(10), Season.autumn);
      expect(timeOfDayForHour(3), DayPhase.night);
      expect(timeOfDayForHour(7), DayPhase.dawn);
      expect(timeOfDayForHour(13), DayPhase.day);
      expect(timeOfDayForHour(19), DayPhase.dusk);
    });

    test('desaturates a wilting canopy without changing the season', () {
      final healthy = buildPalette(Season.summer, DayPhase.day);
      final wilted = buildPalette(Season.summer, DayPhase.day, health: 0.3);
      expect(healthy.leaf, const Color(0xFF3F8F4F));
      expect(wilted.leaf, isNot(healthy.leaf));
      expect(buildPalette(Season.autumn, DayPhase.day).blossom, isNull);
      expect(buildPalette(Season.spring, DayPhase.night).night, isTrue);
    });
  });

  group('level-up chime', () {
    test('is a well-formed mono 16-bit WAV, and is built once', () {
      final wav = levelUpChimeWav();
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final header = ByteData.sublistView(wav);
      expect(header.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(header.getUint32(24, Endian.little), 44100);
      expect(header.getUint16(34, Endian.little), 16, reason: 'bit depth');
      // The declared data size has to match what is actually there, or a
      // player reads past the end and clicks.
      expect(header.getUint32(40, Endian.little), wav.length - 44);

      // Cached, so a run of level-ups does not re-synthesise 1.7s of audio.
      expect(identical(levelUpChimeWav(), wav), isTrue);
    });

    test('stays well under full scale - a chime, not an alert', () {
      final wav = levelUpChimeWav();
      final samples = ByteData.sublistView(wav, 44);
      var peak = 0;
      for (var i = 0; i + 1 < samples.lengthInBytes; i += 2) {
        final value = samples.getInt16(i, Endian.little).abs();
        if (value > peak) peak = value;
      }
      expect(peak, greaterThan(1000), reason: 'audible');
      expect(peak, lessThan(32767 ~/ 2), reason: 'never loud enough to startle');
    });
  });

  group('palette carries the season', () {
    test('so the renderer can draw the seasonal events without a clock', () {
      expect(buildPalette(Season.winter, DayPhase.day).season, Season.winter);
      expect(buildPalette(Season.spring, DayPhase.night).season, Season.spring);
    });
  });

  group('tree state', () {
    test('parses the gamification payload, tree block and all', () {
      final state = TreeState.fromJson({
        'xp': 2200,
        'level': 6,
        'xpIntoLevel': 700,
        'xpForNextLevel': 1500,
        'progressPercentage': 47,
        'streak': 12,
        'freezes': 2,
        'badges': ['streak30'],
        'levensboom': {
          'seed': seed,
          'health': 0.5,
          'wilting': true,
          'daysSinceActive': 3,
          'lastSeenLevel': 5,
          'traitsUnlocked': ['canopy', 'blossom'],
          'reducedMotion': true,
          'disabled': false,
        },
        'xpTable': [
          {'event': 'chapter_read', 'value': 5, 'label': 'Hoofdstuk gelezen'},
        ],
      });

      expect(state.seed, seed);
      expect(state.health, 0.5);
      expect(state.wilting, isTrue);
      expect(state.traitsUnlocked, [TreeTrait.canopy, TreeTrait.blossom]);
      expect(state.reducedMotion, isTrue);
      expect(state.shouldCelebrate, isTrue);
      expect(state.xpToNextLevel, 800);
      expect(state.xpTable.single.label, 'Hoofdstuk gelezen');
    });

    test('renders a grown tree for a server that has no tree block yet', () {
      final state = TreeState.fromJson({'xp': 2200, 'level': 6});
      expect(state.health, 1);
      expect(state.wilting, isFalse);
      // Nothing to celebrate: an absent marker means "already seen".
      expect(state.shouldCelebrate, isFalse);
      expect(state.traitsUnlocked, [TreeTrait.canopy, TreeTrait.blossom]);
    });

    test('applies an xp grant the way the server would', () {
      final before = TreeState.fromJson({
        'xp': 95,
        'level': 1,
        'xpIntoLevel': 95,
        'xpForNextLevel': 100,
        'levensboom': {'seed': seed, 'health': 0.5, 'wilting': true, 'daysSinceActive': 3},
      });

      final after = before.applyGrant(
        const XpGrant(xp: 120, level: 2, levelledUp: true, awarded: 25, newBadges: ['points100']),
      );

      expect(after.level, 2);
      expect(after.xpIntoLevel, 20);
      expect(after.xpForNextLevel, 200);
      // Earning XP means the reader is here today, so the tree perks back up.
      expect(after.health, 1);
      expect(after.wilting, isFalse);
      expect(after.badges, contains('points100'));
    });

    test('ignores a grant that awarded nothing', () {
      expect(XpGrant.fromJson({'awarded': 0, 'xp': 10, 'level': 1}), isNull);
      expect(XpGrant.fromJson(null), isNull);
      expect(XpGrant.fromJson({'awarded': 5, 'xp': 10, 'level': 1})?.awarded, 5);
    });
  });
}
