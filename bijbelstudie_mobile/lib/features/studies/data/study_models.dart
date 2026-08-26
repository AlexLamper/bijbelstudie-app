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

  int get lessonCount => lessons.length;

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
  int get estimatedMinutes => lessonCount * 10;

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
    );
  }
}
