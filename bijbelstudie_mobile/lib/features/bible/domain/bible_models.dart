// Shapes confirmed against the running backend (GET /api/v1/...), not
// inferred from route names.

class BibleSource {
  const BibleSource({
    required this.id,
    required this.name,
    required this.language,
    required this.attribution,
  });

  final String id;
  final String name;
  final String language;
  final String attribution;

  factory BibleSource.fromJson(Map<String, dynamic> json) {
    return BibleSource(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      language: json['language'] as String? ?? 'nl',
      attribution: json['attribution'] as String? ?? '',
    );
  }

  String get languageLabel {
    switch (language) {
      case 'nl':
        return 'Nederlands';
      case 'en':
        return 'Engels';
      case 'de':
        return 'Duits';
      default:
        return language.toUpperCase();
    }
  }
}

class Verse {
  const Verse({required this.number, required this.text});

  final int number;
  final String text;

  factory Verse.fromJson(Map<String, dynamic> json) {
    return Verse(number: (json['n'] as num).toInt(), text: json['t'] as String? ?? '');
  }
}

class ChapterContent {
  const ChapterContent({
    required this.sourceId,
    required this.book,
    required this.chapter,
    required this.verses,
    required this.attribution,
    this.fromCache = false,
  });

  final String sourceId;
  final String book;
  final int chapter;
  final List<Verse> verses;
  final String attribution;

  /// True when the reader is showing text that came off disk with no network.
  final bool fromCache;

  factory ChapterContent.fromJson(Map<String, dynamic> json, {bool fromCache = false}) {
    return ChapterContent(
      sourceId: json['id'] as String? ?? '',
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 0,
      verses: (json['verses'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Verse.fromJson)
          .toList(),
      attribution: json['attribution'] as String? ?? '',
      fromCache: fromCache,
    );
  }

  String get reference => '$book $chapter';

  /// Plain text for the share sheet, with verse numbers inline.
  String shareText({Iterable<int>? onlyVerses}) {
    final wanted = onlyVerses?.toSet();
    final selected = wanted == null
        ? verses
        : verses.where((v) => wanted.contains(v.number)).toList();
    final body = selected.map((v) => '${v.number} ${v.text}').join('\n');
    return '$body\n\n$reference — $attribution';
  }
}

class OriginalWord {
  const OriginalWord({
    required this.original,
    required this.transliteration,
    required this.gloss,
    required this.strongs,
  });

  final String original;
  final String transliteration;
  final String gloss;
  final String strongs;

  factory OriginalWord.fromJson(Map<String, dynamic> json) {
    return OriginalWord(
      original: json['h'] as String? ?? '',
      transliteration: json['t'] as String? ?? '',
      gloss: json['e'] as String? ?? '',
      strongs: json['s'] as String? ?? '',
    );
  }
}

class OriginalVerse {
  const OriginalVerse({required this.number, required this.words});

  final int number;
  final List<OriginalWord> words;

  factory OriginalVerse.fromJson(Map<String, dynamic> json) {
    return OriginalVerse(
      number: (json['n'] as num).toInt(),
      words: (json['words'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OriginalWord.fromJson)
          .toList(),
    );
  }
}

class OriginalChapter {
  const OriginalChapter({
    required this.book,
    required this.chapter,
    required this.verses,
    required this.attribution,
  });

  final String book;
  final int chapter;
  final List<OriginalVerse> verses;

  /// CC BY 4.0 requires this to be visible wherever the words are shown.
  final String attribution;

  factory OriginalChapter.fromJson(Map<String, dynamic> json) {
    return OriginalChapter(
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 0,
      verses: (json['verses'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OriginalVerse.fromJson)
          .toList(),
      attribution: json['attribution'] as String? ?? '',
    );
  }
}

class SearchHit {
  const SearchHit({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final String book;
  final int chapter;
  final int verse;
  final String text;

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    return SearchHit(
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 0,
      verse: (json['verse'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
    );
  }

  String get reference => '$book $chapter:$verse';
}

class SearchResults {
  const SearchResults({required this.hits, required this.truncated});

  final List<SearchHit> hits;

  /// The server stopped early — either the hit cap or its wall-clock budget.
  final bool truncated;

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    return SearchResults(
      hits: (json['hits'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SearchHit.fromJson)
          .toList(),
      truncated: json['truncated'] as bool? ?? false,
    );
  }
}

/// Raised when the server refuses a source for licensing reasons (HTTP 451).
class ContentNotLicensedException implements Exception {
  const ContentNotLicensedException(this.sourceId);

  final String sourceId;

  @override
  String toString() =>
      'Deze bron is niet beschikbaar in de app vanwege licentievoorwaarden.';
}
