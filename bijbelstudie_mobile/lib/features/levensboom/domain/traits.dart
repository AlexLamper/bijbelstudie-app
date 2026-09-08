/// What the tree gains with level, beyond size. Mirror of the website's
/// `lib/levensboom/traits.ts`; both are checked against
/// `docs/levensboom-spec.md` §6.
///
/// The bird and the fireflies used to be traits; they are animals in the
/// catalog now (`catalog.dart`), picked rather than granted.
library;

enum TreeTrait { blossom, fruit, twin, seasons }

const Map<TreeTrait, int> kTraitLevels = {
  TreeTrait.blossom: 5,
  TreeTrait.fruit: 8,
  TreeTrait.twin: 16,
  TreeTrait.seasons: 25,
};

const List<TreeTrait> kTraitOrder = [
  TreeTrait.blossom,
  TreeTrait.fruit,
  TreeTrait.twin,
  TreeTrait.seasons,
];

/// The id the API uses, so a served list can be matched against this table.
const Map<TreeTrait, String> kTraitIds = {
  TreeTrait.blossom: 'blossom',
  TreeTrait.fruit: 'fruit',
  TreeTrait.twin: 'twin',
  TreeTrait.seasons: 'seasons',
};

const Map<TreeTrait, String> kTraitLabels = {
  TreeTrait.blossom: 'Bloesem in het voorjaar',
  TreeTrait.fruit: 'De eerste vrucht van de Geest',
  TreeTrait.twin: 'Een tweede stam',
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
