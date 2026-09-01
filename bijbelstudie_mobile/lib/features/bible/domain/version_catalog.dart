import 'bible_models.dart';

/// The order translations are offered in, everywhere they are offered.
///
/// `/api/v1/bibles` returns them in manifest order, which is the order the
/// files happen to sit in on the server - Canisius first, Statenvertaling
/// sixth, the English ones interleaved with the German. That is an
/// implementation detail leaking into the first question a new user is ever
/// asked, so the client imposes its own order instead of the server changing
/// a manifest the website also reads.
///
/// Two rules, in this order:
///
///  1. Language. Dutch first (this is a Dutch product), then English. The app
///     ships nothing else - the German translations are website-only - but the
///     rule is written as an ordering rather than a filter, so a language the
///     server starts serving lands after these two instead of disappearing.
///     [grouped] turns the same ranking into labelled sections so a picker can
///     draw a rule between the languages.
///  2. Within a language, most-reached-for first. Hand-ranked rather than
///     alphabetical: "Statenvertaling, NBG-vertaling 1951, Canisiusbijbel" is
///     the order a Dutch reader expects, and "American Standard Version,
///     Coverdale, Geneva, King James" is not an order anybody wants.
///
/// An id missing from [_rank] is not an error - a version added to the server
/// manifest lands at the end of its language group, sorted by name, and shows
/// up without an app release.
class VersionCatalog {
  const VersionCatalog._();

  /// Language codes in the order their groups appear. Anything not listed
  /// sorts after these, by code, so a new language cannot silently outrank
  /// Dutch.
  static const List<String> _languageOrder = ['nl', 'en'];

  /// Popularity rank inside a language group, low number first.
  static const Map<String, int> _rank = {
    // Nederlands
    'statenvertaling': 0,
    'nbg51': 1,
    'canisiusbijbel': 2,
    'heilige_schrift_1917': 3,
    // English
    'kjv': 0,
    'asv': 1,
    'web': 2,
    'geneva': 3,
    'coverdale': 4,
  };

  /// Short codes, as readers actually write them. Hand-kept rather than
  /// derived, because the derivation cannot know that "Statenvertaling" is
  /// `SV` and not `S`, nor that "NBG-vertaling 1951" keeps its year.
  ///
  /// A version missing from here still gets a badge - see [shortCodeFor] -
  /// so a translation added to the server manifest needs no app release.
  static const Map<String, String> _shortCodes = {
    // Nederlands
    'statenvertaling': 'SV',
    'nbg51': 'NBG51',
    'canisiusbijbel': 'CANIS',
    'heilige_schrift_1917': 'HS1917',
    'hsv': 'HSV',
    'bgt': 'BGT',
    'nbv': 'NBV',
    // English
    'kjv': 'KJV',
    'asv': 'ASV',
    'web': 'WEB',
    'geneva': 'GNV',
    'coverdale': 'CVD',
  };

  /// Longest badge the picker will draw. Six characters is `HS1917`; past
  /// that the square would either stretch or the text would be unreadable.
  static const int maxShortCodeLength = 6;

  /// Ranks past every hand-ranked id, so an unknown version sorts to the end
  /// of its group instead of ahead of King James.
  static const int _unranked = 1 << 20;

  static int _languageRank(String language) {
    final index = _languageOrder.indexOf(language);
    return index == -1 ? _languageOrder.length : index;
  }

  /// The badge code for [version] - a hand-kept code when we have one, a
  /// derivation from the name when we do not.
  static String shortCode(BibleSource version) =>
      shortCodeFor(id: version.id, name: version.name);

  /// [shortCode] without needing a [BibleSource].
  ///
  /// The fallback builds initials from the name: one letter per word, plus a
  /// trailing year if the whole thing still fits in [maxShortCodeLength], so
  /// `Elberfelder 1905` becomes `E1905` but `De Heilige Schrift 1917` becomes
  /// `DHS` rather than a truncated `DHS191`. A name with nothing usable in it
  /// falls back to the id. The result is never empty and never longer than
  /// [maxShortCodeLength].
  static String shortCodeFor({required String id, required String name}) {
    final known = _shortCodes[id];
    if (known != null) return known;

    // Apostrophes stay inside their word, so `Young's` contributes one Y
    // rather than a Y and a stray S.
    final words = name
        .replaceAll(RegExp(r"['’]"), '')
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty);

    final letters = StringBuffer();
    String? number;
    for (final word in words) {
      if (RegExp(r'^[0-9]+$').hasMatch(word)) {
        number = word;
      } else {
        letters.write(word[0]);
      }
    }

    var code = letters.toString().toUpperCase();
    if (number != null && code.length + number.length <= maxShortCodeLength) {
      code = '$code$number';
    }

    if (code.isEmpty) {
      code = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    }
    if (code.isEmpty) return '?';

    return code.length <= maxShortCodeLength
        ? code
        : code.substring(0, maxShortCodeLength);
  }

  static int compare(BibleSource a, BibleSource b) {
    final byLanguage = _languageRank(a.language).compareTo(_languageRank(b.language));
    if (byLanguage != 0) return byLanguage;

    // Two unlisted languages that tied above still need a stable order.
    if (a.language != b.language) return a.language.compareTo(b.language);

    final byRank = (_rank[a.id] ?? _unranked).compareTo(_rank[b.id] ?? _unranked);
    if (byRank != 0) return byRank;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// [versions] in display order. Does not mutate the input.
  static List<BibleSource> sorted(Iterable<BibleSource> versions) {
    return [...versions]..sort(compare);
  }

  /// The same order, split into labelled language groups so a picker can put
  /// a heading or a rule between them.
  static List<VersionGroup> grouped(Iterable<BibleSource> versions) {
    final groups = <VersionGroup>[];
    for (final version in sorted(versions)) {
      if (groups.isEmpty || groups.last.language != version.language) {
        groups.add(VersionGroup(
          language: version.language,
          label: version.languageLabel,
          versions: [version],
        ));
      } else {
        groups.last.versions.add(version);
      }
    }
    return groups;
  }
}

/// One language's worth of translations, in display order.
class VersionGroup {
  VersionGroup({
    required this.language,
    required this.label,
    required this.versions,
  });

  final String language;

  /// Dutch name of the language, e.g. `Nederlands`, taken from the versions
  /// themselves so it stays in step with [BibleSource.languageLabel].
  final String label;

  final List<BibleSource> versions;
}
