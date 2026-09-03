/// The 66 Dutch book names and their chapter counts, copied from
/// `lib/data/bible-chapter-counts.ts` and `app/dashboard/page.tsx` on
/// www.bijbelstudie.io.
///
/// The dashboard heat map needs a denominator per book before any chapter has
/// been fetched, so this table is bundled rather than requested. It is fixed
/// data — the canon does not gain a book between releases.
class BibleBooks {
  const BibleBooks._();

  /// Oude Testament, in canonical order.
  static const List<String> oldTestament = [
    'Genesis', 'Exodus', 'Leviticus', 'Numeri', 'Deuteronomium',
    'Jozua', 'Richteren', 'Ruth', '1 Samuël', '2 Samuël',
    '1 Koningen', '2 Koningen', '1 Kronieken', '2 Kronieken', 'Ezra',
    'Nehemia', 'Esther', 'Job', 'Psalmen', 'Spreuken',
    'Prediker', 'Hooglied', 'Jesaja', 'Jeremia', 'Klaagliederen',
    'Ezechiël', 'Daniël', 'Hosea', 'Joël', 'Amos',
    'Obadja', 'Jona', 'Micha', 'Nahum', 'Habakuk',
    'Zefanja', 'Haggaï', 'Zacharia', 'Maleachi',
  ];

  /// Nieuwe Testament, in canonical order.
  static const List<String> newTestament = [
    'Mattheüs', 'Markus', 'Lukas', 'Johannes', 'Handelingen',
    'Romeinen', '1 Korinthe', '2 Korinthe', 'Galaten', 'Efeziërs',
    'Filippenzen', 'Kolossenzen', '1 Thessalonicenzen', '2 Thessalonicenzen',
    '1 Timotheüs', '2 Timotheüs', 'Titus', 'Filémon', 'Hebreeën', 'Jakobus',
    '1 Petrus', '2 Petrus', '1 Johannes', '2 Johannes', '3 Johannes',
    'Judas', 'Openbaring',
  ];

  static List<String> get all => [...oldTestament, ...newTestament];

  static const Map<String, int> chapterCounts = {
    'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numeri': 36,
    'Deuteronomium': 34, 'Jozua': 24, 'Richteren': 21, 'Ruth': 4,
    '1 Samuël': 31, '2 Samuël': 24, '1 Koningen': 22, '2 Koningen': 25,
    '1 Kronieken': 29, '2 Kronieken': 36, 'Ezra': 10, 'Nehemia': 13,
    'Esther': 10, 'Job': 42, 'Psalmen': 150, 'Spreuken': 31,
    'Prediker': 12, 'Hooglied': 8, 'Jesaja': 66, 'Jeremia': 52,
    'Klaagliederen': 5, 'Ezechiël': 48, 'Daniël': 12, 'Hosea': 14,
    'Joël': 3, 'Amos': 9, 'Obadja': 1, 'Jona': 4, 'Micha': 7,
    'Nahum': 3, 'Habakuk': 3, 'Zefanja': 3, 'Haggaï': 2,
    'Zacharia': 14, 'Maleachi': 4, 'Mattheüs': 28, 'Markus': 16,
    'Lukas': 24, 'Johannes': 21, 'Handelingen': 28, 'Romeinen': 16,
    '1 Korinthe': 16, '2 Korinthe': 13, 'Galaten': 6, 'Efeziërs': 6,
    'Filippenzen': 4, 'Kolossenzen': 4, '1 Thessalonicenzen': 5,
    '2 Thessalonicenzen': 3, '1 Timotheüs': 6, '2 Timotheüs': 4,
    'Titus': 3, 'Filémon': 1, 'Hebreeën': 13, 'Jakobus': 5,
    '1 Petrus': 5, '2 Petrus': 3, '1 Johannes': 5, '2 Johannes': 1,
    '3 Johannes': 1, 'Judas': 1, 'Openbaring': 22,
  };

  static int chaptersIn(String book) => chapterCounts[book] ?? 1;

  /// English book names the third-party BijbelAPI.com "daytext" feed (and any
  /// other English-keyed source) can hand back, mapped to the exact Dutch
  /// strings in [oldTestament] / [newTestament]. Mirrors `CANONICAL_NL` in
  /// `lib/book-mapping.ts` on www.bijbelstudie.io, but keyed to *this*
  /// app's canonical Dutch spellings rather than the website's.
  static const Map<String, String> _englishToDutch = {
    'Genesis': 'Genesis',
    'Exodus': 'Exodus',
    'Leviticus': 'Leviticus',
    'Numbers': 'Numeri',
    'Deuteronomy': 'Deuteronomium',
    'Joshua': 'Jozua',
    'Judges': 'Richteren',
    'Ruth': 'Ruth',
    '1 Samuel': '1 Samuël',
    '2 Samuel': '2 Samuël',
    '1 Kings': '1 Koningen',
    '2 Kings': '2 Koningen',
    '1 Chronicles': '1 Kronieken',
    '2 Chronicles': '2 Kronieken',
    'Ezra': 'Ezra',
    'Nehemiah': 'Nehemia',
    'Esther': 'Esther',
    'Job': 'Job',
    'Psalms': 'Psalmen',
    'Psalm': 'Psalmen',
    'Proverbs': 'Spreuken',
    'Ecclesiastes': 'Prediker',
    'Song of Solomon': 'Hooglied',
    'Song of Songs': 'Hooglied',
    'Isaiah': 'Jesaja',
    'Jeremiah': 'Jeremia',
    'Lamentations': 'Klaagliederen',
    'Ezekiel': 'Ezechiël',
    'Daniel': 'Daniël',
    'Hosea': 'Hosea',
    'Joel': 'Joël',
    'Amos': 'Amos',
    'Obadiah': 'Obadja',
    'Jonah': 'Jona',
    'Micah': 'Micha',
    'Nahum': 'Nahum',
    'Habakkuk': 'Habakuk',
    'Zephaniah': 'Zefanja',
    'Haggai': 'Haggaï',
    'Zechariah': 'Zacharia',
    'Malachi': 'Maleachi',
    'Matthew': 'Mattheüs',
    'Mark': 'Markus',
    'Luke': 'Lukas',
    'John': 'Johannes',
    'Acts': 'Handelingen',
    'Romans': 'Romeinen',
    '1 Corinthians': '1 Korinthe',
    '2 Corinthians': '2 Korinthe',
    'Galatians': 'Galaten',
    'Ephesians': 'Efeziërs',
    'Philippians': 'Filippenzen',
    'Colossians': 'Kolossenzen',
    '1 Thessalonians': '1 Thessalonicenzen',
    '2 Thessalonians': '2 Thessalonicenzen',
    '1 Timothy': '1 Timotheüs',
    '2 Timothy': '2 Timotheüs',
    'Titus': 'Titus',
    'Philemon': 'Filémon',
    'Hebrews': 'Hebreeën',
    'James': 'Jakobus',
    '1 Peter': '1 Petrus',
    '2 Peter': '2 Petrus',
    '1 John': '1 Johannes',
    '2 John': '2 Johannes',
    '3 John': '3 Johannes',
    'Jude': 'Judas',
    'Revelation': 'Openbaring',
    'Revelations': 'Openbaring',
  };

  /// Normalises an English book name (as BijbelAPI.com's daytext feed returns
  /// it) to this app's canonical Dutch spelling. A no-op passthrough when
  /// [name] is already Dutch or unrecognised — never empty, never throws.
  static String toDutch(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return name;
    return _englishToDutch[trimmed] ?? name;
  }

  /// Statenvertaling / older-data spellings that differ from the canonical set
  /// in [oldTestament] / [newTestament]. `readChapters` keys arrive spelled the
  /// way the translation that was read spells them, so the dashboard folds them
  /// through here (and [toDutch]) before matching against the 66-book grid.
  static const Map<String, String> _spellingAliases = {
    'Numberi': 'Numeri', // source-data typo
    '1 Corinthiërs': '1 Korinthe',
    '1 Corinthiers': '1 Korinthe',
    '1 Korintiërs': '1 Korinthe',
    '2 Corinthiër': '2 Korinthe',
    '2 Corinthiërs': '2 Korinthe',
    '2 Korintiërs': '2 Korinthe',
    'Colossenzen': 'Kolossenzen',
    'Efeze': 'Efeziërs',
    'Filemon': 'Filémon',
    'Matteüs': 'Mattheüs',
    'Marcus': 'Markus',
    'Lucas': 'Lukas',
    '1 Tessalonicenzen': '1 Thessalonicenzen',
    '2 Tessalonicenzen': '2 Thessalonicenzen',
  };

  static final Set<String> _canonical = {...oldTestament, ...newTestament};

  /// The canonical Dutch book name for [name], whatever a translation called it
  /// (English, or a Statenvertaling spelling). Falls back to [name] unchanged
  /// when it is already canonical or is not recognised.
  static String toCanonical(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _canonical.contains(trimmed)) return trimmed;
    return _spellingAliases[trimmed] ?? _englishToDutch[trimmed] ?? trimmed;
  }
}
