import '../../../core/data/bible_books.dart';
import '../../../core/data/text_format.dart';

/// One cross-reference: a target passage, already resolved to this
/// translation's numbering and named in Dutch by the server.
///
/// The app deliberately holds no OSIS ↔ Dutch book table. `/api/v1/crossrefs`
/// resolves both the book name and the printable [label] server-side, so a
/// change in the canon or in a translation's spelling is one deploy, not an
/// app release. [osis] is carried through only because it is stable enough to
/// key on; nothing here parses it.
class CrossRef {
  const CrossRef({
    required this.osis,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.label,
    required this.votes,
    this.endChapter,
    this.endVerse,
  });

  final String osis;
  final String book;
  final int chapter;
  final int verse;

  /// Printable reference as the server formatted it. Never rebuilt for
  /// display when the server sent one — the label and the numbering it
  /// describes are decided in the same place.
  final String label;

  /// OpenBible community votes. The list arrives sorted by this, so it is kept
  /// only so a caller can say how strong a link is, not to re-sort.
  final int votes;

  /// Last chapter of the range, and null for the overwhelming majority of
  /// references that stay inside one chapter. A server that sends the start
  /// chapter again is normalised away here, so `endChapter != null` always
  /// means the range genuinely crosses a chapter boundary.
  final int? endChapter;

  /// Last verse of the range, null when the reference is a single verse.
  final int? endVerse;

  bool get isRange => endVerse != null || endChapter != null;

  factory CrossRef.fromJson(Map<String, dynamic> json) {
    final book = (json['book'] as String? ?? '').trim();
    final chapter = (json['chapter'] as num?)?.toInt() ?? 0;
    final verse = (json['verse'] as num?)?.toInt() ?? 0;

    final rawEndChapter = (json['endChapter'] as num?)?.toInt();
    final rawEndVerse = (json['endVerse'] as num?)?.toInt();

    // A "range" that ends where it starts is a single verse. Normalising here
    // keeps every consumer from having to ask the same question twice.
    final endChapter = rawEndChapter == null || rawEndChapter == chapter
        ? null
        : rawEndChapter;
    final endVerse = rawEndVerse == null || (endChapter == null && rawEndVerse <= verse)
        ? null
        : rawEndVerse;

    final label = normaliseDashes((json['label'] as String? ?? '').trim());

    return CrossRef(
      osis: (json['osis'] as String? ?? '').trim(),
      book: book,
      chapter: chapter,
      verse: verse,
      endChapter: endChapter,
      endVerse: endVerse,
      label: label.isNotEmpty
          ? label
          : formatLabel(
              book: book,
              chapter: chapter,
              verse: verse,
              endChapter: endChapter,
              endVerse: endVerse,
            ),
      votes: (json['votes'] as num?)?.toInt() ?? 0,
    );
  }

  /// The fallback used only when the server sent no label — an older build of
  /// the route, or a payload that lost the field. Same shape the server uses:
  /// `Johannes 1:1-3`, `Mattheüs 5:1-7:29`.
  static String formatLabel({
    required String book,
    required int chapter,
    required int verse,
    int? endChapter,
    int? endVerse,
  }) {
    if (endChapter != null) {
      final tail = endVerse == null ? '$endChapter' : '$endChapter:$endVerse';
      return '$book $chapter:$verse-$tail';
    }
    if (endVerse != null) return '$book $chapter:$verse-$endVerse';
    return '$book $chapter:$verse';
  }

  /// Verse numbers this reference covers inside [chapter], capped at [max].
  ///
  /// A cross-chapter range is deliberately cut at the end of its first
  /// chapter: the preview reads out of one cached chapter, and following the
  /// reference is how the rest is meant to be read.
  List<int> versesInStartChapter({int max = 5}) {
    final last = endChapter != null ? verse + max - 1 : (endVerse ?? verse);
    final end = last < verse ? verse : last;
    return [
      for (var n = verse; n <= end && n - verse < max; n++) n,
    ];
  }
}

/// The references hanging off one verse of the chapter, strongest first.
class CrossRefVerse {
  const CrossRefVerse({required this.number, required this.refs});

  final int number;
  final List<CrossRef> refs;

  factory CrossRefVerse.fromJson(Map<String, dynamic> json) {
    return CrossRefVerse(
      number: (json['n'] as num?)?.toInt() ?? 0,
      refs: (json['refs'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CrossRef.fromJson)
          .toList(),
    );
  }
}

/// One chapter's worth of cross-references.
///
/// A chapter with nothing to show is a 200 with an empty [verses], never a
/// 404, so "no references here" and "this failed" stay distinguishable — the
/// sheet says something different for each.
class CrossRefChapter {
  const CrossRefChapter({
    required this.id,
    required this.datasetVersion,
    required this.versification,
    required this.version,
    required this.book,
    required this.osis,
    required this.chapter,
    required this.verses,
    required this.attribution,
    this.numberingMayDiffer = false,
    this.updatedAt,
    this.fromCache = false,
  });

  final String id;
  final int datasetVersion;
  final String versification;
  final String version;
  final String book;
  final String osis;
  final int chapter;
  final List<CrossRefVerse> verses;

  /// CC BY credit, rendered verbatim under every list. Never retyped on the
  /// client: what the server sent is what the licence is satisfied by.
  final String attribution;

  /// True when this translation has no versification profile and the numbers
  /// may not line up. The reader is told rather than quietly sent one verse
  /// off.
  final bool numberingMayDiffer;

  final DateTime? updatedAt;

  /// True when the payload came off disk with no network behind it.
  final bool fromCache;

  factory CrossRefChapter.fromJson(
    Map<String, dynamic> json, {
    bool fromCache = false,
  }) {
    return CrossRefChapter(
      id: json['id'] as String? ?? '',
      datasetVersion: (json['datasetVersion'] as num?)?.toInt() ?? 0,
      versification: json['versification'] as String? ?? '',
      version: json['version'] as String? ?? '',
      book: json['book'] as String? ?? '',
      osis: json['osis'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 0,
      verses: (json['verses'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CrossRefVerse.fromJson)
          .toList(),
      attribution: normaliseDashes(json['attribution'] as String? ?? ''),
      numberingMayDiffer: json['numberingMayDiffer'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      fromCache: fromCache,
    );
  }

  /// References for one verse, strongest first, empty when it has none.
  List<CrossRef> refsFor(int verse) {
    for (final entry in verses) {
      if (entry.number == verse) return entry.refs;
    }
    return const [];
  }

  int countFor(int verse) => refsFor(verse).length;
}

/// The testament pair an analytics event may carry: `ot_ot`, `ot_nt`,
/// `nt_ot`, `nt_nt`.
///
/// This is the whole of what the funnel learns about which passage was
/// followed. Book, chapter and verse are never sent — the server's allowlist
/// refuses that cardinality by design, so an event carrying them is dropped
/// silently and measures nothing.
String crossRefTestamentPair(String fromBook, String toBook) {
  String side(String book) =>
      BibleBooks.newTestament.contains(BibleBooks.toCanonical(book)) ? 'nt' : 'ot';
  return '${side(fromBook)}_${side(toBook)}';
}
