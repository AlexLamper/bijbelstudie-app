// Pure display helpers for "Bijbel in een jaar", ported from the website's
// `lib/bibleYear/display.ts` so both clients say the same thing. Dates are
// plain 'YYYY-MM-DD' strings in the reader's own time zone; arithmetic runs on
// UTC midnights so a DST change never moves a day.

import '../data/bible_year_models.dart';

const List<BibleYearCatalogueEntry> kDefaultBibleYearCatalogue = [
  BibleYearCatalogueEntry(
    planKey: BibleYearPlanKey.jaar1,
    label: '1 jaar',
    totalDays: 365,
    minutesPerDay: 15,
  ),
  BibleYearCatalogueEntry(
    planKey: BibleYearPlanKey.jaar2,
    label: '2 jaar',
    totalDays: 730,
    minutesPerDay: 8,
  ),
];

const List<BibleYearTrackEntry> kDefaultBibleYearTracks = [
  BibleYearTrackEntry(
    track: BibleYearTrackKey.gemengd,
    label: 'Gemengd',
    description:
        'Elke dag een stuk uit het Oude Testament, uit het Nieuwe Testament en uit Psalmen of Spreuken. Alle drie zijn ze op de laatste dag klaar.',
  ),
  BibleYearTrackEntry(
    track: BibleYearTrackKey.canoniek,
    label: 'Van Genesis tot Openbaring',
    description:
        'De Bijbel in de volgorde van de boeken, van het eerste hoofdstuk tot het laatste.',
  ),
];

const BibleYearPlanKey kDefaultBibleYearPlan = BibleYearPlanKey.jaar1;
const BibleYearTrackKey kDefaultBibleYearTrack = BibleYearTrackKey.gemengd;

const int kBibleChapterCount = 1189;

/// Furthest start date the flow accepts: a year and a day ahead.
const int kMaxStartDaysAhead = 366;

/* ── Dates ─────────────────────────────────────────────────────────────── */

const _months = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];
// DateTime.weekday: 1 = maandag .. 7 = zondag.
const _weekdays = [
  'maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag',
];

final RegExp _isoPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? _utc(String iso) {
  if (!_isoPattern.hasMatch(iso)) return null;
  final y = int.parse(iso.substring(0, 4));
  final m = int.parse(iso.substring(5, 7));
  final d = int.parse(iso.substring(8, 10));
  final date = DateTime.utc(y, m, d);
  // DateTime rolls 2026-02-30 over into March; a real date round-trips.
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}

String isoDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
}

/// A real calendar date in 'YYYY-MM-DD' form (rejects 2026-02-30).
bool isIsoDate(String? value) => value != null && _utc(value) != null;

String addDays(String date, int days) {
  final d = _utc(date);
  if (d == null) return date;
  return isoDate(d.add(Duration(days: days)));
}

/// Whole days from [from] to [to] (negative when [to] is earlier).
int daysBetween(String from, String to) {
  final a = _utc(from);
  final b = _utc(to);
  if (a == null || b == null) return 0;
  return (b.difference(a).inHours / 24).round();
}

/// Today on this device's clock, which is the reader's own time zone.
String deviceToday([DateTime? now]) => isoDate(now ?? DateTime.now());

/// The first 1 January that is today or later.
String nextNewYear(String today) {
  if (today.length >= 10 && today.substring(5) == '01-01') return today;
  return '${int.parse(today.substring(0, 4)) + 1}-01-01';
}

enum StartDateChoice { vandaag, nieuwjaar, kies }

class StartDateOption {
  const StartDateOption({required this.id, required this.label, this.date});

  final StartDateChoice id;
  final String label;
  final String? date;
}

/// "1 januari" is dropped on 1 January itself, where it equals "Vandaag".
List<StartDateOption> startDateOptions(String today) {
  final newYear = nextNewYear(today);
  return [
    StartDateOption(id: StartDateChoice.vandaag, label: 'Vandaag', date: today),
    if (newYear != today)
      StartDateOption(id: StartDateChoice.nieuwjaar, label: '1 januari', date: newYear),
    const StartDateOption(id: StartDateChoice.kies, label: 'Kies een datum'),
  ];
}

/// A Dutch error for an unusable start date, or null when it is fine.
String? startDateError(String? date, String today) {
  if (date == null || !isIsoDate(date)) return 'Kies een geldige datum.';
  if (date.compareTo(today) < 0) return 'Kies vandaag of een latere datum.';
  if (daysBetween(today, date) > kMaxStartDaysAhead) return 'Kies een datum binnen een jaar.';
  return null;
}

/// start + totalDays - 1 + shiftDays, as the contract defines expectedEndDate.
String planEndDate(String startDate, int totalDays, [int shiftDays = 0]) =>
    addDays(startDate, totalDays - 1 + shiftDays);

/// The end date after "Schema verschuiven" moves the schedule by behindDays.
String shiftedEndDate(BibleYearToday today) =>
    addDays(today.expectedEndDate, today.behindDays < 0 ? 0 : today.behindDays);

/// The calendar date a schedule day falls on for this enrollment.
String scheduleDayDate(String startDate, int shiftDays, int day) =>
    addDays(startDate, day - 1 + shiftDays);

/// "1 oktober 2026", or with [weekday] "donderdag 1 oktober".
String formatDutchDate(String date, {bool weekday = false, bool? year}) {
  final d = _utc(date);
  if (d == null) return date;
  final showYear = year ?? !weekday;
  final core = '${d.day} ${_months[d.month - 1]}';
  final withYear = showYear ? '$core ${d.year}' : core;
  return weekday ? '${_weekdays[d.weekday - 1]} $withYear' : withYear;
}

/* ── Copy ──────────────────────────────────────────────────────────────── */

String dayOfPlanLabel(int day, int totalDays) => 'Dag $day van $totalDays';

String daysWord(int n) => n == 1 ? '1 dag' : '$n dagen';

/// Gentle, never a deadline.
String? behindLabel(int behindDays) =>
    behindDays > 0 ? 'Je loopt ${daysWord(behindDays)} achter' : null;

String? aheadLabel(int aheadDays) =>
    aheadDays > 0 ? 'Je loopt ${daysWord(aheadDays)} voor' : null;

/// "12%", "0,4%", "100%": one decimal only below 10, a Dutch comma.
String formatPercent(double percent) {
  final p = percent.isFinite ? percent.clamp(0.0, 100.0) : 0.0;
  if (p >= 10 || p == p.roundToDouble()) return '${p.floor()}%';
  final one = (p * 10).floor() / 10;
  final text = one == one.roundToDouble() ? '${one.toInt()}' : one.toString();
  return '${text.replaceAll('.', ',')}%';
}

String minutesLabel(int minutes) => 'ongeveer ${minutes < 1 ? 1 : minutes} min';

String planLabel(BibleYearPlanKey key, [List<BibleYearCatalogueEntry> catalogue = const []]) {
  for (final entry in [...catalogue, ...kDefaultBibleYearCatalogue]) {
    if (entry.planKey == key) return entry.label;
  }
  return key.id;
}

String trackLabel(BibleYearTrackKey key, [List<BibleYearTrackEntry> tracks = const []]) {
  for (final entry in [...tracks, ...kDefaultBibleYearTracks]) {
    if (entry.track == key) return entry.label;
  }
  return key.id;
}

/// Strand headings for a portion. The canonical track has a single strand.
const Map<String, String> kStrandLabel = {
  'ot': 'Oude Testament',
  'nt': 'Nieuwe Testament',
  'poetry': 'Psalmen en Spreuken',
  'all': 'Lezen',
};

/// "Genesis 4"; Psalmen reads singular, as a heading would say it.
String chapterName(String book, int chapter) =>
    '${book == 'Psalmen' ? 'Psalm' : book} $chapter';

/// "Mm:uu" for a reminder time in minutes after midnight.
String formatClock(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/* ── State updates ─────────────────────────────────────────────────────── */

/// The optimistic version of a mark: flips `read` on the matching refs, then
/// recomputes each portion's `done` and `todayDone`. The server response
/// replaces it a moment later.
BibleYearToday applyRefMark(
  BibleYearToday today,
  Iterable<BibleYearChapterKey> refs,
  bool read,
) {
  final keys = {for (final r in refs) '${r.code}:${r.chapter}'};
  final portions = [
    for (final portion in today.portions)
      () {
        final next = [
          for (final ref in portion.refs) keys.contains(ref.key) ? ref.copyWith(read: read) : ref,
        ];
        return portion.copyWith(
          refs: next,
          done: next.isNotEmpty && next.every((r) => r.read),
        );
      }(),
  ];
  return today.copyWith(
    portions: portions,
    todayDone: portions.isNotEmpty && portions.every((p) => p.done),
  );
}

/// The days after today, for the "Komende dagen" overview.
List<BibleYearScheduleDay> upcomingDays(BibleYearSchedule schedule, int fromDay, int count) =>
    schedule.days.where((d) => d.day > fromDay).take(count < 0 ? 0 : count).toList(growable: false);

/// One line for a schedule day: "Genesis 1-3 · Mattheüs 1 · Psalm 1".
String scheduleDaySummary(BibleYearScheduleDay day) =>
    day.portions.map((p) => p.label).join(' · ');
