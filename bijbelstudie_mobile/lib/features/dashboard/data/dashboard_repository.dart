import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
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
