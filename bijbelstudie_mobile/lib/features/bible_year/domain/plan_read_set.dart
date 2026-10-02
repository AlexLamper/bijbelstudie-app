import '../../../core/data/bible_books.dart';
import '../data/bible_year_models.dart';
import 'plan_book_codes.dart';

/// Every chapter the reader has read, as `readRefs` keys ("GEN.1"), merged
/// from every source the app has. [PlanCalendar] decides "gelezen" on this
/// one set, so the reader's plan bar, Vandaag, Schema, the week strip and the
/// percentage can never disagree.
///
/// Why a merge is needed: `GET /api/v1/bible-year` answers with
/// `BibleYearEnrollmentDTO` (`lib/bibleYear/progress.ts toEnrollmentDTO` in
/// the website repo), which carries the *counts* - `chaptersRead` and
/// `percentBible` - but never the `readRefs` list itself. So the enrollment
/// this app parses always has an empty set, and every mutation response
/// replaces the optimistic one with an empty set again. Nothing outside the
/// single day the server describes in `today` could ever render as read.
///
/// The sources, in order of authority:
///
/// - [enrollmentRefs] - the server's own list, for when the API starts
///   sending it (then this merge is a no-op on top of it).
/// - [today] - the read flag the server sets on each ref of today's portions.
///   Authoritative for today, and refreshed by every mark response.
/// - [readChapters] - `GET /api/v1/dashboard`'s 66-book read map, which is
///   what `POST /last-read` fills. This is how chapters read in the normal
///   reader - before the plan, or on another device - count towards the plan.
/// - [deviceRead] / [deviceUnread] - what this device ticked and unticked
///   ([PlanReadStore]), so a tick sticks at once and offline, and an untick
///   is not undone by the dashboard map on the next frame.
Set<String> planReadRefKeys({
  Set<String> enrollmentRefs = const {},
  BibleYearToday? today,
  Map<String, List<int>> readChapters = const {},
  Set<String> deviceRead = const {},
  Set<String> deviceUnread = const {},
}) {
  final out = <String>{...enrollmentRefs, ...deviceRead};
  if (today != null) {
    for (final portion in today.portions) {
      for (final ref in portion.refs) {
        if (ref.read) out.add(ref.refKey);
      }
    }
  }
  readChapters.forEach((book, chapters) {
    final code = planBookCode(book);
    if (code == null) return;
    // A chapter number past the book cannot be a chapter of the plan, and a
    // live account's read map does hold stray numbers.
    final last = BibleBooks.chaptersIn(planBookName(code) ?? book);
    for (final chapter in chapters) {
      if (chapter >= 1 && chapter <= last) out.add(bibleYearRefKey(code, chapter));
    }
  });
  // An untick on this device wins over the read map, which `/last-read` keeps
  // whatever the plan says.
  return deviceUnread.isEmpty ? out : out.difference(deviceUnread);
}
