/// The one random source the Levensboom is allowed to use.
///
/// A direct port of the website's `lib/levensboom/rng.ts`, operation for
/// operation, because the promise this feature makes is that a user's tree is
/// *theirs*: the same account has to render the same tree here and on the
/// website, and after a reinstall. A single `Random()` anywhere in the
/// generator would break that silently.
///
/// Contract: `docs/levensboom-spec.md` §3 in the website repo.
library;

int _u32(int value) => value & 0xFFFFFFFF;

/// 32-bit wrapping multiply, matching JavaScript's `Math.imul` on unsigned
/// inputs. Dart's ints are 64-bit natively, so the product of two 32-bit values
/// cannot overflow before it is masked.
int _mul32(int a, int b) => _u32(_u32(a) * _u32(b));

/// FNV-1a, 32 bit. Maps a user id to a stream seed.
int fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < input.length; i++) {
    hash = _u32(hash ^ input.codeUnitAt(i));
    hash = _mul32(hash, 0x01000193);
  }
  return hash;
}

/// mulberry32. Small, fast, and identical to the TypeScript implementation.
class Mulberry32 {
  Mulberry32(int seed) : _state = _u32(seed);

  int _state;

  double call() {
    _state = _u32(_state + 0x6D2B79F5);
    var t = _state;
    t = _mul32(_u32(t ^ (t >> 15)), _u32(t | 1));
    t = _u32(t ^ _u32(t + _mul32(_u32(t ^ (t >> 7)), _u32(t | 61))));
    return _u32(t ^ (t >> 14)) / 4294967296.0;
  }
}

/// The stream a given user's tree is drawn from.
Mulberry32 seededRng(String seed) => Mulberry32(fnv1a32(seed));

/// Growth v2: one stream per node of the tree, keyed by its path ("T", "T01",
/// "T01L2", "C0", "PF3" ...). Adding a branch, a leaf or a whole subtree can
/// never shift another node's numbers, which is what lets a tree grow instead
/// of being redrawn at every level-up. Paths are plain ASCII, so this hashes
/// exactly the code units the website's `nodeRng` hashes.
Mulberry32 nodeRng(String seed, String path) => Mulberry32(fnv1a32('$seed|$path'));

/// The first [count] values of a node's stream.
List<double> nodeDraws(String seed, String path, int count) {
  final rand = nodeRng(seed, path);
  return List<double>.generate(count, (_) => rand(), growable: false);
}
