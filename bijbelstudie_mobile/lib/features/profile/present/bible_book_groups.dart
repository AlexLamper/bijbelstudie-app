import '../../../core/data/bible_books.dart';

/// The six bands the Bijbelvoortgang page sorts the 66 books into.
///
/// Same slices of the canon as [CanonGroup] in `core/data/bible_books.dart`,
/// which the "alle studies per bijbelboek" overview uses, but with the shorter
/// labels this page asks for ("Poëzie", not "Poëzie en wijsheid"). The slices
/// are taken from [BibleBooks.oldTestament] and [BibleBooks.newTestament] so
/// every group keeps the canonical order and the six of them together are
/// exactly [BibleBooks.all] - `test/bible_book_groups_test.dart` asserts that.
class BibleBookGroup {
  const BibleBookGroup(this.label, this.books);

  final String label;

  /// The group's books, in canonical order, spelled as [BibleBooks] spells
  /// them.
  final List<String> books;

  int get bookCount => books.length;

  /// All chapters in this group, the denominator of its progress.
  int get chapterCount =>
      books.fold(0, (sum, book) => sum + BibleBooks.chaptersIn(book));

  static final List<BibleBookGroup> all = [
    BibleBookGroup('Wet', BibleBooks.oldTestament.sublist(0, 5)),
    BibleBookGroup('Geschiedenis', BibleBooks.oldTestament.sublist(5, 17)),
    BibleBookGroup('Poëzie', BibleBooks.oldTestament.sublist(17, 22)),
    BibleBookGroup('Profeten', BibleBooks.oldTestament.sublist(22, 39)),
    BibleBookGroup('Evangeliën en Handelingen', BibleBooks.newTestament.sublist(0, 5)),
    BibleBookGroup('Brieven en Openbaring', BibleBooks.newTestament.sublist(5, 27)),
  ];

  /// The groups of one testament, for the Oude T. / Nieuwe T. filter. The
  /// first four groups are the Oude Testament, the last two the Nieuwe.
  static List<BibleBookGroup> forTestament({required bool newTestament}) =>
      newTestament ? all.sublist(4) : all.sublist(0, 4);
}
