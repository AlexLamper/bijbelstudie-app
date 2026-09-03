import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import 'daily_verse_store.dart';
import 'dashboard_models.dart';

final dashboardRepositoryProvider = Provider((ref) {
  return DashboardRepository(ref.watch(apiClientProvider));
});

class DashboardRepository {
  DashboardRepository(this._apiClient);

  final ApiClient _apiClient;

  /// One request for the whole tab. The website makes six; on a phone that is
  /// six round trips before anything renders.
  Future<DashboardData> getDashboard() async {
    try {
      final response = await _apiClient.dio.get('/dashboard');
      return DashboardData.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception('Fout bij ophalen dashboard: ${e.message}');
    }
  }

  /// Records the open chapter and, server-side, marks it read and logs a
  /// reading session. Failures are swallowed: losing a progress ping must
  /// never block the reader.
  Future<void> recordRead({
    required String book,
    required int chapter,
    required String version,
    String? commentary,
  }) async {
    try {
      await _apiClient.dio.post(
        '/last-read',
        data: {
          'book': book,
          'chapter': chapter,
          'version': version,
          if (commentary != null) 'commentary': commentary,
        },
      );
    } catch (_) {
      // best effort
    }
  }

  /// The server's copy of where the reader was, across every device.
  ///
  /// The same document `recordRead` writes. Returns null when it cannot be had
  /// - offline, signed out, or nothing recorded yet - which the caller treats
  /// as "the server has nothing to say", never as "start at Genesis 1".
  Future<LastRead?> getLastRead() async {
    try {
      final response = await _apiClient.dio.get('/last-read');
      final data = response.data as Map<String, dynamic>?;
      return LastRead.fromJson(data?['lastReadChapter'] as Map<String, dynamic>?);
    } catch (_) {
      return null;
    }
  }

  /// Advances the daily streak, once per calendar day.
  ///
  /// The server owns every rule here: it bumps at most once a day, spends a
  /// freeze to bridge a missed day when the account is Pro, hands out a freeze
  /// every fifth day, and re-evaluates the badges. Returns null when the call
  /// did not go through, which the caller treats as "no celebration", never as
  /// "streak lost".
  Future<StreakResult?> bumpStreak() async {
    try {
      final response = await _apiClient.dio.post('/streak');
      return StreakResult.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// The shared verse-of-the-day archive, newest day first.
  ///
  /// `GET /daytext` only ever serves today, so the archive behind "Voorgaande
  /// dagen" is kept server-side: every day the feed is fetched is filed there
  /// once, for everyone. Without it the device copy starts empty on a new
  /// install and fills one day at a time.
  ///
  /// Returns an empty list on any failure - the archive is a nicety, and the
  /// device's own copy still stands.
  Future<List<DailyVerseEntry>> getDayTextHistory({int limit = 60}) async {
    try {
      final response = await _apiClient.dio.get(
        '/daytext/history',
        queryParameters: {'limit': limit},
      );
      final body = response.data;
      final entries = body is Map<String, dynamic> ? body['entries'] : body;
      if (entries is! List) return const [];
      return entries
          .whereType<Map<String, dynamic>>()
          .map(_entryFromJson)
          .whereType<DailyVerseEntry>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// One archive row. Routed through [DailyVerse.fromJson] so the English book
  /// names the feed uses are normalised exactly once, the same way today's
  /// verse is.
  static DailyVerseEntry? _entryFromJson(Map<String, dynamic> json) {
    final date = json['date'] as String?;
    final verse = DailyVerse.fromJson(json);
    if (date == null || date.isEmpty || verse == null) return null;
    final version = verse.version;
    return DailyVerseEntry(
      date: date,
      text: verse.text,
      reference: verse.reference,
      book: verse.book,
      chapter: verse.chapter,
      verse: verse.verse,
      // The server names the translation in full ("Statenvertaling"); the
      // archive prints the abbreviation after the reference.
      version: version == null || version.isEmpty
          ? ''
          : versionAbbreviation(version.toLowerCase()),
    );
  }

  Future<DailyVerse?> getDailyVerse() async {
    try {
      final response = await _apiClient.dio.get('/daytext');
      return DailyVerse.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// What `POST /streak` answers with.
class StreakResult {
  const StreakResult({
    required this.streak,
    required this.freezes,
    required this.newBadges,
  });

  final int streak;
  final int freezes;

  /// Badge ids that were not on the account before this call.
  final List<String> newBadges;

  factory StreakResult.fromJson(Map<String, dynamic> json) {
    final xp = json['xp'] as Map<String, dynamic>?;
    return StreakResult(
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      freezes: (json['freezes'] as num?)?.toInt() ?? 0,
      newBadges: (xp?['newBadges'] as List? ?? const [])
          .map((b) => b as String)
          .toList(growable: false),
    );
  }
}
