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

  /// Advances the daily streak. Returns the new value, or null when the call
  /// did not go through.
  Future<int?> bumpStreak() async {
    try {
      final response = await _apiClient.dio.post('/streak');
      return ((response.data as Map<String, dynamic>)['streak'] as num?)?.toInt();
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
