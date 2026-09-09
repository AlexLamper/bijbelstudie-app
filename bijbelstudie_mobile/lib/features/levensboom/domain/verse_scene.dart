import 'catalog.dart';
import 'palette.dart';
import 'rng.dart';
import 'scenes.dart';
import 'species.dart';

/// The landscape behind the daily verse, in the Levensboom's own hand.
///
/// Replaces the 76 stock photographs the dagtekst card used to carry
/// (`AVATAR_NOTIFICATIONS_PLAN.md` §6): one scene per calendar day, drawn by
/// the same painter that draws the tree's world, so the verse and the avatar
/// finally look like they come from the same app.
///
/// Seeded by the **date**, not by the account: everyone opening the app on the
/// same day sees the same landscape, which is what makes it shareable. The
/// palette is resolved separately, at paint time, so the scene still warms from
/// dawn to dusk while its shapes stay put.
class VerseScene {
  const VerseScene({
    required this.key,
    required this.sceneId,
    required this.species,
    required this.animal,
    required this.cloudSeed,
    required this.driftPhase,
  });

  /// `yyyymmdd` of the day this scene belongs to. Also the art cache's name.
  final String key;

  final TreeSceneId sceneId;

  /// Drives foliage and far-shape tints through [buildPalette] - the verse has
  /// no tree of its own, but the species decides what the distance is made of.
  final TreeSpecies species;

  /// Ground life. `geen` on roughly a third of days, so the scene can also be
  /// still.
  final TreeAnimal animal;

  /// 0..1, the cloud field's own stream.
  final double cloudSeed;

  /// 0..1, where the clouds start their crossing, so two consecutive days do
  /// not open on the same sky.
  final double driftPhase;

  Backdrop get backdrop => sceneSpec(sceneId).backdrop;

  /// The seed the tree-free scene and its decor are generated from.
  String get seed => 'verse:$key';
}

/// `yyyymmdd` for [day], local time. Matches `retentionDayKey()`'s shape.
String verseSceneKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}'
    '${day.month.toString().padLeft(2, '0')}'
    '${day.day.toString().padLeft(2, '0')}';

/// Ground life is thinned out: a landscape with an animal on it every single
/// day stops reading as a landscape.
const List<TreeAnimal> _animalPool = [
  TreeAnimal.geen,
  TreeAnimal.geen,
  TreeAnimal.vogel,
  TreeAnimal.vlinders,
  TreeAnimal.schaap,
  TreeAnimal.duif,
  TreeAnimal.hert,
  TreeAnimal.vuurvliegjes,
];

/// The scene for [day]. Deterministic: the same date gives the same scene on
/// every device and after a reinstall.
VerseScene verseSceneForDay(DateTime day) {
  final key = verseSceneKey(day);
  final rand = seededRng('verse-scene:$key');
  final sceneId = TreeSceneId.values[(rand() * TreeSceneId.values.length).floor() %
      TreeSceneId.values.length];
  final species = TreeSpecies.values[(rand() * TreeSpecies.values.length).floor() %
      TreeSpecies.values.length];
  var animal = _animalPool[(rand() * _animalPool.length).floor() % _animalPool.length];
  // Fireflies belong to a night sky; on a bright scene they are invisible work.
  if (animal == TreeAnimal.vuurvliegjes && !sceneSpec(sceneId).forceNight) {
    animal = TreeAnimal.vogel;
  }
  return VerseScene(
    key: key,
    sceneId: sceneId,
    species: species,
    animal: animal,
    cloudSeed: rand(),
    driftPhase: rand(),
  );
}

/// The colours [scene] wears at [at] - real season, real hour, so the card
/// warms through the day and the scene still belongs to its date.
TreePalette verseScenePalette(VerseScene scene, {DateTime? at}) {
  final now = at ?? DateTime.now();
  return buildPalette(
    seasonForMonth(now.month),
    timeOfDayForHour(now.hour),
    scene: scene.sceneId,
    species: scene.species,
  );
}
