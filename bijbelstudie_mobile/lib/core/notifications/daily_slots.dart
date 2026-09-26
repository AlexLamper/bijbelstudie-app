import 'notification_copy.dart';
import 'notification_schedule.dart';
import 'notification_service.dart' show NotifType, QuietHours, RenderedVariant;

/// The owner's rule (DAILY_HABIT_PLAN.md §1): never more than this many
/// notifications on one calendar day, whatever their type. Enforced in one
/// place, `applyDailyCap` in notification_scheduler.dart.
const int kMaxNotificationsPerDay = 2;

/// Which kinds of task the daily slots may be about (Instellingen > Meldingen >
/// Inhoud). `chapter` and `other` have no switch: a plain reading reminder is
/// what is left when everything else is off.
class DailyContentPrefs {
  const DailyContentPrefs({this.verse = true, this.plan = true, this.study = true});

  final bool verse;
  final bool plan;
  final bool study;

  bool allows(ScheduleKind kind) => switch (kind) {
        ScheduleKind.bibleYear => plan,
        ScheduleKind.study => study,
        ScheduleKind.verse => verse,
        ScheduleKind.chapter || ScheduleKind.other => true,
      };

  /// `exclude` for `/notifications/schedule`: the kinds switched off, in a
  /// fixed order (it is part of the schedule cache key). Empty when all on.
  String get excludeParam => [
        if (!plan) 'bibleYear',
        if (!study) 'study',
        if (!verse) 'verse',
      ].join(',');
}

/// What the device knows without the schedule endpoint: the study in progress
/// (from the enrollments the scheduler already loads), if any.
class LocalDailyFallback {
  const LocalDailyFallback({this.studyTitle, this.lessonLabel, this.studyRoute});

  static const none = LocalDailyFallback();

  final String? studyTitle;
  final String? lessonLabel;

  /// `/studie/<id>/<day>?stap=<step>`; null when no study is running.
  final String? studyRoute;

  bool get hasStudy => studyRoute != null;
}

/// One daily slot's rendered notification.
class DailyLine {
  const DailyLine({
    required this.kind,
    required this.variant,
    required this.route,
  });

  final ScheduleKind kind;
  final RenderedVariant variant;
  final String route;
}

/// Android shows about this much of a collapsed body; the server uses the same.
const int kDailyBodyMax = 110;

/// Cuts at a word boundary and adds an ellipsis (the server's `shorten`).
String shortenLine(String text, int max) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= max) return clean;
  final cut = clean.substring(0, (max - 1).clamp(1, clean.length));
  final space = cut.lastIndexOf(' ');
  final head = space > max / 3 ? cut.substring(0, space) : cut;
  return '${head.replaceAll(RegExp(r'[\s.,;:!?·-]+$'), '')}…';
}

/// `“verse…” Reference`, within the body limit - the server's `verseBody`.
String verseLine(ScheduleVerse verse) {
  final room = kDailyBodyMax - verse.reference.length - 3;
  return '“${shortenLine(verse.text, room)}” ${verse.reference}';
}

/// The morning and evening for one date.
///
/// The schedule is fetched with the switched-off kinds as `exclude`, so the
/// server already falls through to the next task and leaves the verse out;
/// its content is used as sent. What is checked here is only a response that
/// was not built for the current toggles (a cache from before a toggle
/// change, offline): a kind that is switched off, or a verse while "Tekst van
/// de dag" is off, is replaced by what the device can fill itself - the study
/// in progress (when "Studie" is on), else a plain reading reminder to
/// `/read`. Days the schedule does not cover (never fetched, offline, stale
/// cache) get the same local fallback, with [fallbackVerse] when one is known
/// for exactly this date.
({DailyLine morning, DailyLine evening}) dailyLinesFor({
  required ScheduleDay? day,
  required DailyContentPrefs content,
  required LocalDailyFallback fallback,
  ScheduleVerse? fallbackVerse,
  required int rotation,
}) {
  final verse = content.verse ? (day?.verse ?? fallbackVerse) : null;

  // A verse in a day while the verse is off: that morning's body is the
  // verse, built before the toggle changed.
  final staleVerse = !content.verse && day?.verse != null;

  DailyLine? serverMorning;
  final m = day?.morning;
  if (m != null && content.allows(m.kind) && !staleVerse) {
    serverMorning = DailyLine(
      kind: m.kind,
      variant: RenderedVariant(variantId: 'srv-m', title: m.title, body: m.body),
      route: m.route,
    );
  }

  DailyLine? serverEvening;
  final e = day?.evening;
  if (e != null && content.allows(e.kind)) {
    serverEvening = DailyLine(
      kind: e.kind,
      variant: RenderedVariant(variantId: 'srv-e', title: e.title, body: e.body),
      route: e.route,
    );
  }

  // Local fallback: the study unless the server already said "study" and it
  // was switched off (then the next priority down is reading).
  final useStudy = content.study && fallback.hasStudy;
  DailyLine local({required bool evening}) {
    final rot = evening ? rotation + 3 : rotation;
    final v = _localVariant(useStudy, fallback, rot);
    final body = !evening && verse != null ? verseLine(verse) : v.body;
    return DailyLine(
      kind: useStudy ? ScheduleKind.study : ScheduleKind.chapter,
      variant: RenderedVariant(variantId: v.variantId, title: v.title, body: body),
      route: useStudy ? fallback.studyRoute! : '/read',
    );
  }

  return (
    morning: serverMorning ?? local(evening: false),
    evening: serverEvening ?? local(evening: true),
  );
}

RenderedVariant _localVariant(bool study, LocalDailyFallback fallback, int rotation) {
  if (!study) return pickReadingReminder(rotation: rotation);
  return pickVariant(NotifType.studyReminder, rotation: rotation, tokens: {
    'study': fallback.studyTitle,
    'lesson': fallback.lessonLabel,
  });
}

/// Moves a daily slot out of quiet hours without changing its date: into the
/// morning edge of the window when it sits before it, otherwise half an hour
/// before the window opens. (The generic `clampToWaking` can push a time to
/// the next morning, which would stack the evening on top of that morning.)
int clampDailyMinutes(int minutes, QuietHours quiet) {
  if (!quiet.contains(minutes)) return minutes;
  final start = quiet.startMinutes;
  final end = quiet.endMinutes;
  if (start < end) return end; // e.g. 13:00-15:00: after the window
  if (minutes < end) return end; // early morning, window wraps midnight
  return (start - 30).clamp(0, 24 * 60 - 1);
}

/// Days since 1970-01-01 of a local calendar date - the id slot of that date's
/// morning and evening (`% 14`), stable across recomputes, so today's evening
/// can be cancelled without knowing when it was scheduled.
int epochDayOf(DateTime localDate) =>
    DateTime.utc(localDate.year, localDate.month, localDate.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

int dailySlotFor(DateTime localDate) => epochDayOf(localDate) % 14;
