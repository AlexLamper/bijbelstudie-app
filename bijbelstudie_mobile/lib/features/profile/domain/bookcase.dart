import '../../../core/data/bible_books.dart';
import '../../dashboard/domain/bible_milestones.dart';
import 'bible_progress.dart';
import 'profile_stats.dart';

/// The pure side of the "Je boekenkast" page: spine labels, the shelf
/// summary, the reading table and the ladder steps. Everything here is built
/// from numbers `/api/v1/dashboard` already returns. Mirrors `lib/bookcase.ts`
/// on the website; keep the two in step.

/// The short title printed on a spine, as the Dutch Bible abbreviates it.
const Map<String, String> spineLabels = {
  'Genesis': 'Gen', 'Exodus': 'Ex', 'Leviticus': 'Lev', 'Numeri': 'Num',
  'Deuteronomium': 'Deut', 'Jozua': 'Joz', 'Richteren': 'Richt', 'Ruth': 'Ruth',
  '1 Samuël': '1 Sam', '2 Samuël': '2 Sam', '1 Koningen': '1 Kon', '2 Koningen': '2 Kon',
  '1 Kronieken': '1 Kron', '2 Kronieken': '2 Kron', 'Ezra': 'Ezra', 'Nehemia': 'Neh',
  'Esther': 'Est', 'Job': 'Job', 'Psalmen': 'Ps', 'Spreuken': 'Spr',
  'Prediker': 'Pred', 'Hooglied': 'Hoogl', 'Jesaja': 'Jes', 'Jeremia': 'Jer',
  'Klaagliederen': 'Klaagl', 'Ezechiël': 'Ez', 'Daniël': 'Dan', 'Hosea': 'Hos',
  'Joël': 'Joël', 'Amos': 'Am', 'Obadja': 'Ob', 'Jona': 'Jona', 'Micha': 'Mi',
  'Nahum': 'Nah', 'Habakuk': 'Hab', 'Zefanja': 'Zef', 'Haggaï': 'Hag',
  'Zacharia': 'Zach', 'Maleachi': 'Mal', 'Mattheüs': 'Matt', 'Markus': 'Mark',
  'Lukas': 'Luk', 'Johannes': 'Joh', 'Handelingen': 'Hand', 'Romeinen': 'Rom',
  '1 Korinthe': '1 Kor', '2 Korinthe': '2 Kor', 'Galaten': 'Gal', 'Efeziërs': 'Ef',
  'Filippenzen': 'Fil', 'Kolossenzen': 'Kol', '1 Thessalonicenzen': '1 Tess',
  '2 Thessalonicenzen': '2 Tess', '1 Timotheüs': '1 Tim', '2 Timotheüs': '2 Tim',
  'Titus': 'Tit', 'Filémon': 'Filem', 'Hebreeën': 'Hebr', 'Jakobus': 'Jak',
  '1 Petrus': '1 Petr', '2 Petrus': '2 Petr', '1 Johannes': '1 Joh', '2 Johannes': '2 Joh',
  '3 Johannes': '3 Joh', 'Judas': 'Jud', 'Openbaring': 'Openb',
};

/// The name on a brass plaque under each of the six book groups, in the order
/// of `BibleBookGroup.all`. Shorter than the group labels so it fits the board.
const List<String> shelfPlaques = [
  'De Wet',
  'Geschiedenis',
  'Poëzie',
  'Profeten',
  'Evangeliën',
  'Brieven',
];

/// A whole number with the Dutch thousands separator: 1189 -> "1.189".
String formatShelfCount(int n) {
  final digits = (n < 0 ? 0 : n).toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

String _books(int n) => n == 1 ? 'boek' : 'boeken';

/// "5 boeken uit, 4 aan het lezen" under the page title.
String shelfSummary(BibleProgress p) {
  final done = p.booksCompleted;
  final reading = p.booksStarted - p.booksCompleted;
  if (done == 0 && reading == 0) return 'Nog geen hoofdstuk gelezen';
  if (done >= p.booksTotal) return 'Alle ${p.booksTotal} boeken uit';
  if (done == 0) return '$reading ${_books(reading)} aan het lezen';
  if (reading == 0) return '$done ${_books(done)} uit';
  return '$done ${_books(done)} uit, $reading aan het lezen';
}

/// The first chapter of [book] not yet read, or 1 once the book is finished.
int firstUnreadChapter(BookProgress book) {
  for (var n = 1; n <= book.chapters; n++) {
    if (!book.isRead(n)) return n;
  }
  return 1;
}

/// "Op je leestafel": the books started but not finished, the one the
/// leeslint lies in first, the rest in canonical order.
List<BookProgress> readingTable(BibleProgress p, {String? current}) {
  final open = p.books.where((b) => b.started && !b.completed).toList();
  final at = open.indexWhere((b) => b.name == current);
  if (at > 0) open.insert(0, open.removeAt(at));
  return open;
}

/// Books finished now that were not in [before]. Null [before] means the
/// shelf was never seen on this device, and a first look is not news.
List<String> newlyFinishedBooks({required Set<String>? before, required BibleProgress now}) {
  if (before == null) return const [];
  return [
    for (final b in now.books)
      if (b.completed && !before.contains(b.name)) b.name,
  ];
}

/// "Exodus", "Exodus en Ruth", "Exodus, Ruth en Jona", "4 boeken".
String joinBookNames(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length > 3) return '${names.length} boeken';
  return '${names.sublist(0, names.length - 1).join(', ')} en ${names.last}';
}

/// What a rung of "De ladder op" measures.
enum LadderTrack { bible, books, streak }

/// One rung under "De ladder op": the next step on one track, with how far
/// along the reader is.
class LadderStep {
  const LadderStep({
    required this.track,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.target,
  });

  final LadderTrack track;
  final String title;
  final String subtitle;
  final int value;
  final int target;

  double get fraction => target <= 0 ? 1 : (value / target).clamp(0.0, 1.0).toDouble();
}

String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The next rung on each of three tracks: the Bible milestones the ladder on
/// the case shows, and the books-opened and streak badges the profile counts
/// towards ([BadgeCatalog.milestones]). Measured from where the reader stands
/// now, so a streak that broke climbs from its new run. A track with nothing
/// left to reach drops out. `ladderSteps` in `lib/bookcase.ts` is the same.
List<LadderStep> ladderSteps({
  required int chaptersRead,
  required int chaptersTotal,
  required int booksStarted,
  required int streak,
}) {
  final out = <LadderStep>[];

  final milestone = nextBibleMilestone(chaptersRead, chaptersTotal);
  if (milestone != null) {
    final need = milestone.chaptersNeeded(chaptersTotal);
    final left = need - chaptersRead;
    out.add(
      LadderStep(
        track: LadderTrack.bible,
        title: milestone == BibleMilestone.whole
            ? 'De hele Bijbel'
            : '${_capitalised(milestone.target)} van de Bijbel',
        subtitle: 'Nog ${formatShelfCount(left)} ${left == 1 ? 'hoofdstuk' : 'hoofdstukken'}',
        value: chaptersRead,
        target: need,
      ),
    );
  }

  BadgeDefinition? next(BadgeTrack track, int value) {
    for (final d in BadgeCatalog.milestones) {
      if (d.track == track && value < d.target) return d;
    }
    return null;
  }

  final books = next(BadgeTrack.books, booksStarted);
  if (books != null) {
    out.add(
      LadderStep(
        track: LadderTrack.books,
        title: books.label,
        subtitle: '${books.target} boeken geopend, nu $booksStarted',
        value: booksStarted,
        target: books.target,
      ),
    );
  }

  final days = next(BadgeTrack.streak, streak);
  if (days != null) {
    out.add(
      LadderStep(
        track: LadderTrack.streak,
        title: days.label,
        subtitle: '${days.target} dagen op rij, nu $streak',
        value: streak,
        target: days.target,
      ),
    );
  }
  return out;
}

/// Canonical position of every book, 0-65.
final Map<String, int> canonIndex = () {
  final order = BibleBooks.all;
  return {for (var i = 0; i < order.length; i++) order[i]: i};
}();

/// A stable 0-1 value per book and purpose, so every spine keeps its height
/// and shade from one visit to the next. The same integer hash as
/// `shelfJitter` in `lib/bookcase.ts`, so app and website draw the same case.
double shelfJitter(int index, int salt) {
  var h = (index * 374761393 + salt * 668265263) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
  h = h ^ (h >> 16);
  return h / 4294967296;
}
