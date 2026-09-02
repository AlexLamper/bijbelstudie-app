import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/data/bible_books.dart';
import 'package:bijbelstudie_mobile/features/dashboard/data/dashboard_models.dart';

void main() {
  group('BibleBooks.toCanonical', () {
    test('leaves canonical names untouched', () {
      expect(BibleBooks.toCanonical('Genesis'), 'Genesis');
      expect(BibleBooks.toCanonical('1 Korinthe'), '1 Korinthe');
      expect(BibleBooks.toCanonical('Openbaring'), 'Openbaring');
    });

    test('folds Statenvertaling and English spellings onto the canon', () {
      expect(BibleBooks.toCanonical('Numberi'), 'Numeri'); // source-data typo
      expect(BibleBooks.toCanonical('1 Corinthiërs'), '1 Korinthe');
      expect(BibleBooks.toCanonical('2 Corinthiër'), '2 Korinthe');
      expect(BibleBooks.toCanonical('Colossenzen'), 'Kolossenzen');
      expect(BibleBooks.toCanonical('Matthew'), 'Mattheüs');
      expect(BibleBooks.toCanonical('John'), 'Johannes');
    });

    test('passes an unknown name through unchanged', () {
      expect(BibleBooks.toCanonical('Nergensboek'), 'Nergensboek');
    });
  });

  group('DashboardData.booksStarted', () {
    DashboardData parse(Map<String, dynamic> readChapters) => DashboardData.fromJson({
      'user': {'name': 'Test', 'isPro': false},
      'streak': 0,
      'readChapters': readChapters,
    });

    test('counts every distinct book with a chapter read', () {
      final data = parse({
        'Genesis': [1, 2],
        'Ruth': [1, 2, 3, 4],
        'Openbaring': [1],
      });
      expect(data.booksStarted, 3);
    });

    test('merges keys that only differ in spelling', () {
      // Genesis reached via a Dutch key and Numeri via the "Numberi" typo plus
      // its canonical name — three raw keys, two distinct books.
      final data = parse({
        'Genesis': [1],
        'Numberi': [3, 1],
        'Numeri': [1, 2],
      });
      expect(data.booksStarted, 2);
      expect(data.readChapters['Numeri'], [1, 2, 3]);
      expect(data.readChapters.containsKey('Numberi'), isFalse);
    });

    test('is not fooled by an English-keyed translation', () {
      final data = parse({
        'John': [1, 3],
        'Johannes': [3],
        'Matthew': [5],
      });
      expect(data.booksStarted, 2);
      expect(data.readChapters['Johannes'], [1, 3]);
      expect(data.readChapters['Mattheüs'], [5]);
    });

    test('handles a missing readChapters field', () {
      final data = DashboardData.fromJson({
        'user': {'name': 'Test', 'isPro': false},
        'streak': 0,
      });
      expect(data.booksStarted, 0);
    });

    // `$*` is the schema path of the server's readChapters Map and sat as a
    // literal key on live accounts. It reached the app once the API stopped
    // dropping the whole map over it, and `chapters as List?` threw on its
    // object value - one bad key would have taken the dashboard down.
    test('ignores a key that is not a book, and keeps the books beside it', () {
      final data = parse({
        r'$*': {'0': 1},
        'a.b': [1],
        'Genesis': [4],
        'Ruth': [1, 2],
      });
      expect(data.booksStarted, 2);
      expect(data.readChapters['Genesis'], [4]);
      expect(data.readChapters.containsKey(r'$*'), isFalse);
    });

    test('ignores a value that is not a chapter list', () {
      final data = parse({
        'Genesis': {'0': 1},
        'Ruth': 'nope',
        'Job': [1, 2],
      });
      expect(data.booksStarted, 1);
      expect(data.readChapters['Job'], [1, 2]);
    });

    test('does not count a book the fold did not recognise', () {
      // The grid draws 66 squares, so "… van 66" must not exceed them.
      final data = parse({
        'Genesis': [1],
        'Nergensboek': [1, 2],
      });
      expect(data.booksStarted, 1);
    });
  });
}
