// Wire shapes for "Bijbel in een jaar" (DAILY_HABIT_PLAN.md §4).
//
// Mirrors `lib/bibleYear/types.ts` in the website repo, which is the contract
// shared by the API, the web UI and this app. Every `fromJson` is tolerant: a
// missing or mistyped field falls back to an empty/zero value rather than
// throwing, so a server that adds or drops a field never blanks the screen.

/// `'jaar-1'` / `'jaar-2'`.
enum BibleYearPlanKey {
  jaar1('jaar-1'),
  jaar2('jaar-2');

  const BibleYearPlanKey(this.id);

  final String id;

  static BibleYearPlanKey? tryParse(Object? raw) {
    for (final key in values) {
      if (key.id == raw) return key;
    }
    return null;
  }
}

/// `'gemengd'` = OT / NT / Psalmen+Spreuken side by side; `'canoniek'` =
/// Genesis to Openbaring.
enum BibleYearTrackKey {
  gemengd('gemengd'),
  canoniek('canoniek');

  const BibleYearTrackKey(this.id);

  final String id;

  static BibleYearTrackKey? tryParse(Object? raw) {
    for (final key in values) {
      if (key.id == raw) return key;
    }
    return null;
  }
}

enum BibleYearStatus {
  active('active'),
  completed('completed'),
  abandoned('abandoned');

  const BibleYearStatus(this.id);

  final String id;

  static BibleYearStatus fromId(Object? raw) {
    for (final status in values) {
      if (status.id == raw) return status;
    }
    // An unknown status is never treated as a running plan.
    return BibleYearStatus.abandoned;
  }
}

String _str(Object? raw, [String fallback = '']) => raw is String ? raw : fallback;

int _int(Object? raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

double _num(Object? raw, [double fallback = 0]) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}

bool _bool(Object? raw) => raw == true;

List<Map<String, dynamic>> _maps(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => m.cast<String, dynamic>())
      .toList(growable: false);
}

Map<String, dynamic>? _map(Object? raw) => raw is Map ? raw.cast<String, dynamic>() : null;

/// One chapter reference with its read flag. `book` is the canonical Dutch
/// name as used in `readChapters`; `code` the stable machine code ("GEN").
class BibleYearRef {
  const BibleYearRef({
    required this.book,
    required this.code,
    required this.chapter,
    this.read = false,
  });

  final String book;
  final String code;
  final int chapter;

  /// Always false on a schedule day; the state on today's portions.
  final bool read;

  String get key => '$code:$chapter';

  static BibleYearRef? fromJson(Map<String, dynamic> json) {
    final chapter = _int(json['chapter']);
    final book = _str(json['book']);
    if (chapter < 1 || book.isEmpty) return null;
    return BibleYearRef(
      book: book,
      code: _str(json['code']),
      chapter: chapter,
      read: _bool(json['read']),
    );
  }

  BibleYearRef copyWith({bool? read}) =>
      BibleYearRef(book: book, code: code, chapter: chapter, read: read ?? this.read);

  Map<String, dynamic> toJson() => {
    'book': book,
    'code': code,
    'chapter': chapter,
    'read': read,
  };
}

/// `{ code, chapter }` - what `POST /bible-year/mark` takes.
class BibleYearChapterKey {
  const BibleYearChapterKey(this.code, this.chapter);

  final String code;
  final int chapter;

  Map<String, dynamic> toJson() => {'code': code, 'chapter': chapter};

  @override
  bool operator ==(Object other) =>
      other is BibleYearChapterKey && other.code == code && other.chapter == chapter;

  @override
  int get hashCode => Object.hash(code, chapter);
}

/// A portion of a day: the static schedule's shape, or today's with read
/// flags and `done`.
class BibleYearPortion {
  const BibleYearPortion({
    required this.strand,
    required this.label,
    required this.refs,
    this.done = false,
  });

  /// `'ot' | 'nt' | 'poetry' | 'all'`; kept as a string so a new strand still
  /// renders (without a heading).
  final String strand;
  final String label;
  final List<BibleYearRef> refs;
  final bool done;

  factory BibleYearPortion.fromJson(Map<String, dynamic> json) {
    final refs = _maps(json['refs'])
        .map(BibleYearRef.fromJson)
        .whereType<BibleYearRef>()
        .toList(growable: false);
    return BibleYearPortion(
      strand: _str(json['strand'], 'all'),
      label: _str(json['label']),
      refs: refs,
      done: json.containsKey('done')
          ? _bool(json['done'])
          : refs.isNotEmpty && refs.every((r) => r.read),
    );
  }

  BibleYearPortion copyWith({List<BibleYearRef>? refs, bool? done}) => BibleYearPortion(
    strand: strand,
    label: label,
    refs: refs ?? this.refs,
    done: done ?? this.done,
  );

  Map<String, dynamic> toJson() => {
    'strand': strand,
    'label': label,
    'refs': [for (final r in refs) r.toJson()],
    'done': done,
  };
}

/// A day in the static schedule. `day` is 1-based.
class BibleYearScheduleDay {
  const BibleYearScheduleDay({
    required this.day,
    required this.portions,
    required this.minutes,
  });

  final int day;
  final List<BibleYearPortion> portions;
  final int minutes;

  factory BibleYearScheduleDay.fromJson(Map<String, dynamic> json) => BibleYearScheduleDay(
    day: _int(json['day']),
    portions: _maps(json['portions']).map(BibleYearPortion.fromJson).toList(growable: false),
    minutes: _int(json['minutes']),
  );
}

class BibleYearSchedule {
  const BibleYearSchedule({
    required this.planKey,
    required this.track,
    required this.version,
    required this.totalDays,
    required this.days,
  });

  final BibleYearPlanKey? planKey;
  final BibleYearTrackKey? track;
  final int version;
  final int totalDays;
  final List<BibleYearScheduleDay> days;

  factory BibleYearSchedule.fromJson(Map<String, dynamic> json) {
    final days = _maps(json['days'])
        .map(BibleYearScheduleDay.fromJson)
        .where((d) => d.day > 0)
        .toList(growable: false);
    return BibleYearSchedule(
      planKey: BibleYearPlanKey.tryParse(json['planKey']),
      track: BibleYearTrackKey.tryParse(json['track']),
      version: _int(json['version'], 1),
      totalDays: _int(json['totalDays'], days.length),
      days: days,
    );
  }

  BibleYearScheduleDay? dayAt(int day) {
    // Days are sorted 1..n on the wire; a direct index is the fast path.
    if (day >= 1 && day <= days.length && days[day - 1].day == day) return days[day - 1];
    for (final d in days) {
      if (d.day == day) return d;
    }
    return null;
  }
}

class BibleYearCatalogueEntry {
  const BibleYearCatalogueEntry({
    required this.planKey,
    required this.label,
    required this.totalDays,
    required this.minutesPerDay,
  });

  final BibleYearPlanKey planKey;
  final String label;
  final int totalDays;
  final int minutesPerDay;

  static BibleYearCatalogueEntry? fromJson(Map<String, dynamic> json) {
    final key = BibleYearPlanKey.tryParse(json['planKey']);
    if (key == null) return null;
    return BibleYearCatalogueEntry(
      planKey: key,
      label: _str(json['label'], key == BibleYearPlanKey.jaar1 ? '1 jaar' : '2 jaar'),
      totalDays: _int(json['totalDays'], key == BibleYearPlanKey.jaar1 ? 365 : 730),
      minutesPerDay: _int(json['minutesPerDay'], key == BibleYearPlanKey.jaar1 ? 15 : 8),
    );
  }

  Map<String, dynamic> toJson() => {
    'planKey': planKey.id,
    'label': label,
    'totalDays': totalDays,
    'minutesPerDay': minutesPerDay,
  };
}

class BibleYearTrackEntry {
  const BibleYearTrackEntry({
    required this.track,
    required this.label,
    required this.description,
  });

  final BibleYearTrackKey track;
  final String label;
  final String description;

  static BibleYearTrackEntry? fromJson(Map<String, dynamic> json) {
    final key = BibleYearTrackKey.tryParse(json['track']);
    if (key == null) return null;
    return BibleYearTrackEntry(
      track: key,
      label: _str(json['label'], key.id),
      description: _str(json['description']),
    );
  }

  Map<String, dynamic> toJson() => {
    'track': track.id,
    'label': label,
    'description': description,
  };
}

class BibleYearEnrollment {
  const BibleYearEnrollment({
    required this.id,
    required this.planKey,
    required this.track,
    required this.scheduleVersion,
    required this.startDate,
    required this.timeZone,
    required this.shiftDays,
    required this.status,
    required this.totalDays,
    required this.chaptersRead,
    required this.percentBible,
    required this.expectedEndDate,
    this.completedAt,
  });

  final String id;
  final BibleYearPlanKey planKey;
  final BibleYearTrackKey track;
  final int scheduleVersion;

  /// 'YYYY-MM-DD' in the reader's time zone.
  final String startDate;
  final String timeZone;
  final int shiftDays;
  final BibleYearStatus status;
  final int totalDays;
  final int chaptersRead;

  /// 0-100.
  final double percentBible;
  final String expectedEndDate;
  final String? completedAt;

  bool get isActive => status == BibleYearStatus.active;
  bool get isCompleted => status == BibleYearStatus.completed;

  static BibleYearEnrollment? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final plan = BibleYearPlanKey.tryParse(json['planKey']);
    final track = BibleYearTrackKey.tryParse(json['track']);
    // A plan this build does not know cannot be rendered, and must not be
    // offered as "not started" either - the caller treats null as "none".
    if (plan == null || track == null) return null;
    return BibleYearEnrollment(
      id: _str(json['id']),
      planKey: plan,
      track: track,
      scheduleVersion: _int(json['scheduleVersion'], 1),
      startDate: _str(json['startDate']),
      timeZone: _str(json['timeZone'], 'Europe/Amsterdam'),
      shiftDays: _int(json['shiftDays']),
      status: BibleYearStatus.fromId(json['status']),
      totalDays: _int(json['totalDays'], plan == BibleYearPlanKey.jaar1 ? 365 : 730),
      chaptersRead: _int(json['chaptersRead']),
      percentBible: _num(json['percentBible']),
      expectedEndDate: _str(json['expectedEndDate']),
      completedAt: json['completedAt'] is String ? json['completedAt'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'planKey': planKey.id,
    'track': track.id,
    'scheduleVersion': scheduleVersion,
    'startDate': startDate,
    'timeZone': timeZone,
    'shiftDays': shiftDays,
    'status': status.id,
    'totalDays': totalDays,
    'chaptersRead': chaptersRead,
    'percentBible': percentBible,
    'expectedEndDate': expectedEndDate,
    'completedAt': completedAt,
  };
}

class BibleYearBacklogDay {
  const BibleYearBacklogDay({required this.day, required this.label});

  final int day;
  final String label;

  Map<String, dynamic> toJson() => {'day': day, 'label': label};
}

/// Everything a "Vandaag" card needs.
class BibleYearToday {
  const BibleYearToday({
    required this.dayNumber,
    required this.totalDays,
    required this.localDate,
    required this.portions,
    required this.todayDone,
    required this.behindDays,
    required this.aheadDays,
    required this.backlogDays,
    required this.percentBible,
    required this.expectedEndDate,
    required this.minutesEstimate,
    this.href = '/studies/bijbel-in-een-jaar',
  });

  /// 1..totalDays after shiftDays; 0 before the start date.
  final int dayNumber;
  final int totalDays;
  final String localDate;
  final List<BibleYearPortion> portions;
  final bool todayDone;
  final int behindDays;
  final int aheadDays;

  /// Oldest first, at most 7.
  final List<BibleYearBacklogDay> backlogDays;
  final double percentBible;
  final String expectedEndDate;
  final int minutesEstimate;

  /// The website path of the plan page; the app maps it to its own route.
  final String href;

  bool get notStarted => dayNumber <= 0;

  static BibleYearToday? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final portions = _maps(json['portions']).map(BibleYearPortion.fromJson).toList(growable: false);
    return BibleYearToday(
      dayNumber: _int(json['dayNumber']),
      totalDays: _int(json['totalDays']),
      localDate: _str(json['localDate']),
      portions: portions,
      todayDone: json.containsKey('todayDone')
          ? _bool(json['todayDone'])
          : portions.isNotEmpty && portions.every((p) => p.done),
      behindDays: _int(json['behindDays']).clamp(0, 1 << 20),
      aheadDays: _int(json['aheadDays']).clamp(0, 1 << 20),
      backlogDays: [
        for (final day in _maps(json['backlogDays']))
          if (_int(day['day']) > 0)
            BibleYearBacklogDay(day: _int(day['day']), label: _str(day['label'])),
      ],
      percentBible: _num(json['percentBible']),
      expectedEndDate: _str(json['expectedEndDate']),
      minutesEstimate: _int(json['minutesEstimate']),
      href: _str(json['href'], '/studies/bijbel-in-een-jaar'),
    );
  }

  BibleYearToday copyWith({List<BibleYearPortion>? portions, bool? todayDone}) => BibleYearToday(
    dayNumber: dayNumber,
    totalDays: totalDays,
    localDate: localDate,
    portions: portions ?? this.portions,
    todayDone: todayDone ?? this.todayDone,
    behindDays: behindDays,
    aheadDays: aheadDays,
    backlogDays: backlogDays,
    percentBible: percentBible,
    expectedEndDate: expectedEndDate,
    minutesEstimate: minutesEstimate,
    href: href,
  );

  Map<String, dynamic> toJson() => {
    'dayNumber': dayNumber,
    'totalDays': totalDays,
    'localDate': localDate,
    'portions': [for (final p in portions) p.toJson()],
    'todayDone': todayDone,
    'behindDays': behindDays,
    'aheadDays': aheadDays,
    'backlogDays': [for (final d in backlogDays) d.toJson()],
    'percentBible': percentBible,
    'expectedEndDate': expectedEndDate,
    'minutesEstimate': minutesEstimate,
    'href': href,
  };
}

/// `GET /api/v1/bible-year`, and - merged with the catalogue already held -
/// every mutation's answer.
class BibleYearState {
  const BibleYearState({
    this.catalogue = const [],
    this.tracks = const [],
    this.enrollment,
    this.today,
  });

  final List<BibleYearCatalogueEntry> catalogue;
  final List<BibleYearTrackEntry> tracks;
  final BibleYearEnrollment? enrollment;
  final BibleYearToday? today;

  /// A plan runs and there is a day to show.
  bool get isActive => enrollment?.isActive == true && today != null;

  factory BibleYearState.fromJson(Map<String, dynamic> json) => BibleYearState(
    catalogue: _maps(json['catalogue'])
        .map(BibleYearCatalogueEntry.fromJson)
        .whereType<BibleYearCatalogueEntry>()
        .toList(growable: false),
    tracks: _maps(json['tracks'])
        .map(BibleYearTrackEntry.fromJson)
        .whereType<BibleYearTrackEntry>()
        .toList(growable: false),
    enrollment: BibleYearEnrollment.fromJson(_map(json['enrollment'])),
    today: BibleYearToday.fromJson(_map(json['today'])),
  );

  /// A mutation's `{ enrollment, today }` replaces those two and keeps the
  /// catalogue and tracks this state already has.
  BibleYearState withMutation(Map<String, dynamic> json) => BibleYearState(
    catalogue: catalogue,
    tracks: tracks,
    enrollment: BibleYearEnrollment.fromJson(_map(json['enrollment'])),
    today: BibleYearToday.fromJson(_map(json['today'])),
  );

  BibleYearState copyWith({BibleYearToday? today}) => BibleYearState(
    catalogue: catalogue,
    tracks: tracks,
    enrollment: enrollment,
    today: today ?? this.today,
  );

  Map<String, dynamic> toJson() => {
    'catalogue': [for (final c in catalogue) c.toJson()],
    'tracks': [for (final t in tracks) t.toJson()],
    'enrollment': enrollment?.toJson(),
    'today': today?.toJson(),
  };
}

/// `POST /api/v1/bible-year` (and PATCH restart).
class BibleYearStartBody {
  const BibleYearStartBody({
    required this.planKey,
    required this.track,
    required this.startDate,
    this.timeZone,
  });

  final BibleYearPlanKey planKey;
  final BibleYearTrackKey track;

  /// 'YYYY-MM-DD', today or later in the reader's time zone.
  final String startDate;
  final String? timeZone;

  Map<String, dynamic> toJson() => {
    'planKey': planKey.id,
    'track': track.id,
    'startDate': startDate,
    if (timeZone != null && timeZone!.isNotEmpty) 'timeZone': timeZone,
  };
}
