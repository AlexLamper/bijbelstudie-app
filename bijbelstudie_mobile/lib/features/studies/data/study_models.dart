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

  /// `Gedeelte` / `Persoon` / `Onderwerp` / `Boek` — the badge on the card.
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

/// A leesplan from `GET /api/v1/plans`.
class BiblePlan {
  const BiblePlan({
    required this.id,
    required this.title,
    required this.description,
    required this.duration,
    required this.category,
    required this.isEnrolled,
    required this.completedDays,
    required this.progressPercentage,
    required this.readings,
    this.author,
    this.isOwner = false,
  });

  final String id;
  final String title;
  final String description;
  final int duration;
  final String category;
  final bool isEnrolled;
  final List<int> completedDays;
  final int progressPercentage;
  final List<PlanReading> readings;
  final String? author;
  final bool isOwner;

  factory BiblePlan.fromJson(Map<String, dynamic> json) {
    return BiblePlan(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'evangelie',
      isEnrolled: json['isEnrolled'] as bool? ?? false,
      completedDays: (json['completedDays'] as List? ?? const [])
          .map((d) => (d as num).toInt())
          .toList(growable: false),
      progressPercentage: (json['progressPercentage'] as num?)?.toInt() ?? 0,
      readings: (json['readings'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlanReading.fromJson)
          .toList(growable: false),
      author: json['author'] as String?,
      isOwner: json['isOwner'] as bool? ?? false,
    );
  }
}

class PlanReading {
  const PlanReading({
    required this.day,
    required this.book,
    required this.chapter,
    this.title,
  });

  final int day;
  final String book;
  final int chapter;
  final String? title;

  String get reference => '$book $chapter';

  factory PlanReading.fromJson(Map<String, dynamic> json) {
    return PlanReading(
      day: (json['day'] as num?)?.toInt() ?? 1,
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      title: json['title'] as String?,
    );
  }
}
