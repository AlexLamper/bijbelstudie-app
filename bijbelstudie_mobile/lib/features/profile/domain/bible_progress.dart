import '../../../core/data/bible_books.dart';

/// "Bijbel gelezen": the 66 books with the reader's progress laid over them.
///
/// Pure aggregation over a `readChapters` map (book name -> chapter numbers),
/// mirroring `lib/bibleProgress.ts` on the website. Keys are folded through
/// [BibleBooks.toCanonical] so a translation's own spelling counts towards the
/// right book; unknown books and chapters outside 1..count are ignored, so the
/// totals can never pass 66 books or 1189 chapters.
class BookProgress {
  const BookProgress({
    required this.name,
    required this.isNewTestament,
    required this.chapters,
    required this.readChapters,
  });

  /// Canonical Dutch name, as [BibleBooks] spells it.
  final String name;
  final bool isNewTestament;
  final int chapters;

  /// Sorted, unique, all within 1..[chapters].
  final List<int> readChapters;

  int get readCount => readChapters.length;
  bool get started => readCount > 0;
  bool get completed => chapters > 0 && readCount >= chapters;

  /// 0-100, rounded down so a book never shows 100 before it is finished.
  int get percent => _floorPercent(readCount, chapters).floor();

  bool isRead(int chapter) => readChapters.contains(chapter);
}

enum BookFilter {
  all('Alles'),
  started('Begonnen'),
  completed('Voltooid'),
  notStarted('Nog niet begonnen');

  const BookFilter(this.label);
  final String label;

  /// "Begonnen" means underway: started but not yet finished.
  bool matches(BookProgress book) => switch (this) {
        BookFilter.all => true,
        BookFilter.started => book.started && !book.completed,
        BookFilter.completed => book.completed,
        BookFilter.notStarted => !book.started,
      };
}

class BibleProgress {
  const BibleProgress._(this.books);

  factory BibleProgress.fromReadChapters(Map<String, List<int>> raw) {
    final byBook = <String, Set<int>>{};
    raw.forEach((key, chapters) {
      final name = BibleBooks.toCanonical(key);
      if (!BibleBooks.chapterCounts.containsKey(name)) return;
      byBook.putIfAbsent(name, () => <int>{}).addAll(chapters.where((n) => n >= 1));
    });

    final books = <BookProgress>[
      for (final name in BibleBooks.all)
        BookProgress(
          name: name,
          isNewTestament: BibleBooks.newTestament.contains(name),
          chapters: BibleBooks.chapterCounts[name] ?? 0,
          readChapters: ((byBook[name] ?? const <int>{})
                  .where((n) => n <= (BibleBooks.chapterCounts[name] ?? 0))
                  .toList()
                ..sort())
              .toList(growable: false),
        ),
    ];
    return BibleProgress._(List.unmodifiable(books));
  }

  final List<BookProgress> books;

  List<BookProgress> get oldTestament =>
      books.where((b) => !b.isNewTestament).toList(growable: false);
  List<BookProgress> get newTestament =>
      books.where((b) => b.isNewTestament).toList(growable: false);

  int get chaptersRead => books.fold(0, (sum, b) => sum + b.readCount);
  int get chaptersTotal => books.fold(0, (sum, b) => sum + b.chapters);
  int get booksStarted => books.where((b) => b.started).length;
  int get booksCompleted => books.where((b) => b.completed).length;
  int get booksTotal => books.length;

  /// Share of all chapters read, 0-100 with one decimal, rounded down.
  double get percent =>
      (_floorPercent(chaptersRead, chaptersTotal) * 10).floor() / 10;

  List<BookProgress> filtered(List<BookProgress> source, BookFilter filter) =>
      source.where(filter.matches).toList(growable: false);
}

double _floorPercent(int part, int whole) {
  if (whole <= 0 || part <= 0) return 0;
  if (part >= whole) return 100;
  return part / whole * 100;
}
