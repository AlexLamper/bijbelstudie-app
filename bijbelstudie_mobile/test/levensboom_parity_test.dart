import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/features/levensboom/domain/catalog.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/chime.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/palette.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/rng.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/scenes.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/species.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/stages.dart';
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
    const levels = [(1, 0.0), (3, 0.5), (6, 0.4), (10, 0.9), (18, 0.25)];

    // branches, leaves, open, blossoms, fruits, maxDepth - one row per level.
    const counts = <TreeSpecies, List<(int, int, int, int, int, int)>>{
      TreeSpecies.eik: [
        (1, 2, 1, 0, 0, 0),
        (8, 35, 27, 0, 0, 2),
        (22, 114, 80, 11, 0, 3),
        (39, 217, 207, 12, 2, 4),
        (131, 848, 530, 13, 6, 5),
      ],
      TreeSpecies.olijf: [
        (1, 2, 1, 0, 0, 0),
        (8, 35, 27, 0, 0, 2),
        (25, 154, 108, 11, 0, 3),
        (57, 392, 373, 12, 2, 4),
        (210, 1400, 875, 13, 6, 5),
      ],
      TreeSpecies.vijg: [
        (1, 2, 1, 0, 0, 0),
        (8, 21, 16, 0, 0, 2),
        (20, 51, 36, 0, 0, 3),
        (48, 160, 152, 0, 2, 4),
        (223, 752, 470, 0, 6, 5),
      ],
      TreeSpecies.palm: [
        (1, 2, 1, 0, 0, 0),
        (3, 6, 5, 0, 0, 2),
        (4, 8, 6, 0, 0, 3),
        (5, 9, 9, 0, 2, 4),
        (12, 20, 13, 0, 6, 5),
      ],
      TreeSpecies.amandel: [
        (1, 2, 1, 1, 0, 0),
        (8, 28, 21, 4, 0, 2),
        (22, 114, 80, 11, 0, 3),
        (47, 234, 223, 12, 2, 4),
        (196, 1155, 722, 13, 6, 5),
      ],
      TreeSpecies.ceder: [
        (1, 2, 1, 0, 0, 0),
        (12, 66, 50, 0, 0, 2),
        (34, 210, 147, 0, 0, 3),
        (95, 738, 702, 0, 2, 4),
        (308, 1400, 875, 0, 6, 5),
      ],
    };

    const traitsByLevel = <int, List<String>>{
      1: [],
      3: [],
      6: ['blossom'],
      10: ['blossom', 'fruit'],
      18: ['blossom', 'fruit', 'twin'],
    };

    for (final entry in counts.entries) {
      for (var i = 0; i < levels.length; i++) {
        final (level, frac) = levels[i];
        final (branches, leaves, open, blossoms, fruits, maxDepth) = entry.value[i];
        test('matches the parity fixture for ${kSpeciesIds[entry.key]} at level $level', () {
          final scene = generateTree(
            seed: seed,
            level: level,
            frac: frac,
            health: 1,
            species: entry.key,
          );

          expect(scene.branches.length, branches, reason: 'branches');
          expect(scene.leaves.length, leaves, reason: 'leaves');
          expect(scene.leaves.where((l) => l.open).length, open, reason: 'open leaves');
          expect(scene.blossoms.length, blossoms, reason: 'blossoms');
          expect(scene.fruits.length, fruits, reason: 'fruits');
          expect(scene.maxDepth, maxDepth, reason: 'maxDepth');
          expect(scene.species, entry.key);
          expect(
            scene.traits.map((t) => kTraitIds[t]).toList(),
            traitsByLevel[level],
            reason: 'traits',
          );
        });
      }
    }

    test('starts as a kiem: one stem, two leaves, nothing else', () {
      final kiem = generateTree(seed: seed, level: 1, frac: 0);
      expect(growthForLevel(1), 0);
      expect(maxDepthForLevel(1), 0);
      expect(kiem.branches, hasLength(1));
      expect(kiem.leaves, hasLength(2));
      expect(kiem.leaves[0].x, lessThan(50));
      expect(kiem.leaves[1].x, greaterThan(50));
    });

    test('grows without ever finishing, and stays bounded', () {
      expect(growthForLevel(20), greaterThan(growthForLevel(10)));
      expect(growthForLevel(200), lessThan(1));
      expect(maxDepthForLevel(200), lessThanOrEqualTo(7));

      for (final species in TreeSpecies.values) {
        final huge = generateTree(seed: seed, level: 400, frac: 1, health: 1, species: species);
        expect(huge.branches.length, lessThanOrEqualTo(kMaxBranches));
        expect(huge.leaves.length, lessThanOrEqualTo(kMaxLeaves));
      }
    });

    test('starts from the ground at the trunk, and the bounds include the earth', () {
      final scene = generateTree(seed: seed, level: 6, frac: 0.5);
      expect(scene.branches.first.y0, kGroundY);
      expect(scene.branches.first.x0, kTrunkX);
      expect(scene.bounds.maxY, 96);
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
      final healthy = generateTree(seed: seed, level: 10, frac: 0.9, health: 1);
      final wilted = generateTree(seed: seed, level: 10, frac: 0.9, health: 0.3);

      expect(healthy.leaves.where((l) => l.visible).length, 217);
      expect(wilted.leaves.where((l) => l.visible).length, 156);
      // Same skeleton either way: wilting is never a smaller tree.
      expect(wilted.branches.length, healthy.branches.length);
      expect(wilted.level, healthy.level);

      // And the leaves that come back are the same ones, because hardiness is
      // seeded rather than rolled per render.
      final again = generateTree(seed: seed, level: 10, frac: 0.9, health: 0.3);
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

    test('always offers a perch, so a picked bird has somewhere to sit', () {
      expect(generateTree(seed: seed, level: 5, frac: 0.5).perch, isNotNull);
    });
  });

  group('stages', () {
    test('map levels onto the five named bands', () {
      expect(kStages.map((s) => s.from).toList(), [1, 2, 4, 8, 16]);
      expect(stageForLevel(1).stage, TreeStage.kiem);
      expect(stageForLevel(3).stage, TreeStage.zaailing);
      expect(stageForLevel(4).stage, TreeStage.jongeBoom);
      expect(stageForLevel(8).stage, TreeStage.volwassenBoom);
      expect(stageForLevel(16).stage, TreeStage.eeuwenoudeBoom);
      expect(stageForLevel(400).stage, TreeStage.eeuwenoudeBoom);
      expect(stageForLevel(5).to, 7);
      expect(stageForLevel(5).nextLevel, 8);
      expect(stageForLevel(5).nextName, 'Volwassen boom');
      expect(stageForLevel(20).nextLevel, isNull);
      expect(stageById('jonge_boom')?.name, 'Jonge boom');
    });
  });

  group('catalog', () {
    const fresh = UnlockContext(level: 1, badges: [], longestStreak: 0, isPro: false);

    test('gives a new account exactly the free items', () {
      expect(unlockedKeys(fresh), {
        'species:eik',
        'species:olijf',
        'scene:waterbeken',
        'animal:geen',
        'ring:teal',
      });
    });

    test('unlocks by level, streak, badge and Pro independently', () {
      final level8 = unlockedKeys(const UnlockContext(level: 8, badges: [], longestStreak: 0, isPro: false));
      expect(level8, containsAll(['species:vijg', 'species:palm', 'scene:heuvels', 'scene:meer', 'animal:vogel', 'animal:vlinders']));
      expect(level8, isNot(contains('species:amandel')));

      final streak30 = unlockedKeys(const UnlockContext(level: 1, badges: [], longestStreak: 30, isPro: false));
      expect(streak30, containsAll(['scene:woestijn', 'scene:berg', 'animal:duif']));
      expect(streak30, isNot(contains('animal:hert')));

      expect(
        unlockedKeys(const UnlockContext(level: 1, badges: ['completed5'], longestStreak: 0, isPro: false)),
        contains('scene:stadsmuur'),
      );
      final pro = unlockedKeys(const UnlockContext(level: 1, badges: [], longestStreak: 0, isPro: true));
      expect(pro, containsAll(['species:ceder', 'scene:hof', 'scene:sterrennacht', 'ring:goud']));
    });

    test('falls back to defaults for anything the account is not entitled to', () {
      const chosen = AvatarChoice(
        species: TreeSpecies.ceder,
        scene: TreeSceneId.hof,
        animal: TreeAnimal.duif,
        ring: TreeRing.goud,
      );
      expect(resolveAvatar(chosen, unlockedKeys(fresh)), AvatarChoice.defaults);
      expect(
        resolveAvatar(
          chosen,
          unlockedKeys(const UnlockContext(level: 1, badges: [], longestStreak: 14, isPro: true)),
        ),
        chosen,
      );
      expect(AvatarChoice.fromJson({'species': 'baobab'}), AvatarChoice.defaults);
      expect(AvatarChoice.fromJson(chosen.toJson()), chosen);
      expect(chosen.withItem(ItemKind.scene, 'meer').scene, TreeSceneId.meer);
      expect(chosen.idFor(ItemKind.ring), 'goud');
    });

    test('labels every rule in Dutch and finds the next level unlock', () {
      expect(unlockLabel(const LevelUnlock(8)), 'Niveau 8');
      expect(unlockLabel(const StreakUnlock(14)), 'Reeks van 14 dagen');
      expect(unlockLabel(const BadgeUnlock('completed5', '5 studies voltooid')), '5 studies voltooid');
      expect(unlockLabel(const ProUnlock()), 'Pro');
      expect(nextLevelUnlock(const UnlockContext(level: 5, badges: [], longestStreak: 0, isPro: false))?.id, 'meer');
      expect(nextLevelUnlock(const UnlockContext(level: 15, badges: [], longestStreak: 0, isPro: false)), isNull);
      expect(itemsUnlockedAtLevel(8).map((i) => i.id).toList(), ['palm']);
    });

    test('has unique keys', () {
      final keys = kCatalog.map((item) => item.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(kCatalog.length, 23);
    });
  });

  group('traits and fruit', () {
    test('unlock in the documented order', () {
      expect(traitsForLevel(1), isEmpty);
      expect(traitsForLevel(4), isEmpty);
      expect(traitsForLevel(5), [TreeTrait.blossom]);
      expect(traitsForLevel(12), [TreeTrait.blossom, TreeTrait.fruit]);
      expect(traitsForLevel(25).length, kTraitOrder.length);
      expect(nextTrait(1)?.key, TreeTrait.blossom);
      expect(nextTrait(1)?.value, 5);
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

    test('lets evergreens keep their green and a scene force the night', () {
      expect(
        buildPalette(Season.autumn, DayPhase.day, species: TreeSpecies.olijf).leaf,
        isNot(const Color(0xFFC9772E)),
      );
      expect(
        buildPalette(Season.autumn, DayPhase.day, species: TreeSpecies.vijg).leaf,
        const Color(0xFFC9772E),
      );
      expect(
        buildPalette(Season.summer, DayPhase.day, species: TreeSpecies.ceder).leaf,
        const Color(0xFF2F6B4F),
      );
      final night = buildPalette(Season.summer, DayPhase.day, scene: TreeSceneId.sterrennacht);
      expect(night.night, isTrue);
      expect(night.timeOfDay, DayPhase.night);
      expect(night.scene, TreeSceneId.sterrennacht);
      expect(
        buildPalette(Season.summer, DayPhase.day, scene: TreeSceneId.woestijn).ground,
        const Color(0xFFD9B77A),
      );
      expect(
        buildPalette(Season.spring, DayPhase.day, species: TreeSpecies.amandel).blossom,
        const Color(0xFFFBD3E0),
      );
    });

    test('carries the season so the renderer can draw seasonal events', () {
      expect(buildPalette(Season.winter, DayPhase.day).season, Season.winter);
      expect(buildPalette(Season.spring, DayPhase.night).season, Season.spring);
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
          'traitsUnlocked': ['blossom'],
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
      expect(state.traitsUnlocked, [TreeTrait.blossom]);
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
      expect(state.traitsUnlocked, [TreeTrait.blossom]);
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

    test('parses the studio block and keeps chosen apart from what is drawn', () {
      final state = TreeState.fromJson({
        'xp': 2800,
        'level': 8,
        'badges': ['completed1'],
        'streak': 3,
        'levensboom': {
          'seed': seed,
          'chosen': {'species': 'ceder', 'scene': 'hof', 'animal': 'schaap', 'ring': 'goud'},
          'avatar': {'species': 'eik', 'scene': 'waterbeken', 'animal': 'schaap', 'ring': 'teal'},
          'unlocked': ['species:eik', 'species:olijf', 'species:vijg', 'species:palm', 'animal:schaap'],
          'nextUnlock': {'kind': 'species', 'id': 'amandel', 'name': 'Amandelboom', 'level': 12},
          'longestStreak': 14,
          'planted': true,
          'introSeen': false,
          'publicProfile': true,
          'seenItems': ['species:vijg'],
        },
      });

      expect(state.chosen.species, TreeSpecies.ceder);
      expect(state.avatar.species, TreeSpecies.eik);
      expect(state.avatar.animal, TreeAnimal.schaap);
      expect(state.unlocked, contains('species:palm'));
      expect(state.isProUnlocked, isFalse);
      expect(state.nextUnlock?.id, 'amandel');
      expect(state.stage.stage, TreeStage.volwassenBoom);
      expect(state.longestStreak, 14);
      expect(state.planted, isTrue);
      expect(state.publicProfile, isTrue);
      expect(state.seenItems, {'species:vijg'});

      // The cache round-trips every studio field.
      final again = TreeState.fromJson(state.toJson());
      expect(again.chosen, state.chosen);
      expect(again.avatar, state.avatar);
      expect(again.unlocked, state.unlocked);
      expect(again.seenItems, state.seenItems);

      // A PATCH answer replaces the block and nothing else.
      final merged = state.mergeTree({
        ...((state.toJson()['levensboom'] as Map).cast<String, dynamic>()),
        'avatar': {'species': 'palm', 'scene': 'waterbeken', 'animal': 'schaap', 'ring': 'teal'},
        'chosen': {'species': 'palm', 'scene': 'waterbeken', 'animal': 'schaap', 'ring': 'teal'},
      });
      expect(merged.avatar.species, TreeSpecies.palm);
      expect(merged.xp, 2800);
      expect(merged.badges, ['completed1']);
    });

    test('derives the unlocks itself for a server without the studio block', () {
      final state = TreeState.fromJson({
        'xp': 4500,
        'level': 10,
        'badges': ['completed5', 'premium'],
        'streak': 7,
        'levensboom': {'seed': seed},
      });
      expect(state.unlocked, containsAll(['species:palm', 'scene:stadsmuur', 'scene:woestijn', 'ring:goud']));
      expect(state.unlocked, isNot(contains('species:amandel')));
      expect(state.avatar, AvatarChoice.defaults);
    });
  });
}
