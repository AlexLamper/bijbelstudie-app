// Shapes returned by `GET /api/v1/dashboard`, which mirrors what
// `app/dashboard/page.tsx` assembles on the website.

class LastRead {
  const LastRead({
    required this.book,
    required this.chapter,
    required this.version,
    this.commentary,
  });

  final String book;
  final int chapter;
  final String version;
  final String? commentary;

  String get reference => '$book $chapter';

  static LastRead? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['book'] == null) return null;
    return LastRead(
      book: json['book'] as String,
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      version: json['version'] as String? ?? 'statenvertaling',
      commentary: json['commentary'] as String?,
    );
  }
}

class WeekDay {
  const WeekDay({
    required this.label,
    required this.count,
    required this.heightPct,
    required this.isToday,
  });

  final String label;
  final int count;
  final int heightPct;
  final bool isToday;

  factory WeekDay.fromJson(Map<String, dynamic> json) {
    return WeekDay(
      label: json['label'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      heightPct: (json['heightPct'] as num?)?.toInt() ?? 0,
      isToday: json['isToday'] as bool? ?? false,
    );
  }
}

class DailyVerse {
  const DailyVerse({
    required this.text,
    required this.reference,
    required this.book,
    required this.chapter,
    required this.verse,
  });

  final String text;
  final String reference;
  final String book;
  final int chapter;
  final int verse;

  static DailyVerse? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['text'] == null) return null;
    return DailyVerse(
      text: json['text'] as String,
      reference: json['reference'] as String? ?? '',
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verse: (json['verse'] as num?)?.toInt() ?? 1,
    );
  }
}

class RecentNote {
  const RecentNote({
    required this.id,
    required this.book,
    required this.chapter,
    required this.text,
    this.verse,
  });

  final String id;
  final String book;
  final int chapter;
  final String text;
  final int? verse;

  String get reference =>
      verse == null ? '$book $chapter' : '$book $chapter:$verse';

  factory RecentNote.fromJson(Map<String, dynamic> json) {
    return RecentNote(
      id: json['id'] as String? ?? '',
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verse: (json['verse'] as num?)?.toInt(),
      text: json['noteText'] as String? ?? '',
    );
  }
}

class ActivePlanSummary {
  const ActivePlanSummary({
    required this.id,
    required this.title,
    required this.duration,
    required this.completedDays,
    required this.progressPercentage,
  });

  final String id;
  final String title;
  final int duration;
  final int completedDays;
  final int progressPercentage;

  static ActivePlanSummary? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['id'] == null) return null;
    return ActivePlanSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      completedDays: (json['completedDays'] as num?)?.toInt() ?? 0,
      progressPercentage: (json['progressPercentage'] as num?)?.toInt() ?? 0,
    );
  }
}

class DashboardData {
  const DashboardData({
    required this.name,
    required this.isPro,
    required this.streak,
    required this.freezes,
    required this.readChapters,
    required this.weekDays,
    required this.weekTotal,
    required this.notesCount,
    required this.recentNotes,
    this.lastRead,
    this.dailyVerse,
    this.activePlan,
  });

  final String name;
  final bool isPro;
  final int streak;
  final int freezes;

  /// Book name -> the chapter numbers already read.
  final Map<String, List<int>> readChapters;

  final List<WeekDay> weekDays;
  final int weekTotal;
  final int notesCount;
  final List<RecentNote> recentNotes;
  final LastRead? lastRead;
  final DailyVerse? dailyVerse;
  final ActivePlanSummary? activePlan;

  /// How many of the 66 books have at least one chapter read.
  int get booksStarted => readChapters.values.where((c) => c.isNotEmpty).length;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    final weekly = json['weeklyStats'] as Map<String, dynamic>? ?? const {};
    final rawProgress = json['readChapters'] as Map<String, dynamic>? ?? const {};

    return DashboardData(
      name: user['name'] as String? ?? '',
      isPro: user['isPro'] as bool? ?? false,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      freezes: (json['freezes'] as num?)?.toInt() ?? 0,
      readChapters: rawProgress.map(
        (book, chapters) => MapEntry(
          book,
          (chapters as List? ?? const [])
              .map((c) => (c as num).toInt())
              .toList(growable: false),
        ),
      ),
      weekDays: (weekly['days'] as List? ?? const [])
          .map((d) => WeekDay.fromJson(d as Map<String, dynamic>))
          .toList(growable: false),
      weekTotal: (weekly['totalThisWeek'] as num?)?.toInt() ?? 0,
      notesCount: (json['notesCount'] as num?)?.toInt() ?? 0,
      recentNotes: (json['recentNotes'] as List? ?? const [])
          .map((n) => RecentNote.fromJson(n as Map<String, dynamic>))
          .toList(growable: false),
      lastRead: LastRead.fromJson(json['lastRead'] as Map<String, dynamic>?),
      dailyVerse: DailyVerse.fromJson(json['dailyVerse'] as Map<String, dynamic>?),
      activePlan: ActivePlanSummary.fromJson(json['activePlan'] as Map<String, dynamic>?),
    );
  }
}
