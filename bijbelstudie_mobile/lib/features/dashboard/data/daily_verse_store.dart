import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_models.dart';

/// Local memory for the "Tekst van de dag" card.
///
/// The server has no endpoint for either half of this: `GET /daytext` hands
/// out today's verse and nothing else — no archive, no favourites. So the app
/// keeps both on the device, the same way [ReadingSettings] keeps the reader's
/// typography: every verse that arrives is appended to a capped history, and
/// the references the reader has hearted are stored as a flat set.
///
/// Both are best-effort. A device with no preferences plugin (tests, an
/// unusual platform) simply gets an empty history and no likes rather than an
/// error — the card must still render today's verse.

/// One day's verse as it was stored, plus the day it was shown.
class DailyVerseEntry {
  const DailyVerseEntry({
    required this.date,
    required this.text,
    required this.reference,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.version,
  });

  /// Local calendar day, `yyyy-mm-dd`. Also the de-duplication key: one entry
  /// per day, so a dashboard refresh does not stack the same verse twice.
  final String date;

  final String text;
  final String reference;
  final String book;
  final int chapter;
  final int verse;

  /// The translation abbreviation shown beside the reference on the day it was
  /// captured, e.g. `SV`. Empty when it could not be determined.
  final String version;

  Map<String, dynamic> toJson() => {
    'date': date,
    'text': text,
    'reference': reference,
    'book': book,
    'chapter': chapter,
    'verse': verse,
    'version': version,
  };

  static DailyVerseEntry? fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String?;
    final date = json['date'] as String?;
    if (text == null || date == null) return null;
    return DailyVerseEntry(
      date: date,
      text: text,
      reference: json['reference'] as String? ?? '',
      book: json['book'] as String? ?? '',
      chapter: (json['chapter'] as num?)?.toInt() ?? 1,
      verse: (json['verse'] as num?)?.toInt() ?? 1,
      version: json['version'] as String? ?? '',
    );
  }

  /// What the share sheet and the archive rows show.
  String get referenceWithVersion =>
      version.isEmpty ? reference : '$reference $version';
}

/// The stored state: newest day first, plus the set of liked references.
class DailyVerseMemory {
  const DailyVerseMemory({
    this.history = const [],
    this.liked = const {},
    this.loaded = false,
  });

  /// Newest first, at most [DailyVerseStore.maxDays] entries.
  final List<DailyVerseEntry> history;

  /// References (without the version suffix) the reader has hearted.
  final Set<String> liked;

  /// False until the first read from disk has finished, so the card can show a
  /// skeleton instead of a heart that flips a moment later.
  final bool loaded;

  bool isLiked(String reference) => liked.contains(reference);

  DailyVerseMemory copyWith({
    List<DailyVerseEntry>? history,
    Set<String>? liked,
    bool? loaded,
  }) {
    return DailyVerseMemory(
      history: history ?? this.history,
      liked: liked ?? this.liked,
      loaded: loaded ?? this.loaded,
    );
  }
}

const _kHistory = 'daytext.history';
const _kLiked = 'daytext.liked';

final dailyVerseStoreProvider =
    NotifierProvider<DailyVerseStore, DailyVerseMemory>(DailyVerseStore.new);

class DailyVerseStore extends Notifier<DailyVerseMemory> {
  /// Two months of archive. Long enough that "voorgaande dagen" is worth
  /// opening, short enough that the whole thing stays a few kilobytes of JSON.
  static const int maxDays = 60;

  /// The first read from disk. Every mutator awaits it before touching state.
  ///
  /// This used to be a fire-and-forget read with a `_written` flag that made it
  /// bail out if a write had got in first - and a write always did. The card
  /// calls [remember] from its first post-frame callback, which lands well
  /// before `SharedPreferences.getInstance()` resolves, so the read returned
  /// early on every single launch. State was then "today's verse and nothing
  /// else", and [_persistHistory] wrote exactly that back over the stored
  /// archive. Every previous day was destroyed on startup, which is why
  /// "Voorgaande dagen" was always empty no matter how long the app had been
  /// used.
  ///
  /// Waiting is the whole fix: the read is quick, the writes it gates are not
  /// user-visible, and a mutation can no longer be built on a blank history.
  late Future<void> _ready;

  @override
  DailyVerseMemory build() {
    _ready = _load();
    return const DailyVerseMemory();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The read outlives the provider when the app (or a test) tears down
      // mid-launch; writing state then throws rather than being ignored.
      if (!ref.mounted) return;
      state = DailyVerseMemory(
        history: _decode(prefs.getString(_kHistory)),
        liked: (prefs.getStringList(_kLiked) ?? const <String>[]).toSet(),
        loaded: true,
      );
    } catch (_) {
      // No preferences plugin: an empty archive, and likes that live only for
      // this session. Still "loaded" - nothing more is coming.
      if (!ref.mounted) return;
      state = state.copyWith(loaded: true);
    }
  }

  List<DailyVerseEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DailyVerseEntry.fromJson)
          .whereType<DailyVerseEntry>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Records [verse] as today's entry, if today is not already recorded.
  ///
  /// Called from the card whenever `/dashboard` hands over a daily verse, so
  /// the archive fills itself simply by opening the app on consecutive days.
  Future<void> remember(DailyVerse verse, {required String version}) async {
    await _ready;
    final today = dayKey(DateTime.now());
    final existing = state.history;
    if (existing.isNotEmpty &&
        existing.first.date == today &&
        existing.first.reference == verse.reference) {
      return;
    }

    final entry = DailyVerseEntry(
      date: today,
      text: verse.text,
      reference: verse.reference,
      book: verse.book,
      chapter: verse.chapter,
      verse: verse.verse,
      version: version,
    );

    // Newest first, and sorted by day rather than by arrival: an entry
    // recovered from an older install, or a day whose key sorts before one
    // already stored, still lands in the right place in the list.
    final next =
        <DailyVerseEntry>[entry, ...existing.where((e) => e.date != today)]
          ..sort((a, b) => b.date.compareTo(a.date));

    final capped = next.take(maxDays).toList(growable: false);
    state = state.copyWith(history: capped, loaded: true);
    await _persistHistory(capped);
  }

  /// Folds the server's archive into the device's.
  ///
  /// `GET /daytext/history` is the shared record of every day the feed was
  /// fetched, so this is what makes "Voorgaande dagen" show more than the days
  /// this particular install happened to be opened - a reinstall, a new phone
  /// or a fresh build no longer starts from nothing.
  ///
  /// The device copy wins on a clash: it was written from the verse the reader
  /// actually saw, including the translation label they were reading in.
  Future<void> mergeServer(List<DailyVerseEntry> entries) async {
    if (entries.isEmpty) return;
    await _ready;

    final byDate = <String, DailyVerseEntry>{
      for (final entry in entries) entry.date: entry,
      for (final entry in state.history) entry.date: entry,
    };

    final merged = byDate.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final capped = merged.take(maxDays).toList(growable: false);

    // Nothing new: leave state alone rather than handing every listener a new
    // list to rebuild on.
    final before = state.history.map((e) => e.date).join(',');
    if (before == capped.map((e) => e.date).join(',')) return;

    state = state.copyWith(history: capped, loaded: true);
    await _persistHistory(capped);
  }

  Future<void> toggleLike(String reference) async {
    if (reference.isEmpty) return;
    await _ready;
    final next = {...state.liked};
    if (!next.remove(reference)) next.add(reference);

    state = state.copyWith(liked: next, loaded: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kLiked, next.toList(growable: false));
    } catch (_) {
      // Best effort; the heart still reflects the tap for this session.
    }
  }

  Future<void> _persistHistory(List<DailyVerseEntry> history) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kHistory,
        jsonEncode(history.map((e) => e.toJson()).toList(growable: false)),
      );
    } catch (_) {
      // Best effort.
    }
  }
}

/// `yyyy-mm-dd` in local time — the archive's per-day key.
String dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// The short label for a translation id, as it is printed after a reference.
///
/// Hand-mapped for the translations the app ships; anything the server starts
/// serving falls back to its id in capitals, which is wrong-looking but never
/// blank.
String versionAbbreviation(String versionId) {
  return switch (versionId) {
    'statenvertaling' => 'SV',
    'nbg51' => 'NBG51',
    'canisiusbijbel' => 'CANIS',
    'heilige_schrift_1917' => 'HS1917',
    'kjv' => 'KJV',
    'asv' => 'ASV',
    'web' => 'WEB',
    'geneva' => 'GNV',
    'coverdale' => 'CVDL',
    _ => versionId.replaceAll('_', '').toUpperCase(),
  };
}
