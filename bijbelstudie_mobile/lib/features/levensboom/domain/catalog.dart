/// What the reader can pick for their tree, and what each pick costs in
/// progress. Mirror of the website's `lib/levensboom/catalog.ts`; the table is
/// `docs/levensboom-spec.md` §9 and the three copies must agree.
///
/// Nothing about an unlock is ever stored. [unlockedKeys] is a pure function of
/// what the account already records, and the server re-checks every PATCH -
/// this copy exists so tiles can show their lock state and the stage can
/// preview a pick without a round trip.
library;

import 'scenes.dart';
import 'species.dart';

const int kCatalogVersion = 1;

enum TreeAnimal { geen, vogel, vlinders, schaap, duif, vuurvliegjes, hert }

const TreeAnimal kDefaultAnimal = TreeAnimal.geen;

const Map<TreeAnimal, String> kAnimalIds = {
  TreeAnimal.geen: 'geen',
  TreeAnimal.vogel: 'vogel',
  TreeAnimal.vlinders: 'vlinders',
  TreeAnimal.schaap: 'schaap',
  TreeAnimal.duif: 'duif',
  TreeAnimal.vuurvliegjes: 'vuurvliegjes',
  TreeAnimal.hert: 'hert',
};

TreeAnimal animalFromId(String? id) {
  for (final entry in kAnimalIds.entries) {
    if (entry.value == id) return entry.key;
  }
  return kDefaultAnimal;
}

enum TreeRing { teal, goud }

const TreeRing kDefaultRing = TreeRing.teal;

const Map<TreeRing, String> kRingIds = {
  TreeRing.teal: 'teal',
  TreeRing.goud: 'goud',
};

TreeRing ringFromId(String? id) {
  for (final entry in kRingIds.entries) {
    if (entry.value == id) return entry.key;
  }
  return kDefaultRing;
}

enum ItemKind { species, scene, animal, ring }

const Map<ItemKind, String> kItemKindIds = {
  ItemKind.species: 'species',
  ItemKind.scene: 'scene',
  ItemKind.animal: 'animal',
  ItemKind.ring: 'ring',
};

sealed class Unlock {
  const Unlock();
}

final class FreeUnlock extends Unlock {
  const FreeUnlock();
}

final class LevelUnlock extends Unlock {
  const LevelUnlock(this.level);

  final int level;
}

final class StreakUnlock extends Unlock {
  const StreakUnlock(this.days);

  final int days;
}

final class BadgeUnlock extends Unlock {
  const BadgeUnlock(this.badge, this.label);

  final String badge;
  final String label;
}

final class ProUnlock extends Unlock {
  const ProUnlock();
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.blurb,
    this.verse,
    required this.unlock,
  });

  final String id;
  final ItemKind kind;
  final String name;

  /// One line under the name in the studio.
  final String blurb;

  /// The verse the item borrows its meaning from, where it has one.
  final String? verse;
  final Unlock unlock;

  /// `kind:id`, so two kinds can never collide on an id.
  String get key => '${kItemKindIds[kind]}:$id';
}

const List<CatalogItem> kCatalog = [
  // Boomsoorten
  CatalogItem(id: 'eik', kind: ItemKind.species, name: 'Eik', blurb: 'Breed en sterk, met eikels in de herfst.', verse: 'Genesis 18:1', unlock: FreeUnlock()),
  CatalogItem(id: 'olijf', kind: ItemKind.species, name: 'Olijfboom', blurb: 'Knoestig en altijd groen.', verse: 'Psalm 52:10', unlock: FreeUnlock()),
  CatalogItem(id: 'vijg', kind: ItemKind.species, name: 'Vijgenboom', blurb: 'Laag en wijd, met grote bladeren.', verse: 'Micha 4:4', unlock: LevelUnlock(4)),
  CatalogItem(id: 'palm', kind: ItemKind.species, name: 'Palmboom', blurb: 'Eén hoge stam en een kroon van bladeren.', verse: 'Psalm 92:13', unlock: LevelUnlock(8)),
  CatalogItem(id: 'amandel', kind: ItemKind.species, name: 'Amandelboom', blurb: 'Bloeit als eerste, ieder voorjaar.', verse: 'Jeremia 1:11', unlock: LevelUnlock(12)),
  CatalogItem(id: 'ceder', kind: ItemKind.species, name: 'Ceder van de Libanon', blurb: 'Hoog en kegelvormig, altijd groen.', verse: 'Psalm 92:13', unlock: ProUnlock()),

  // Omgevingen
  CatalogItem(id: 'waterbeken', kind: ItemKind.scene, name: 'Waterbeken', blurb: 'Een beek langs de wortels.', verse: 'Psalm 1:3', unlock: FreeUnlock()),
  CatalogItem(id: 'heuvels', kind: ItemKind.scene, name: 'Heuvels van Galilea', blurb: 'Glooiende heuvels met olijfgaarden.', unlock: LevelUnlock(3)),
  CatalogItem(id: 'meer', kind: ItemKind.scene, name: 'Meer van Galilea', blurb: 'De oever, met een bootje op het water.', unlock: LevelUnlock(6)),
  CatalogItem(id: 'woestijn', kind: ItemKind.scene, name: 'Woestijn-oase', blurb: 'Zand, warmte en een bron.', verse: 'Jesaja 35:1', unlock: StreakUnlock(7)),
  CatalogItem(id: 'berg', kind: ItemKind.scene, name: 'De berg', blurb: 'Rotsen en een verre bergketen.', verse: 'Psalm 121:1', unlock: StreakUnlock(30)),
  CatalogItem(id: 'stadsmuur', kind: ItemKind.scene, name: 'Stadsmuur', blurb: 'Onder de muren van Jeruzalem.', verse: 'Psalm 122', unlock: BadgeUnlock('completed5', '5 studies voltooid')),
  CatalogItem(id: 'hof', kind: ItemKind.scene, name: 'De hof', blurb: 'Een tuin met bloemen en een rivier.', verse: 'Genesis 2:8', unlock: ProUnlock()),
  CatalogItem(id: 'sterrennacht', kind: ItemKind.scene, name: 'Sterrennacht', blurb: 'Kijk omhoog en tel de sterren.', verse: 'Genesis 15:5', unlock: ProUnlock()),

  // Dieren
  CatalogItem(id: 'geen', kind: ItemKind.animal, name: 'Geen', blurb: 'Alleen de boom.', unlock: FreeUnlock()),
  CatalogItem(id: 'vogel', kind: ItemKind.animal, name: 'Vogel', blurb: 'Nestelt in je kroon.', verse: 'Psalm 84:4', unlock: LevelUnlock(5)),
  CatalogItem(id: 'vlinders', kind: ItemKind.animal, name: 'Vlinders', blurb: 'Drie vlinders rond je boom.', unlock: LevelUnlock(7)),
  CatalogItem(id: 'schaap', kind: ItemKind.animal, name: 'Schapen', blurb: 'Twee schapen grazen bij de stam.', verse: 'Psalm 23:2', unlock: BadgeUnlock('completed1', 'Eerste studie voltooid')),
  CatalogItem(id: 'duif', kind: ItemKind.animal, name: 'Duif', blurb: 'Een witte duif op de hoogste tak.', verse: 'Genesis 8:11', unlock: StreakUnlock(14)),
  CatalogItem(id: 'vuurvliegjes', kind: ItemKind.animal, name: 'Vuurvliegjes', blurb: "Lichtjes in je boom, 's nachts.", unlock: LevelUnlock(15)),
  CatalogItem(id: 'hert', kind: ItemKind.animal, name: 'Hert', blurb: 'Een hert naast je boom.', verse: 'Psalm 42:2', unlock: StreakUnlock(60)),

  // Ring
  CatalogItem(id: 'teal', kind: ItemKind.ring, name: 'Groene ring', blurb: 'De standaard voortgangsring.', unlock: FreeUnlock()),
  CatalogItem(id: 'goud', kind: ItemKind.ring, name: 'Gouden ring', blurb: 'Een gouden ring om je boom.', unlock: ProUnlock()),
];

List<CatalogItem> itemsOfKind(ItemKind kind) =>
    kCatalog.where((item) => item.kind == kind).toList();

CatalogItem? catalogItem(ItemKind kind, String id) {
  for (final item in kCatalog) {
    if (item.kind == kind && item.id == id) return item;
  }
  return null;
}

/// The reader's choice, as stored on the account.
class AvatarChoice {
  const AvatarChoice({
    this.species = kDefaultSpecies,
    this.scene = kDefaultScene,
    this.animal = kDefaultAnimal,
    this.ring = kDefaultRing,
  });

  final TreeSpecies species;
  final TreeSceneId scene;
  final TreeAnimal animal;
  final TreeRing ring;

  static const AvatarChoice defaults = AvatarChoice();

  String get speciesId => kSpeciesIds[species]!;
  String get sceneId => kSceneIds[scene]!;
  String get animalId => kAnimalIds[animal]!;
  String get ringId => kRingIds[ring]!;

  factory AvatarChoice.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    return AvatarChoice(
      species: speciesFromId(raw['species'] as String?),
      scene: sceneFromId(raw['scene'] as String?),
      animal: animalFromId(raw['animal'] as String?),
      ring: ringFromId(raw['ring'] as String?),
    );
  }

  Map<String, String> toJson() => {
    'species': speciesId,
    'scene': sceneId,
    'animal': animalId,
    'ring': ringId,
  };

  AvatarChoice copyWith({
    TreeSpecies? species,
    TreeSceneId? scene,
    TreeAnimal? animal,
    TreeRing? ring,
  }) {
    return AvatarChoice(
      species: species ?? this.species,
      scene: scene ?? this.scene,
      animal: animal ?? this.animal,
      ring: ring ?? this.ring,
    );
  }

  /// The id this choice holds for [kind], so a tile can tell if it is selected.
  String idFor(ItemKind kind) => switch (kind) {
    ItemKind.species => speciesId,
    ItemKind.scene => sceneId,
    ItemKind.animal => animalId,
    ItemKind.ring => ringId,
  };

  /// The same choice with [kind] set to [id]; unknown ids fall back to default.
  AvatarChoice withItem(ItemKind kind, String id) => switch (kind) {
    ItemKind.species => copyWith(species: speciesFromId(id)),
    ItemKind.scene => copyWith(scene: sceneFromId(id)),
    ItemKind.animal => copyWith(animal: animalFromId(id)),
    ItemKind.ring => copyWith(ring: ringFromId(id)),
  };

  @override
  bool operator ==(Object other) =>
      other is AvatarChoice &&
      other.species == species &&
      other.scene == scene &&
      other.animal == animal &&
      other.ring == ring;

  @override
  int get hashCode => Object.hash(species, scene, animal, ring);
}

/// Everything an unlock rule can look at. All of it already exists on the
/// account.
class UnlockContext {
  const UnlockContext({
    required this.level,
    required this.badges,
    required this.longestStreak,
    required this.isPro,
  });

  final int level;
  final List<String> badges;
  final int longestStreak;
  final bool isPro;
}

bool isUnlocked(CatalogItem item, UnlockContext ctx) => switch (item.unlock) {
  FreeUnlock() => true,
  LevelUnlock(:final level) => ctx.level >= level,
  StreakUnlock(:final days) => ctx.longestStreak >= days,
  BadgeUnlock(:final badge) => ctx.badges.contains(badge),
  ProUnlock() => ctx.isPro,
};

Set<String> unlockedKeys(UnlockContext ctx) =>
    {for (final item in kCatalog) if (isUnlocked(item, ctx)) item.key};

/// The avatar to draw: the stored choice, with anything the account is not
/// (or no longer) entitled to swapped for that kind's default. The stored
/// choice is never rewritten, so a lapsed Pro item comes back on renewal.
AvatarChoice resolveAvatar(AvatarChoice chosen, Set<String> unlocked) {
  return AvatarChoice(
    species: unlocked.contains('species:${chosen.speciesId}') ? chosen.species : kDefaultSpecies,
    scene: unlocked.contains('scene:${chosen.sceneId}') ? chosen.scene : kDefaultScene,
    animal: unlocked.contains('animal:${chosen.animalId}') ? chosen.animal : kDefaultAnimal,
    ring: unlocked.contains('ring:${chosen.ringId}') ? chosen.ring : kDefaultRing,
  );
}

/// The Dutch line under a locked tile.
String unlockLabel(Unlock unlock) => switch (unlock) {
  FreeUnlock() => 'Gratis',
  LevelUnlock(:final level) => 'Niveau $level',
  StreakUnlock(:final days) => 'Reeks van $days dagen',
  BadgeUnlock(:final label) => label,
  ProUnlock() => 'Pro',
};

/// The nearest level-gated item the reader has not reached, for the progress
/// strip's "nog 340 XP → Palmboom". Streak, badge and Pro items are not
/// "nearer" in any XP sense, so they never show up here.
CatalogItem? nextLevelUnlock(UnlockContext ctx) {
  CatalogItem? best;
  var bestLevel = 1 << 30;
  for (final item in kCatalog) {
    final unlock = item.unlock;
    if (unlock is! LevelUnlock) continue;
    if (unlock.level <= ctx.level) continue;
    if (unlock.level < bestLevel) {
      best = item;
      bestLevel = unlock.level;
    }
  }
  return best;
}

/// Items that unlock at exactly this level - what a level-up card announces.
List<CatalogItem> itemsUnlockedAtLevel(int level) => [
  for (final item in kCatalog)
    if (item.unlock case LevelUnlock(level: final at) when at == level) item,
];
