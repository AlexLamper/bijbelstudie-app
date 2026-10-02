import '../data/bible_year_models.dart';

/// How a plan day looks on the week strip and the month calendar.
enum PlanDayState {
  /// Every part done (chapters, and in 'studeren' the uitleg and the vraag).
  done,

  /// In the past and not done: "staat open". Shown neutral, never as a warning.
  open,
  today,
  future,

  /// A calendar date outside the plan (before day 1 or after the last day).
  outside,
}

/// One part of a plan day, in reading order: every chapter, then in
/// 'studeren' the uitleg and the vraag. The reader's plan bar has one segment
/// per part; Vandaag one row per part.
class PlanPart {
  const PlanPart.chapter(this.ref, {required this.strand, required this.done})
    : kind = PlanPartKind.chapter,
      question = null;

  const PlanPart.uitleg(this.ref, {required this.done})
    : kind = PlanPartKind.uitleg,
      strand = null,
      question = null;

  const PlanPart.vraag(this.ref, {required String this.question, required this.done})
    : kind = PlanPartKind.vraag,
      strand = null;

  final PlanPartKind kind;

  /// The chapter; for uitleg and vraag the chapter they are about.
  final BibleYearRef ref;

  /// 'ot' | 'nt' | 'poetry' | 'all', chapters only.
  final String? strand;
  final String? question;
  final bool done;

  bool get isChapter => kind == PlanPartKind.chapter;

  /// Reading minutes: the chapter's own, 6 for an uitleg, 2 for a vraag.
  int get minutes => switch (kind) {
    PlanPartKind.chapter => ref.minutes > 0 ? ref.minutes : 4,
    PlanPartKind.uitleg => 6,
    PlanPartKind.vraag => 2,
  };
}

enum PlanPartKind { chapter, uitleg, vraag }

/// "Oude Testament", "Nieuwe Testament", "Psalmen en Spreuken"; null for the
/// single strand of the other orders.
String? strandLabel(String? strand) => switch (strand) {
  'ot' => 'Oude Testament',
  'nt' => 'Nieuwe Testament',
  'poetry' => 'Psalmen en Spreuken',
  _ => null,
};

/// "Genesis 46" (Psalmen read as "Psalm 23").
String chapterLabel(BibleYearRef ref) =>
    '${ref.code == 'PS' ? 'Psalm' : ref.book} ${ref.chapter}';

/// Calendar maths of a running plan, mirroring `lib/bibleYear/progress.ts`:
/// day N falls on startDate + N - 1 + shiftDays. Pure; build one per frame.
class PlanCalendar {
  PlanCalendar({
    required this.enrollment,
    required this.schedule,
    required this.todayDay,
    Set<String>? readRefs,
  }) : readRefs = readRefs ?? enrollment.readRefs;

  final BibleYearEnrollment enrollment;
  final BibleYearSchedule schedule;

  /// Every chapter read, as `readRefs` keys ("GEN.1"). Built by
  /// `planReadRefKeys` from the server's answer, the dashboard's read map and
  /// this device's own ticks - the enrollment DTO does not carry the list, so
  /// `enrollment.readRefs` alone is empty. The one source every surface asks.
  final Set<String> readRefs;

  /// The server's `today.dayNumber`: 0 before the start, else 1..totalDays.
  final int todayDay;

  /// Chapters in the whole Bible, the denominator of [percentBible].
  static const bibleChapters = 1189;

  int get totalDays => schedule.totalDays;

  /// Chapters read: whichever is larger of the server's own `chaptersRead`
  /// and the size of [readRefs].
  ///
  /// The server counts the plan's `readRefs`, a list it does not send, so it
  /// may know of ticks this app cannot enumerate; [readRefs] knows of
  /// chapters read before the plan began, which its count leaves out. Taking
  /// the larger keeps the server's number and still never shows fewer
  /// chapters than the green days already prove.
  int get chaptersRead {
    final derived = readRefs.length;
    final reported = enrollment.chaptersRead;
    return (derived > reported ? derived : reported).clamp(0, bibleChapters);
  }

  /// 0-100, unrounded - the surfaces that show it round it themselves.
  double get percentBible => chaptersRead * 100 / bibleChapters;

  DateTime get _start {
    final parsed = DateTime.tryParse(enrollment.startDate);
    final d = parsed ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  /// The calendar date of plan day [day].
  DateTime dateOf(int day) {
    final s = _start;
    return DateTime(s.year, s.month, s.day + day - 1 + enrollment.shiftDays);
  }

  /// The plan day on [date], or null outside the plan.
  int? dayOn(DateTime date) {
    final s = _start;
    final utcDate = DateTime.utc(date.year, date.month, date.day);
    final utcStart = DateTime.utc(s.year, s.month, s.day);
    final day = utcDate.difference(utcStart).inDays + 1 - enrollment.shiftDays;
    return day >= 1 && day <= totalDays ? day : null;
  }

  BibleYearScheduleDay? scheduleDay(int day) => schedule.dayAt(day);

  bool isRead(BibleYearRef ref) => readRefs.contains(ref.refKey);

  bool studyPartDone(int day, BibleYearStudyPart part) =>
      enrollment.studyDone.contains(bibleYearStudyKey(day, part));

  bool get studeren => enrollment.mode == BibleYearMode.studeren;

  /// The parts of [day] in reading order, with their done state.
  List<PlanPart> partsOf(int day) {
    final sd = scheduleDay(day);
    if (sd == null) return const [];
    final parts = <PlanPart>[
      for (final p in sd.portions)
        for (final r in p.refs) PlanPart.chapter(r, strand: p.strand, done: isRead(r)),
    ];
    final study = sd.study;
    if (studeren && study != null) {
      parts
        ..add(PlanPart.uitleg(study.ref, done: studyPartDone(day, BibleYearStudyPart.uitleg)))
        ..add(
          PlanPart.vraag(
            study.ref,
            question: study.question,
            done: studyPartDone(day, BibleYearStudyPart.vraag),
          ),
        );
    }
    return parts;
  }

  bool isDone(int day) {
    final parts = partsOf(day);
    return parts.isNotEmpty && parts.every((p) => p.done);
  }

  PlanDayState stateOf(int day) {
    if (day < 1 || day > totalDays) return PlanDayState.outside;
    if (day == todayDay) return isDone(day) ? PlanDayState.done : PlanDayState.today;
    if (isDone(day)) return PlanDayState.done;
    return day < todayDay ? PlanDayState.open : PlanDayState.future;
  }

  /// Open days before today, oldest first.
  List<int> openDays() => [
    for (var d = 1; d < todayDay && d <= totalDays; d++)
      if (!isDone(d)) d,
  ];

  /// Index of the first part of [day] not done, or null when the day is done.
  int? firstOpenPart(int day) {
    final parts = partsOf(day);
    final i = parts.indexWhere((p) => !p.done);
    return i < 0 ? null : i;
  }

  /// Minutes still to read on [day].
  int minutesLeft(int day) =>
      partsOf(day).where((p) => !p.done).fold(0, (sum, p) => sum + p.minutes);

  /// Minutes of the whole of [day].
  int minutesOf(int day) => partsOf(day).fold(0, (sum, p) => sum + p.minutes);
}

const _weekdays = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];
const _months = [
  'januari', 'februari', 'maart', 'april', 'mei', 'juni',
  'juli', 'augustus', 'september', 'oktober', 'november', 'december',
];

/// "woensdag 30 september".
String planDateLong(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "September 2026".
String planMonthTitle(DateTime d) {
  final m = _months[d.month - 1];
  return '${m[0].toUpperCase()}${m.substring(1)} ${d.year}';
}

/// "ma" .. "zo".
const planWeekdayShort = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

/// "Dinsdag 29 september".
String planDateTitle(DateTime d) {
  final s = planDateLong(d);
  return '${s[0].toUpperCase()}${s.substring(1)}';
}
