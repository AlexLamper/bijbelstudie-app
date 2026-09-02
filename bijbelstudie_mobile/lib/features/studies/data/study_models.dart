// Shapes returned by `GET /api/v1/studies`, sourced from
// `lib/data/curated-studies.ts` on the website.

class StudyLesson {
  const StudyLesson({
    required this.day,
    required this.title,
    required this.book,
    required this.chapter,
    required this.focus,
    this.verseRange,
  });

  final int day;
  final String title;
  final String book;
  final int chapter;
  final String focus;
  final String? verseRange;

  String get reference =>
      verseRange == null ? '$book $chapter' : '$book $chapter:$verseRange';

  /// Chapter-level reference, for the places a verse range is more detail than
  /// the line has room for.
  String get chapterReference => '$book $chapter';

  /// The first and last verse of [verseRange], or null when the lesson covers
  /// the whole chapter.
  ///
  /// The website writes the range with an en dash (1 to 18), so both dash
  /// forms are accepted; `POST /api/v1/study-progress` wants plain integers.
  (int, int)? get verseBounds {
    final raw = verseRange;
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split(RegExp(r'[-\u2013\u2014]'));
    final start = int.tryParse(parts.first.trim());
    if (start == null) return null;
    final end = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
    return (start, end ?? start);
  }

  factory StudyLesson.fromJson(Map<String, dynamic> json) {
    return StudyLesson(
      day: (json['day'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      focus: json['focus'] as String? ?? '',
      verseRange: json['verseRange'] as String?,
    );
  }
}

class CuratedStudy {
  const CuratedStudy({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.durationLabel,
    required this.startBook,
    required this.startChapter,
    required this.startVersion,
    required this.image,
    required this.lessons,
    this.about = const [],
    this.outcomes = const [],
    this.suggestedRhythm,
    this.suggestedDepth,
    this.category,
    this.kind,
    this.avgMinutes,
  });

  /// `Gedeelte` / `Persoon` / `Onderwerp` / `Boek` - the badge on the card.
  final String type;

  final String id;
  final String title;
  final String description;
  final String durationLabel;
  final String startBook;
  final int startChapter;
  final String startVersion;
  final String image;
  final List<StudyLesson> lessons;

  /// The "waar gaat deze studie over?" paragraphs. The detail screen shows at
  /// most the first two; empty for a generated book study, which falls back to
  /// [description].
  final List<String> about;

  final List<String> outcomes;

  /// What the study itself proposes in the start dialog, when it has an
  /// opinion: `dagelijks` / `drie-per-week` / `wekelijks` / `eigen` / `vrij`.
  final String? suggestedRhythm;

  /// `kort` or `diep`.
  final String? suggestedDepth;

  /// `ot` / `nt` / `personen` / `themas`, resolved server-side by
  /// `/api/v1/studies/catalog`. Null on the older `/api/v1/studies` response.
  final String? category;

  /// One word for what this is: a book genre (`Evangelie`) or `Persoon` /
  /// `Gedeelte` / `Thema`.
  final String? kind;

  /// Mean minutes per lesson as the server measured it. Prefer this over
  /// [estimatedMinutes]'s flat ten-minute assumption when it is present.
  final int? avgMinutes;

  int get lessonCount => lessons.length;

  /// Minutes per lesson: the server's average when the catalogue supplied one,
  /// otherwise the flat estimate the older endpoint implies.
  int get minutesPerLesson => avgMinutes ?? 10;

  /// The distinct books the lessons walk through, in lesson order. This is the
  /// single most concrete answer to "what am I going to read", and the website
  /// only ever shows it a lesson at a time behind an expander.
  List<String> get books {
    final seen = <String>[];
    for (final lesson in lessons) {
      if (lesson.book.isNotEmpty && !seen.contains(lesson.book)) {
        seen.add(lesson.book);
      }
    }
    return seen;
  }

  /// `Johannes 20` for a study that stays put, `Genesis 12 - Jakobus 2` for one
  /// that travels. Verses are left off deliberately: this sits on one line of a
  /// card next to two other chips.
  String get scopeLabel {
    if (lessons.isEmpty) return '$startBook $startChapter';
    final first = lessons.first.chapterReference;
    final last = lessons.last.chapterReference;
    return first == last ? first : '$first - $last';
  }

  /// Roughly ten minutes of reading and reflection per lesson, which is what
  /// the lesson lengths on the website work out to. Shown as a total so the
  /// reader can judge the commitment before starting rather than after.
  int get estimatedMinutes => lessonCount * minutesPerLesson;

  /// Plain-language gloss of [type]. The badge alone says `Gedeelte`, which
  /// tells a first-time reader nothing about what the study is.
  String get typeSummary => switch (type) {
    'Persoon' => 'Volg het leven van een persoon uit de Bijbel',
    'Gedeelte' => 'Lees een bijbelgedeelte van dichtbij',
    'Boek' => 'Werk een bijbelboek van begin tot eind door',
    _ => 'Volg een thema door de hele Bijbel',
  };

  StudyLesson? get firstLesson => lessons.isEmpty ? null : lessons.first;

  /// The lesson for [day], or null when the study has no such lesson.
  StudyLesson? lessonForDay(int day) {
    for (final lesson in lessons) {
      if (lesson.day == day) return lesson;
    }
    return null;
  }

  factory CuratedStudy.fromJson(Map<String, dynamic> json) {
    return CuratedStudy(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'Onderwerp',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      durationLabel: json['durationLabel'] as String? ?? '',
      startBook: json['startBook'] as String? ?? 'Genesis',
      startChapter: (json['startChapter'] as num?)?.toInt() ?? 1,
      startVersion: json['startVersion'] as String? ?? 'statenvertaling',
      image: json['image'] as String? ?? '',
      lessons: (json['lessons'] as List? ?? const [])
          .map((l) => StudyLesson.fromJson(l as Map<String, dynamic>))
          .toList(growable: false),
      about: _stringList(json['about']),
      outcomes: _stringList(json['outcomes']),
      suggestedRhythm: json['suggestedRhythm'] as String?,
      suggestedDepth: json['suggestedDepth'] as String?,
      category: json['category'] as String?,
      kind: json['kind'] as String?,
      avgMinutes: (json['avgMinutes'] as num?)?.toInt(),
    );
  }
}

/// Whatever the server sent, as a list of non-empty strings. `about` and
/// `outcomes` are absent on generated studies and can arrive as a bare string.
List<String> _stringList(Object? value) {
  if (value is String) {
    return value.trim().isEmpty ? const [] : [value.trim()];
  }
  if (value is List) {
    return value
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}
