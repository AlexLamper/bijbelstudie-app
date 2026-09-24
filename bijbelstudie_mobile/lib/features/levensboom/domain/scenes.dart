/// The fifteen omgevingen the tree can stand in. Mirror of the website's
/// `lib/levensboom/scenes.ts`; the table is `docs/levensboom-spec.md` §7.2.
///
/// A scene is colour plus a backdrop the renderer draws behind the tree. It is
/// never a generator input: the branches and leaves of a tree are the same in
/// every scene, which is what lets the studio preview a scene by repainting
/// rather than regenerating, and what keeps the parity fixtures scene-free.
library;

import 'package:flutter/painting.dart';

import 'palette.dart';

/// Same ids, same order as the website's `SCENE_IDS`.
enum TreeSceneId {
  waterbeken,
  heuvels,
  meer,
  woestijn,
  berg,
  stadsmuur,
  hof,
  sterrennacht,
  jordaan,
  wijngaard,
  graanveld,
  kust,
  regenboog,
  dageraad,
  herdersveld,
}

const TreeSceneId kDefaultScene = TreeSceneId.waterbeken;

const Map<TreeSceneId, String> kSceneIds = {
  TreeSceneId.waterbeken: 'waterbeken',
  TreeSceneId.heuvels: 'heuvels',
  TreeSceneId.meer: 'meer',
  TreeSceneId.woestijn: 'woestijn',
  TreeSceneId.berg: 'berg',
  TreeSceneId.stadsmuur: 'stadsmuur',
  TreeSceneId.hof: 'hof',
  TreeSceneId.sterrennacht: 'sterrennacht',
  TreeSceneId.jordaan: 'jordaan',
  TreeSceneId.wijngaard: 'wijngaard',
  TreeSceneId.graanveld: 'graanveld',
  TreeSceneId.kust: 'kust',
  TreeSceneId.regenboog: 'regenboog',
  TreeSceneId.dageraad: 'dageraad',
  TreeSceneId.herdersveld: 'herdersveld',
};

TreeSceneId sceneFromId(String? id) {
  for (final entry in kSceneIds.entries) {
    if (entry.value == id) return entry.key;
  }
  return kDefaultScene;
}

/// What the renderer paints behind the tree. One routine per value.
enum Backdrop {
  meadow,
  hills,
  lake,
  dunes,
  mountain,
  wall,
  garden,
  stars,
  river,
  vineyard,
  field,
  sea,
  rainbow,
  sunrise,
  shepherds,
}

class SkyStops {
  const SkyStops(this.top, this.bottom, this.glow, this.light);

  final Color top, bottom, glow, light;
}

class SceneSpec {
  const SceneSpec({
    required this.id,
    required this.name,
    required this.backdrop,
    this.sky = const {},
    this.groundTop,
    this.groundBottom,
    required this.far,
    required this.farAlt,
    this.water,
    required this.accent,
    this.forceTime,
  });

  final TreeSceneId id;
  final String name;
  final Backdrop backdrop;

  /// Per-time-of-day sky overrides; anything missing keeps the default sky.
  final Map<DayPhase, SkyStops> sky;

  /// Ground band colours. `null` keeps the seasonal ground.
  final Color? groundTop;
  final Color? groundBottom;

  /// Distant shapes: hills, dunes, the range, the wall.
  final Color far;
  final Color farAlt;

  /// Water, where the scene has any.
  final Color? water;

  /// Small colour accents: flowers, the sail, reflections.
  final Color accent;

  /// Pins the time of day whatever the clock says: the starry night, the
  /// dawn. `null` follows the clock.
  final DayPhase? forceTime;

  /// Always night, whatever the clock says.
  bool get forceNight => forceTime == DayPhase.night;
}

const Map<TreeSceneId, SceneSpec> kScenes = {
  TreeSceneId.waterbeken: SceneSpec(
    id: TreeSceneId.waterbeken,
    name: 'Waterbeken',
    backdrop: Backdrop.meadow,
    far: Color(0xFF5E8C57),
    farAlt: Color(0xFF4E7C49),
    water: Color(0xFF5FA8C8),
    accent: Color(0xFFDFF3F7),
  ),
  TreeSceneId.heuvels: SceneSpec(
    id: TreeSceneId.heuvels,
    name: 'Heuvels van Galilea',
    backdrop: Backdrop.hills,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF8FCBE6),
        Color(0xFFF0E9D2),
        Color(0xFFFFF1C9),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFF7C9B4A),
    groundBottom: Color(0xFF5C7433),
    far: Color(0xFF8FA86A),
    farAlt: Color(0xFF6F8C52),
    accent: Color(0xFF4F6B3A),
  ),
  TreeSceneId.meer: SceneSpec(
    id: TreeSceneId.meer,
    name: 'Meer van Galilea',
    backdrop: Backdrop.lake,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF79BEE0),
        Color(0xFFE6F4FA),
        Color(0xFFFFF6DE),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFF8A9A62),
    groundBottom: Color(0xFF6B7A46),
    far: Color(0xFF7FA3B8),
    farAlt: Color(0xFF6B8FA6),
    water: Color(0xFF4F9CC4),
    accent: Color(0xFFF4EFE2),
  ),
  TreeSceneId.woestijn: SceneSpec(
    id: TreeSceneId.woestijn,
    name: 'Woestijn-oase',
    backdrop: Backdrop.dunes,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF8FC3E8),
        Color(0xFFF6E3C0),
        Color(0xFFFFEAB8),
        Color(0xFFFFFFFF),
      ),
      DayPhase.dusk: SkyStops(
        Color(0xFF5A3E6E),
        Color(0xFFF0A56B),
        Color(0xFFFFC98A),
        Color(0xFFFFE0B8),
      ),
    },
    groundTop: Color(0xFFD9B77A),
    groundBottom: Color(0xFFB48F55),
    far: Color(0xFFE2C48C),
    farAlt: Color(0xFFC9A467),
    water: Color(0xFF5AA9C8),
    accent: Color(0xFF7FB069),
  ),
  TreeSceneId.berg: SceneSpec(
    id: TreeSceneId.berg,
    name: 'De berg',
    backdrop: Backdrop.mountain,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF6FAED6),
        Color(0xFFDCEBF3),
        Color(0xFFF4F7FB),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFF6F7F5C),
    groundBottom: Color(0xFF55634A),
    far: Color(0xFF6E7C90),
    farAlt: Color(0xFF8A96A6),
    accent: Color(0xFFF4F7FB),
  ),
  TreeSceneId.stadsmuur: SceneSpec(
    id: TreeSceneId.stadsmuur,
    name: 'Stadsmuur',
    backdrop: Backdrop.wall,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF86C0E0),
        Color(0xFFF3E6CF),
        Color(0xFFFFEFCF),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFFB8A275),
    groundBottom: Color(0xFF8E7A52),
    far: Color(0xFFC9B189),
    farAlt: Color(0xFFA8905F),
    accent: Color(0xFF7A6444),
  ),
  TreeSceneId.hof: SceneSpec(
    id: TreeSceneId.hof,
    name: 'De hof',
    backdrop: Backdrop.garden,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF8ED0E8),
        Color(0xFFE9F7EA),
        Color(0xFFFFF7DA),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFF4E9A4F),
    groundBottom: Color(0xFF3B7A3D),
    far: Color(0xFF3F8A5A),
    farAlt: Color(0xFF2F6B48),
    water: Color(0xFF5FB0CC),
    accent: Color(0xFFF28CB1),
  ),
  TreeSceneId.sterrennacht: SceneSpec(
    id: TreeSceneId.sterrennacht,
    name: 'Sterrennacht',
    backdrop: Backdrop.stars,
    sky: {
      DayPhase.night: SkyStops(
        Color(0xFF060A1C),
        Color(0xFF1B2450),
        Color(0xFF3C4B86),
        Color(0xFFDCE4FF),
      ),
    },
    groundTop: Color(0xFF2B3550),
    groundBottom: Color(0xFF1A2138),
    far: Color(0xFF141B36),
    farAlt: Color(0xFF1E2747),
    accent: Color(0xFFF5F0C8),
    forceTime: DayPhase.night,
  ),
  TreeSceneId.jordaan: SceneSpec(
    id: TreeSceneId.jordaan,
    name: 'De Jordaan',
    backdrop: Backdrop.river,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF84C4E4),
        Color(0xFFEAF3E6),
        Color(0xFFFFF4D6),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFF7FA25A),
    groundBottom: Color(0xFF5E7A3E),
    far: Color(0xFF7FA86C),
    farAlt: Color(0xFF628A55),
    water: Color(0xFF4F9CC4),
    accent: Color(0xFFC9E2B0),
  ),
  TreeSceneId.wijngaard: SceneSpec(
    id: TreeSceneId.wijngaard,
    name: 'Wijngaard',
    backdrop: Backdrop.vineyard,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF8CC6E4),
        Color(0xFFF4E9CF),
        Color(0xFFFFF1C9),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFF8E7A4E),
    groundBottom: Color(0xFF6B5A36),
    far: Color(0xFF8FA65E),
    farAlt: Color(0xFF6E8A48),
    accent: Color(0xFF5B3A6E),
  ),
  TreeSceneId.graanveld: SceneSpec(
    id: TreeSceneId.graanveld,
    name: 'Graanveld',
    backdrop: Backdrop.field,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF8EC8E8),
        Color(0xFFF8ECC8),
        Color(0xFFFFF0BE),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFFD8B85E),
    groundBottom: Color(0xFFB08F3E),
    far: Color(0xFFD9BE6A),
    farAlt: Color(0xFFB79A4E),
    accent: Color(0xFFF2D98A),
  ),
  TreeSceneId.kust: SceneSpec(
    id: TreeSceneId.kust,
    name: 'De kust',
    backdrop: Backdrop.sea,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF6FB6E0),
        Color(0xFFE3F1F7),
        Color(0xFFFFF6DE),
        Color(0xFFFFFFFF),
      ),
    },
    groundTop: Color(0xFFE4D3A6),
    groundBottom: Color(0xFFC4AE7C),
    far: Color(0xFF3F86B0),
    farAlt: Color(0xFF5FA3C8),
    water: Color(0xFF3F86B0),
    accent: Color(0xFFF4F8FA),
  ),
  TreeSceneId.regenboog: SceneSpec(
    id: TreeSceneId.regenboog,
    name: 'Regenboog',
    backdrop: Backdrop.rainbow,
    sky: {
      DayPhase.day: SkyStops(
        Color(0xFF7CB9DC),
        Color(0xFFDDEBEF),
        Color(0xFFFFF4D6),
        Color(0xFFFFFFFF),
      ),
    },
    far: Color(0xFF5E8C57),
    farAlt: Color(0xFF4E7C49),
    accent: Color(0xFFF4F7FB),
  ),
  TreeSceneId.dageraad: SceneSpec(
    id: TreeSceneId.dageraad,
    name: 'Dageraad',
    backdrop: Backdrop.sunrise,
    sky: {
      DayPhase.dawn: SkyStops(
        Color(0xFF3A4A73),
        Color(0xFFF9C89A),
        Color(0xFFFFD9A0),
        Color(0xFFFFE8CC),
      ),
    },
    groundTop: Color(0xFF7A7F55),
    groundBottom: Color(0xFF585E3E),
    far: Color(0xFF5C5A7A),
    farAlt: Color(0xFF7B6E8E),
    accent: Color(0xFFFFD27A),
    forceTime: DayPhase.dawn,
  ),
  TreeSceneId.herdersveld: SceneSpec(
    id: TreeSceneId.herdersveld,
    name: 'Velden van Efratha',
    backdrop: Backdrop.shepherds,
    sky: {
      DayPhase.night: SkyStops(
        Color(0xFF0A1030),
        Color(0xFF26305A),
        Color(0xFF4A5A96),
        Color(0xFFE2E8FF),
      ),
    },
    groundTop: Color(0xFF33405A),
    groundBottom: Color(0xFF1F283E),
    far: Color(0xFF1A2340),
    farAlt: Color(0xFF26304F),
    accent: Color(0xFFFFF3C4),
    forceTime: DayPhase.night,
  ),
};

SceneSpec sceneSpec(TreeSceneId id) => kScenes[id]!;
