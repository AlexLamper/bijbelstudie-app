// Turns a resume item's `href` - a path on www.bijbelstudie.io - into the place
// the app opens for it. Pure, so every shape the server may send is unit
// tested without a router.

import '../../../core/data/bible_books.dart';
import '../../studies/data/enrollment_models.dart';

/// `/studies/bijbel-in-een-jaar` is registered in `core/router/app_router.dart`
/// (before `/studies/:id`). Set back to false only if that route goes away:
/// the path would then be caught by `/studies/:id` and open a study detail
/// screen for a study that does not exist, so it falls back to the Studies tab.
const bool kBibleYearRouteAvailable = true;

const String bibleYearPath = '/studies/bijbel-in-een-jaar';

sealed class ResumeTarget {
  const ResumeTarget();
}

/// A go_router location, pushed as is.
class ResumeRoute extends ResumeTarget {
  const ResumeRoute(this.location);

  final String location;

  /// Tab roots are switched to with `go`; everything else is pushed so the
  /// back arrow returns to the Start tab.
  bool get isTab => const {'/dashboard', '/studies', '/study', '/notes', '/profile'}
      .contains(location);

  @override
  bool operator ==(Object other) => other is ResumeRoute && other.location == location;

  @override
  int get hashCode => location.hashCode;

  @override
  String toString() => 'ResumeRoute($location)';
}

/// A Bible chapter, opened through the reader's own location controller.
class ResumeChapter extends ResumeTarget {
  const ResumeChapter({required this.book, required this.chapter, this.version});

  final String book;
  final int chapter;
  final String? version;

  @override
  bool operator ==(Object other) =>
      other is ResumeChapter &&
      other.book == book &&
      other.chapter == chapter &&
      other.version == version;

  @override
  int get hashCode => Object.hash(book, chapter, version);

  @override
  String toString() => 'ResumeChapter($book $chapter, $version)';
}

const ResumeTarget _home = ResumeRoute('/dashboard');

/// Maps [href] to where the app should go. Anything it does not recognise
/// lands on the Start tab rather than on a broken screen.
ResumeTarget resumeTargetFor(
  String href, {
  bool bibleYearRoute = kBibleYearRouteAvailable,
}) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return _home;
  if (uri.hasScheme && !(uri.host.endsWith('bijbelstudie.io') || uri.host == 'localhost')) {
    return _home;
  }

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: false);
  if (segments.isEmpty) return _home;
  final query = uri.queryParameters;

  switch (segments.first) {
    case 'studie':
      return _studyTarget(segments, query);
    case 'studies':
      if (segments.length == 1) return const ResumeRoute('/studies');
      if (segments[1] == 'bijbel-in-een-jaar') {
        return ResumeRoute(bibleYearRoute ? bibleYearPath : '/studies');
      }
      if (segments.length == 2) return ResumeRoute('/studies/${Uri.encodeComponent(segments[1])}');
      return const ResumeRoute('/studies');
    case 'lezen':
    case 'bijbel':
      // `/lezen?book=` carries the stored spelling - the translation's own
      // name for the book, which is what the reader resolves its folder by -
      // so it is passed on verbatim. Path forms carry a name or a slug.
      final fromQuery = segments.length < 2;
      final rawBook = fromQuery ? query['book'] : segments[1];
      final rawChapter = segments.length >= 3 ? segments[2] : query['chapter'];
      final book = fromQuery ? _nonEmpty(rawBook) : resolveBookName(rawBook);
      if (book == null) return const ResumeRoute('/study');
      return ResumeChapter(
        book: book,
        chapter: _positive(rawChapter) ?? 1,
        version: _nonEmpty(query['version']),
      );
    case 'dashboard':
      return _home;
    default:
      return _home;
  }
}

ResumeTarget _studyTarget(List<String> segments, Map<String, String> query) {
  final step = _stepQuery(query['stap']);

  // /studie/hoofdstuk/<book>/<chapter> - one chapter studied on its own.
  if (segments.length >= 4 && segments[1] == 'hoofdstuk') {
    final chapter = _positive(segments[3]);
    if (chapter == null) return _home;
    return ResumeRoute(
      '/studie/hoofdstuk/${Uri.encodeComponent(segments[2])}/$chapter$step',
    );
  }

  if (segments.length >= 3) {
    final day = _positive(segments[2]);
    if (day == null) return _home;
    return ResumeRoute('/studie/${Uri.encodeComponent(segments[1])}/$day$step');
  }

  // /studie/<id> without a day: the website redirects to the enrollment's
  // lesson; the app's study screen does the same from its "Verder" button.
  if (segments.length == 2) {
    return ResumeRoute('/studies/${Uri.encodeComponent(segments[1])}');
  }
  return _home;
}

/// `?stap=<id>` for a step this build renders, else nothing: a lesson opened
/// on an unknown step id would have nowhere to land.
String _stepQuery(String? raw) {
  final step = StudyStep.tryFromId(raw);
  if (step == null || step == StudyStep.done) return '';
  return '?stap=${step.id}';
}

/// The canonical Dutch name for a book as a link spells it: a Dutch name
/// ("1 Korinthe"), an older spelling, an English name, or a web slug
/// ("1-korinthe", "mattheus"). Unrecognised names come back readable (dashes
/// as spaces) so the reader's own book list can still try them.
String? resolveBookName(String? raw) {
  final name = raw?.trim() ?? '';
  if (name.isEmpty) return null;

  final canonical = BibleBooks.toCanonical(name);
  if (BibleBooks.all.contains(canonical)) return canonical;

  final key = _slugKey(name);
  for (final book in BibleBooks.all) {
    if (_slugKey(book) == key) return book;
  }
  final spaced = name.replaceAll('-', ' ');
  final again = BibleBooks.toCanonical(spaced);
  if (BibleBooks.all.contains(again)) return again;
  return spaced;
}

const Map<String, String> _folds = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
};

String _slugKey(String name) {
  final buffer = StringBuffer();
  for (final char in name.toLowerCase().split('')) {
    final folded = _folds[char] ?? char;
    if (RegExp(r'[a-z0-9]').hasMatch(folded)) buffer.write(folded);
  }
  return buffer.toString();
}

int? _positive(String? raw) {
  final value = int.tryParse(raw?.trim() ?? '');
  return value == null || value < 1 ? null : value;
}

String? _nonEmpty(String? raw) {
  final value = raw?.trim() ?? '';
  return value.isEmpty ? null : value;
}
