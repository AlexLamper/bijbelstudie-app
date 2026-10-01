import '../../../core/data/bible_books.dart';
import '../../dashboard/data/resume_link.dart' show resolveBookName;

/// The server's book codes for "Bijbel in een jaar" (`BibleYearRef.code`,
/// `bible-year/mark`), in canonical order - index for index the same books as
/// [BibleBooks.all].
const List<String> planBookCodes = [
  'GEN', 'EXOD', 'LEV', 'NUM', 'DEUT', 'JOSH', 'JUDG', 'RUTH', '1SAM', '2SAM',
  '1KGS', '2KGS', '1CHR', '2CHR', 'EZRA', 'NEH', 'ESTH', 'JOB', 'PS', 'PROV',
  'ECCL', 'SONG', 'ISA', 'JER', 'LAM', 'EZEK', 'DAN', 'HOS', 'JOEL', 'AMOS',
  'OBAD', 'JONAH', 'MIC', 'NAH', 'HAB', 'ZEPH', 'HAG', 'ZECH', 'MAL',
  'MATT', 'MARK', 'LUKE', 'JOHN', 'ACTS', 'ROM', '1COR', '2COR', 'GAL', 'EPH',
  'PHIL', 'COL', '1THESS', '2THESS', '1TIM', '2TIM', 'TITUS', 'PHLM', 'HEB', 'JAS',
  '1PET', '2PET', '1JOHN', '2JOHN', '3JOHN', 'JUDE', 'REV',
];

/// The plan code of a book as the reader names it ("Genesis", "1 Korinthe",
/// an older spelling or a slug); null for a name that is not one of the 66.
String? planBookCode(String book) {
  final name = resolveBookName(book);
  if (name == null) return null;
  final index = BibleBooks.all.indexOf(name);
  return index < 0 ? null : planBookCodes[index];
}

/// The reader's Dutch book name for a plan code ("MATT" -> "Mattheüs").
String? planBookName(String code) {
  final index = planBookCodes.indexOf(code.toUpperCase());
  return index < 0 ? null : BibleBooks.all[index];
}
