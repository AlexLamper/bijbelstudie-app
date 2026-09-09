import 'package:bijbelstudie_mobile/features/levensboom/domain/catalog.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/scenes.dart';
import 'package:bijbelstudie_mobile/features/levensboom/domain/verse_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// The daily verse's landscape (`AVATAR_NOTIFICATIONS_PLAN.md` §6). It replaced
/// 76 photographs, so the two things that used to be free - "the same picture
/// all day" and "a different one tomorrow" - now have to be asserted.
void main() {
  group('verseSceneForDay', () {
    test('is the same scene all day, on every device', () {
      final morning = verseSceneForDay(DateTime(2026, 3, 14, 6, 5));
      final evening = verseSceneForDay(DateTime(2026, 3, 14, 23, 55));

      expect(morning.key, '20260314');
      expect(evening.key, morning.key);
      expect(evening.sceneId, morning.sceneId);
      expect(evening.species, morning.species);
      expect(evening.animal, morning.animal);
      expect(evening.cloudSeed, morning.cloudSeed);
      expect(evening.driftPhase, morning.driftPhase);
    });

    test('keeps moving: a month is not two or three looks', () {
      final looks = <String>{};
      for (var day = 0; day < 30; day++) {
        final scene = verseSceneForDay(DateTime(2026, 1, 1).add(Duration(days: day)));
        looks.add('${scene.sceneId}/${scene.species}');
      }
      expect(looks.length, greaterThanOrEqualTo(12));
    });

    test('consecutive days do not repeat the scene', () {
      var repeats = 0;
      for (var day = 0; day < 60; day++) {
        final a = verseSceneForDay(DateTime(2026, 1, 1).add(Duration(days: day)));
        final b = verseSceneForDay(DateTime(2026, 1, 2).add(Duration(days: day)));
        if (a.sceneId == b.sceneId) repeats++;
      }
      // Eight scenes drawn independently repeat about one day in eight; twice
      // that would mean the stream is not actually moving.
      expect(repeats, lessThan(15));
    });

    test('fireflies only ever appear on a night scene', () {
      for (var day = 0; day < 365; day++) {
        final scene = verseSceneForDay(DateTime(2026, 1, 1).add(Duration(days: day)));
        if (scene.animal == TreeAnimal.vuurvliegjes) {
          expect(sceneSpec(scene.sceneId).forceNight, isTrue,
              reason: 'fireflies on a daylit scene are invisible work');
        }
      }
    });

    test('the seed is the date, so the art cache can be named after it', () {
      final scene = verseSceneForDay(DateTime(2026, 12, 5));
      expect(scene.key, '20261205');
      expect(scene.seed, 'verse:20261205');
      expect(verseSceneKey(DateTime(2026, 12, 5, 13, 30)), '20261205');
    });
  });

  group('verseScenePalette', () {
    test('warms through the day while the scene stays put', () {
      final scene = verseSceneForDay(DateTime(2026, 6, 21));
      final noon = verseScenePalette(scene, at: DateTime(2026, 6, 21, 12));
      final night = verseScenePalette(scene, at: DateTime(2026, 6, 21, 23));

      expect(noon.scene, night.scene);
      // A forced-night scene is night at noon too; every other one changes.
      if (!sceneSpec(scene.sceneId).forceNight) {
        expect(night.night, isTrue);
        expect(noon.night, isFalse);
      }
    });
  });
}
