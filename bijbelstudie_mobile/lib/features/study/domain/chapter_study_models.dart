import '../../../core/data/bible_books.dart';
import '../../studies/data/study_models.dart';
import 'lesson_models.dart';

/// Studying one chapter on its own ("Bestudeer dit hoofdstuk").
///
/// Not a new kind of study: the website resolves a chapter to the lesson for that
/// chapter in the book's existing study (`lib/chapterStudy.ts`), and the app opens it
/// without an enrollment. Progress keeps the (studyId, lessonDay) keys, so the
/// chapter counts toward the book study and never pays XP twice.

/// The app route for a chapter study. [book] may be a slug or any book name
/// the website recognises ("1 Korinthe", "Psalmen"); a reader spelling is
/// first brought to the canonical Dutch name. Encoded here, decoded by
/// go_router.
String chapterStudyRoute(String book, int chapter) =>
    '/studie/hoofdstuk/${Uri.encodeComponent(BibleBooks.toCanonical(book))}/$chapter';

/// True when [book] is one of the 66 books under its canonical Dutch name, so
/// the website can resolve it. A translation keyed by other names (English,
/// German) gets no "Bestudeer dit hoofdstuk" entry rather than a dead one.
bool canStudyChapter(String book) =>
    BibleBooks.chapterCounts.containsKey(BibleBooks.toCanonical(book));

/// Which chapter a route or a sheet asks for. A value type, so a provider
/// family keyed on it dedupes.
class ChapterStudyKey {
  const ChapterStudyKey(this.book, this.chapter);

  final String book;
  final int chapter;

  /// From the route's path parameters. Null when either is missing or the
  /// chapter is not a positive whole number, so the route can refuse early.
  static ChapterStudyKey? parse(String? book, String? chapter) {
    final name = book?.trim() ?? '';
    final number = int.tryParse(chapter ?? '');
    if (name.isEmpty || number == null || number < 1) return null;
    return ChapterStudyKey(name, number);
  }

  @override
  bool operator ==(Object other) =>
      other is ChapterStudyKey && other.book == book && other.chapter == chapter;

  @override
  int get hashCode => Object.hash(book, chapter);

  @override
  String toString() => 'ChapterStudyKey($book $chapter)';
}

/// One chapter, as the website names it.
class ChapterRef {
  const ChapterRef({
    required this.book,
    required this.bookName,
    required this.readerBook,
    required this.chapter,
    required this.chapters,
  });

  /// The website's slug, the stable part of the route.
  final String book;
  final String bookName;

  /// The reader's key for the book.
  final String readerBook;
  final int chapter;

  /// Chapters in the book.
  final int chapters;

  String get label => '$bookName $chapter';
  String get route => chapterStudyRoute(book, chapter);

  static ChapterRef? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final book = json['book'];
    final chapter = (json['chapter'] as num?)?.toInt();
    if (book is! String || book.isEmpty || chapter == null) return null;
    final name = json['bookName'] as String? ?? book;
    return ChapterRef(
      book: book,
      bookName: name,
      readerBook: json['readerBook'] as String? ?? name,
      chapter: chapter,
      chapters: (json['chapters'] as num?)?.toInt() ?? chapter,
    );
  }
}

/// `GET /api/v1/chapter-study/:book/:chapter`.
class ChapterStudy {
  const ChapterStudy({
    required this.ref,
    required this.studyId,
    required this.lessonDay,
    required this.followStudyId,
    required this.followStudyTitle,
    required this.lesson,
    this.previous,
    this.next,
    this.enrolled = false,
    this.completed = false,
  });

  final ChapterRef ref;
  final ChapterRef? previous;

  /// Null after Openbaring 22.
  final ChapterRef? next;

  /// The study and lesson this chapter is. Every write uses these.
  final String studyId;
  final int lessonDay;

  /// The book study offered as "Heel (boek) als studie volgen".
  final String followStudyId;
  final String followStudyTitle;

  final bool enrolled;

  /// Already studied before, in any mode.
  final bool completed;

  final LessonPayload lesson;

  /// A book of one chapter: this chapter was the whole book study.
  bool get isWholeBook => ref.chapters == 1;

  /// Null when the response has no usable chapter or lesson.
  static ChapterStudy? fromJson(Map<String, dynamic> json) {
    final ref = ChapterRef.fromJson(json['ref']);
    final lesson = json['lesson'];
    final studyId = json['studyId'];
    final lessonDay = (json['lessonDay'] as num?)?.toInt();
    if (ref == null ||
        lesson is! Map<String, dynamic> ||
        studyId is! String ||
        studyId.isEmpty ||
        lessonDay == null) {
      return null;
    }
    final follow = json['followStudy'] is Map<String, dynamic>
        ? json['followStudy'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return ChapterStudy(
      ref: ref,
      previous: ChapterRef.fromJson(json['previous']),
      next: ChapterRef.fromJson(json['next']),
      studyId: studyId,
      lessonDay: lessonDay,
      followStudyId: follow['id'] as String? ?? studyId,
      followStudyTitle: follow['title'] as String? ?? ref.bookName,
      enrolled: json['enrolled'] as bool? ?? false,
      completed: json['completed'] as bool? ?? false,
      lesson: LessonPayload.fromJson(lesson),
    );
  }
}

/// Where a lesson row on the study detail screen opens, or null when it stays
/// locked.
///
/// Enrolled: the lesson inside the study. Not enrolled: a book study's
/// whole-chapter lesson opens as a single-chapter study, which needs no
/// enrollment and still counts toward the study. A theme study, or a lesson on
/// part of a chapter, has no such route - the chapter study would be a
/// different lesson than the row lists - so it stays locked until started.
String? lessonRowRoute({
  required CuratedStudy study,
  required StudyLesson lesson,
  required bool enrolled,
}) {
  if (enrolled) return '/studie/${study.id}/${lesson.day}';
  if (study.type != 'Boek') return null;
  final bounds = lesson.verseBounds;
  if (bounds != null && bounds.$1 != 1) return null;
  return chapterStudyRoute(lesson.book, lesson.chapter);
}
