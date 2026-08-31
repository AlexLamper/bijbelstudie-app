// Shapes returned by `GET /api/v1/dashboard`, which mirrors what
// `app/dashboard/page.tsx` assembles on the website.

import '../../../core/data/bible_books.dart';

class LastRead {
  const LastRead({
    required this.book,
    required this.chapter,
    required this.version,
    this.commentary,
    this.updatedAt,
  });

  final String book;
  final int chapter;
  final String version;
  final String? commentary;

  /// When the server last moved this. The reader compares it with the copy on
  /// this device to decide which of the two is the more recent truth.
  final DateTime? updatedAt;

  String get reference => '$book $chapter';

  static LastRead? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['book'] == null) return null;
    return LastRead(
      book: json['book'] as String,
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      version: json['version'] as String? ?? 'statenvertaling',
      commentary: json['commentary'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
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
    // BijbelAPI.com (the "via BijbelAPI.com" feed behind `GET /daytext`)
    // returns English book names, e.g. "Zechariah" / "Zechariah 4:6"; the app
    // is Dutch-only, so both fields are normalised here, once, at the model
    // boundary — everything downstream (including the "Lees hoofdstuk →"
    // navigation) then only ever sees the Dutch name.
    final rawBook = json['book'] as String? ?? '';
    final book = BibleBooks.toDutch(rawBook);
    return DailyVerse(
      text: json['text'] as String,
      reference: _dutchReference(
        json['reference'] as String? ?? '',
        rawBook: rawBook,
        dutchBook: book,
      ),
      book: book,
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verse: (json['verse'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Swaps the English book name at the start of a "daytext" reference string
/// (e.g. "Zechariah 4:6") for its Dutch equivalent, leaving the
/// "chapter:verse" suffix untouched. Falls back to the raw string unchanged
/// when it does not start with [rawBook] — already Dutch, or an unrecognised
/// shape — rather than guessing.
String _dutchReference(
  String raw, {
  required String rawBook,
  required String dutchBook,
}) {
  if (raw.isEmpty) return dutchBook;
  if (rawBook.isNotEmpty && raw.startsWith(rawBook)) {
    return dutchBook + raw.substring(rawBook.length);
  }
  return raw;
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
    required this.badges,
    this.lastRead,
    this.dailyVerse,
  });

  final String name;
  final bool isPro;
  final int streak;

  /// Days the streak can survive without a completed task. Earned one per five
  /// days server-side; only a Pro account may spend one.
  final int freezes;

  /// Book name -> the chapter numbers already read.
  final Map<String, List<int>> readChapters;

  final List<WeekDay> weekDays;
  final int weekTotal;
  final int notesCount;
  final List<RecentNote> recentNotes;

  /// Earned badge ids, as `lib/gamification.ts` writes them. Rendered as seals;
  /// the XP and level the server derives them from stay off screen on purpose,
  /// so what the user sees is always what they actually read.
  final List<String> badges;

  final LastRead? lastRead;
  final DailyVerse? dailyVerse;

  /// How many of the 66 books have at least one chapter read.
  int get booksStarted => readChapters.values.where((c) => c.isNotEmpty).length;

  /// Folds `readChapters` keys onto their canonical Dutch spelling and merges
  /// the chapter lists behind keys that collapse together.
  ///
  /// The server does this now too, but an older build of the API — or a
  /// response served from cache — can still hand back keys spelled the way the
  /// translation that was read spells them ("1 Corinthiërs", "John",
  /// "Numberi"). Without this fold those chapters never match the 66-book grid
  /// and never count towards "… van 66 boeken geopend".
  static Map<String, List<int>> _canonicaliseProgress(Map<String, dynamic> raw) {
    final out = <String, List<int>>{};
    raw.forEach((book, chapters) {
      final key = BibleBooks.toCanonical(book);
      final nums = (chapters as List? ?? const [])
          .map((c) => (c as num).toInt())
          .where((n) => n >= 1);
      out.update(
        key,
        (existing) => {...existing, ...nums}.toList()..sort(),
        ifAbsent: () => nums.toSet().toList()..sort(),
      );
    });
    return out;
  }

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    final weekly = json['weeklyStats'] as Map<String, dynamic>? ?? const {};
    final rawProgress = json['readChapters'] as Map<String, dynamic>? ?? const {};

    return DashboardData(
      name: user['name'] as String? ?? '',
      isPro: user['isPro'] as bool? ?? false,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      freezes: (json['freezes'] as num?)?.toInt() ?? 0,
      readChapters: _canonicaliseProgress(rawProgress),
      weekDays: (weekly['days'] as List? ?? const [])
          .map((d) => WeekDay.fromJson(d as Map<String, dynamic>))
          .toList(growable: false),
      weekTotal: (weekly['totalThisWeek'] as num?)?.toInt() ?? 0,
      notesCount: (json['notesCount'] as num?)?.toInt() ?? 0,
      recentNotes: (json['recentNotes'] as List? ?? const [])
          .map((n) => RecentNote.fromJson(n as Map<String, dynamic>))
          .toList(growable: false),
      badges: (json['badges'] as List? ?? const [])
          .map((b) => b as String)
          .toList(growable: false),
      lastRead: LastRead.fromJson(json['lastRead'] as Map<String, dynamic>?),
      dailyVerse: DailyVerse.fromJson(json['dailyVerse'] as Map<String, dynamic>?),
    );
  }
}
