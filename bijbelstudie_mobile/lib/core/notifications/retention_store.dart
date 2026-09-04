import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart' show NotifType, NotifTypeX;

/// Local, best-effort mirror of the reader's habit, used only to decide whether
/// to *nudge* (`RETENTION_PLAN.md` §2). The server streak (`GET /dashboard`)
/// stays the number the app displays and celebrates; a wrong nudge is cheap, a
/// wrong streak is not.
///
/// Every day/week decision is a wall-clock date-key comparison, never an
/// elapsed-hours diff, so a timezone change or a clock rewind cannot inflate or
/// destroy anything: [markCompleted] is idempotent per day-key and never
/// decrements a counter.
class RetentionState {
  const RetentionState({
    this.loaded = false,
    this.lastCompletionDay,
    this.lastOpenDay,
    this.completionsByWeek = const {},
    this.localStreak = 0,
    this.serverStreakSeen = 0,
    this.graceUsedDay,
    this.tzName,
    this.sentLog = const {},
    this.milestonesReached = const {},
    this.permissionAskedAfterFirstLesson = false,
    this.firstLessonDone = false,
  });

  final bool loaded;

  /// `yyyy-MM-dd` of the last local day with a completion.
  final String? lastCompletionDay;
  final String? lastOpenDay;

  /// `{ "2026-W36": ["2026-09-01", "2026-09-03"] }`, capped to 8 weeks.
  final Map<String, List<String>> completionsByWeek;

  final int localStreak;
  final int serverStreakSeen;
  final String? graceUsedDay;
  final String? tzName;

  /// `{ "2026-09-04": ["studyReminder"] }`, capped to 14 days - the frequency
  /// cap ledger.
  final Map<String, List<String>> sentLog;

  /// Celebration dedupe: `streak-7`, `study-<id>-done`, `badge-<id>`,
  /// `book-Genesis`.
  final Set<String> milestonesReached;

  final bool permissionAskedAfterFirstLesson;
  final bool firstLessonDone;

  RetentionState copyWith({
    bool? loaded,
    String? lastCompletionDay,
    String? lastOpenDay,
    Map<String, List<String>>? completionsByWeek,
    int? localStreak,
    int? serverStreakSeen,
    String? graceUsedDay,
    bool clearGrace = false,
    String? tzName,
    Map<String, List<String>>? sentLog,
    Set<String>? milestonesReached,
    bool? permissionAskedAfterFirstLesson,
    bool? firstLessonDone,
  }) {
    return RetentionState(
      loaded: loaded ?? this.loaded,
      lastCompletionDay: lastCompletionDay ?? this.lastCompletionDay,
      lastOpenDay: lastOpenDay ?? this.lastOpenDay,
      completionsByWeek: completionsByWeek ?? this.completionsByWeek,
      localStreak: localStreak ?? this.localStreak,
      serverStreakSeen: serverStreakSeen ?? this.serverStreakSeen,
      graceUsedDay: clearGrace ? null : (graceUsedDay ?? this.graceUsedDay),
      tzName: tzName ?? this.tzName,
      sentLog: sentLog ?? this.sentLog,
      milestonesReached: milestonesReached ?? this.milestonesReached,
      permissionAskedAfterFirstLesson:
          permissionAskedAfterFirstLesson ?? this.permissionAskedAfterFirstLesson,
      firstLessonDone: firstLessonDone ?? this.firstLessonDone,
    );
  }
}

/// `yyyy-MM-dd` for a local wall-clock date. Lexicographic order == chronological
/// order, which is what the clock-rewind guard in [markCompleted] leans on.
String retentionDayKey([DateTime? now]) {
  final d = now ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// `"<isoYear>-W<isoWeek>"`, Monday-start ISO-8601 week.
String retentionWeekKey([DateTime? now]) {
  final d = now ?? DateTime.now();
  final date = DateTime(d.year, d.month, d.day);
  // The Thursday of this week determines the ISO year and week number.
  final thursday = date.add(Duration(days: 4 - (date.weekday == 7 ? 7 : date.weekday)));
  final firstThursdayOfYear = () {
    final jan1 = DateTime(thursday.year, 1, 1);
    final wd = jan1.weekday; // Mon=1..Sun=7
    final offset = (4 - wd) % 7;
    return jan1.add(Duration(days: offset < 0 ? offset + 7 : offset));
  }();
  final week = 1 + (thursday.difference(firstThursdayOfYear).inDays ~/ 7);
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

/// Number of whole days between two `yyyy-MM-dd` keys (`b - a`). Negative when
/// [b] is before [a] (a clock rewind).
int retentionDayGap(String a, String b) {
  final da = DateTime.parse(a);
  final db = DateTime.parse(b);
  return db.difference(da).inDays;
}

const _kPrefix = 'retention.';

final retentionStoreProvider =
    NotifierProvider<RetentionStore, RetentionState>(RetentionStore.new);

class RetentionStore extends Notifier<RetentionState> {
  final Completer<void> _loaded = Completer<void>();

  Future<void> get loaded => _loaded.future;

  @override
  RetentionState build() {
    _load();
    return const RetentionState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = RetentionState(
        loaded: true,
        lastCompletionDay: prefs.getString('${_kPrefix}lastCompletionDayKey'),
        lastOpenDay: prefs.getString('${_kPrefix}lastOpenDayKey'),
        completionsByWeek: _decodeMap(prefs.getString('${_kPrefix}completionsByWeek')),
        localStreak: prefs.getInt('${_kPrefix}localStreak') ?? 0,
        serverStreakSeen: prefs.getInt('${_kPrefix}serverStreakSeen') ?? 0,
        graceUsedDay: prefs.getString('${_kPrefix}graceUsedDayKey'),
        tzName: prefs.getString('${_kPrefix}tzName'),
        sentLog: _decodeMap(prefs.getString('${_kPrefix}sentLog')),
        milestonesReached:
            (jsonDecodeList(prefs.getString('${_kPrefix}milestonesReached'))).toSet(),
        permissionAskedAfterFirstLesson:
            prefs.getBool('${_kPrefix}permissionAskedAfterFirstLesson') ?? false,
        firstLessonDone: prefs.getBool('${_kPrefix}firstLessonDone') ?? false,
      );
    } catch (_) {
      state = const RetentionState(loaded: true);
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  static Map<String, List<String>> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          e.key: (e.value as List).whereType<String>().toList(),
      };
    } catch (_) {
      return const {};
    }
  }

  static List<String> jsonDecodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(RetentionState next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '${_kPrefix}lastCompletionDayKey', next.lastCompletionDay ?? '');
      await prefs.setString('${_kPrefix}lastOpenDayKey', next.lastOpenDay ?? '');
      await prefs.setString(
          '${_kPrefix}completionsByWeek', jsonEncode(next.completionsByWeek));
      await prefs.setInt('${_kPrefix}localStreak', next.localStreak);
      await prefs.setInt('${_kPrefix}serverStreakSeen', next.serverStreakSeen);
      await prefs.setString('${_kPrefix}graceUsedDayKey', next.graceUsedDay ?? '');
      await prefs.setString('${_kPrefix}tzName', next.tzName ?? '');
      await prefs.setString('${_kPrefix}sentLog', jsonEncode(next.sentLog));
      await prefs.setString('${_kPrefix}milestonesReached',
          jsonEncode(next.milestonesReached.toList()));
      await prefs.setBool('${_kPrefix}permissionAskedAfterFirstLesson',
          next.permissionAskedAfterFirstLesson);
      await prefs.setBool('${_kPrefix}firstLessonDone', next.firstLessonDone);
    } catch (_) {
      // In-memory state still stands for this session.
    }
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  bool get studiedToday => state.lastCompletionDay == retentionDayKey();

  bool studiedOn(String dayKey) => state.lastCompletionDay == dayKey;

  int get completionsThisWeek =>
      state.completionsByWeek[retentionWeekKey()]?.length ?? 0;

  int completionsInWeek(String weekKey) =>
      state.completionsByWeek[weekKey]?.length ?? 0;

  bool get openedToday => state.lastOpenDay == retentionDayKey();

  /// Whether a capped-type notification has already gone out today (§4.4).
  bool get cappedSentToday {
    final today = state.sentLog[retentionDayKey()] ?? const [];
    return today.any((tag) {
      final type = NotifType.values
          .where((t) => t.id == tag)
          .cast<NotifType?>()
          .firstWhere((_) => true, orElse: () => null);
      return type != null && type.isCapped;
    });
  }

  bool sentTypeToday(NotifType type) =>
      (state.sentLog[retentionDayKey()] ?? const []).contains(type.id);

  bool hasMilestone(String id) => state.milestonesReached.contains(id);

  // ── Writes ─────────────────────────────────────────────────────────────

  /// A finished lesson or a recorded chapter read. Idempotent per day-key;
  /// never decrements; never rewrites [RetentionState.lastCompletionDay]
  /// backwards on a clock rewind (§2).
  Future<void> markCompleted({DateTime? now}) async {
    await loaded;
    final d = retentionDayKey(now);
    final last = state.lastCompletionDay;
    if (d == last) return; // Already counted today.

    final week = retentionWeekKey(now);
    final byWeek = {
      for (final e in state.completionsByWeek.entries) e.key: [...e.value],
    };
    final bucket = byWeek.putIfAbsent(week, () => <String>[]);
    if (!bucket.contains(d)) bucket.add(d);

    // Trim to the 8 most recent weeks.
    if (byWeek.length > 8) {
      final keys = byWeek.keys.toList()..sort();
      for (final k in keys.take(byWeek.length - 8)) {
        byWeek.remove(k);
      }
    }

    final rewind = last != null && retentionDayGap(last, d) < 0;
    var streak = state.localStreak;
    if (!rewind) {
      if (last != null && retentionDayGap(last, d) == 1) {
        streak += 1;
      } else if (last == null || retentionDayGap(last, d) > 1) {
        streak = 1;
      }
    }

    await _persist(state.copyWith(
      // On a rewind keep the (later) stored day; only the week bucket grows.
      lastCompletionDay: rewind ? last : d,
      completionsByWeek: byWeek,
      localStreak: rewind ? state.localStreak : streak,
    ));
  }

  Future<void> markOpened({DateTime? now}) async {
    await loaded;
    final d = retentionDayKey(now);
    if (state.lastOpenDay == d) return;
    await _persist(state.copyWith(lastOpenDay: d));
  }

  /// The server streak is authoritative. When it changes, adopt it and remember
  /// what we last saw so a later local guess of "broke" can be corrected.
  Future<void> reconcileServerStreak(int serverStreak) async {
    await loaded;
    if (serverStreak == state.serverStreakSeen) return;
    await _persist(state.copyWith(
      localStreak: serverStreak,
      serverStreakSeen: serverStreak,
    ));
  }

  Future<void> recordNotificationSent(NotifType type, {DateTime? now}) async {
    await loaded;
    final d = retentionDayKey(now);
    final log = {for (final e in state.sentLog.entries) e.key: [...e.value]};
    final bucket = log.putIfAbsent(d, () => <String>[]);
    if (!bucket.contains(type.id)) bucket.add(type.id);
    if (log.length > 14) {
      final keys = log.keys.toList()..sort();
      for (final k in keys.take(log.length - 14)) {
        log.remove(k);
      }
    }
    await _persist(state.copyWith(sentLog: log));
  }

  Future<void> markMilestone(String id) async {
    await loaded;
    if (state.milestonesReached.contains(id)) return;
    await _persist(state.copyWith(
      milestonesReached: {...state.milestonesReached, id},
    ));
  }

  Future<void> markPermissionAsked() async {
    await loaded;
    await _persist(state.copyWith(permissionAskedAfterFirstLesson: true));
  }

  Future<void> markFirstLessonDone() async {
    await loaded;
    if (state.firstLessonDone) return;
    await _persist(state.copyWith(firstLessonDone: true));
  }

  Future<void> noteTimezone(String name) async {
    await loaded;
    if (state.tzName == name) return;
    await _persist(state.copyWith(tzName: name));
  }
}
