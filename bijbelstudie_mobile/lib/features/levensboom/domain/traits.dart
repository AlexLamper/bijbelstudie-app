/// What the tree gains, and when. Mirror of the website's
/// `lib/levensboom/traits.ts`; both are checked against
/// `docs/levensboom-spec.md` §6.
///
/// The server also serves `traitsUnlocked`, so a build older than a trait-table
/// change still gets a correct list. This table is what the *renderer* needs -
/// the API answer arrives too late to decide whether to draw a canopy.
library;

enum TreeTrait { canopy, blossom, fruit, bird, twin, fireflies, seasons }

const Map<TreeTrait, int> kTraitLevels = {
  TreeTrait.canopy: 3,
  TreeTrait.blossom: 5,
  TreeTrait.fruit: 8,
  TreeTrait.bird: 12,
  TreeTrait.twin: 16,
  TreeTrait.fireflies: 20,
  TreeTrait.seasons: 25,
};

const List<TreeTrait> kTraitOrder = [
  TreeTrait.canopy,
  TreeTrait.blossom,
  TreeTrait.fruit,
  TreeTrait.bird,
  TreeTrait.twin,
  TreeTrait.fireflies,
  TreeTrait.seasons,
];

/// The id the API uses, so a served list can be matched against this table.
const Map<TreeTrait, String> kTraitIds = {
  TreeTrait.canopy: 'canopy',
  TreeTrait.blossom: 'blossom',
  TreeTrait.fruit: 'fruit',
  TreeTrait.bird: 'bird',
  TreeTrait.twin: 'twin',
  TreeTrait.fireflies: 'fireflies',
  TreeTrait.seasons: 'seasons',
};

const Map<TreeTrait, String> kTraitLabels = {
  TreeTrait.canopy: 'Je boom krijgt een echte kroon',
  TreeTrait.blossom: 'Bloesem in het voorjaar',
  TreeTrait.fruit: 'De eerste vrucht van de Geest',
  TreeTrait.bird: 'Een vogel keert terug naar je boom',
  TreeTrait.twin: 'Een tweede stam - je boom komt tot zijn recht',
  TreeTrait.fireflies: "Vuurvliegjes 's nachts",
  TreeTrait.seasons: 'Zeldzame seizoenen: sneeuw en bloesemstorm',
};

bool hasTrait(int level, TreeTrait trait) => level >= kTraitLevels[trait]!;

List<TreeTrait> traitsForLevel(int level) =>
    kTraitOrder.where((trait) => hasTrait(level, trait)).toList();

/// The next trait the reader has not reached yet, for "wat komt hierna?".
MapEntry<TreeTrait, int>? nextTrait(int level) {
  for (final trait in kTraitOrder) {
    final at = kTraitLevels[trait]!;
    if (level < at) return MapEntry(trait, at);
  }
  return null;
}

/// The trait that arrives at exactly this level, if any - the line the
/// celebration card shows on a non-fruit level-up.
TreeTrait? traitAtLevel(int level) {
  for (final trait in kTraitOrder) {
    if (kTraitLevels[trait] == level) return trait;
  }
  return null;
}

/// Galatians 5:22-23, in order. The app's word for "milestone": the number is
/// still there for people who like numbers, but what the tree grows is fruit.
class SpiritFruit {
  const SpiritFruit({required this.name, required this.level});

  final String name;
  final int level;

  String get reference => kFruitReference;
}

const String kFruitReference = 'Galaten 5:22-23';

const List<String> _fruitNames = [
  'Liefde',
  'Blijdschap',
  'Vrede',
  'Geduld',
  'Vriendelijkheid',
  'Goedheid',
  'Geloof',
  'Zachtmoedigheid',
  'Zelfbeheersing',
];

int fruitLevel(int index) => kTraitLevels[TreeTrait.fruit]! + index * 2;

/// One fruit at level 8, then one every second level, ending at nine.
int fruitCount(int level) {
  final from = kTraitLevels[TreeTrait.fruit]!;
  if (level < from) return 0;
  final count = ((level - from) ~/ 2) + 1;
  return count > 9 ? 9 : count;
}

List<SpiritFruit> allFruits() => [
  for (var i = 0; i < _fruitNames.length; i++)
    SpiritFruit(name: _fruitNames[i], level: fruitLevel(i)),
];

List<SpiritFruit> fruitsForLevel(int level) =>
    allFruits().take(fruitCount(level)).toList();

/// The fruit a level-up hands over, or null when this level unlocks none.
SpiritFruit? fruitAtLevel(int level) {
  final from = kTraitLevels[TreeTrait.fruit]!;
  if (level < from) return null;
  if ((level - from) % 2 != 0) return null;
  final index = (level - from) ~/ 2;
  return index < _fruitNames.length ? allFruits()[index] : null;
}
