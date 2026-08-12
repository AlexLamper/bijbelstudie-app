import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import 'study_models.dart';

final studiesRepositoryProvider = Provider((ref) {
  return StudiesRepository(ref.watch(apiClientProvider));
});

class StudiesRepository {
  StudiesRepository(this._apiClient);

  final ApiClient _apiClient;

  /// The guided studies from `/studies` on the website. Static content, so the
  /// server sends an ETag and Dio's 304 costs one empty round trip.
  Future<List<CuratedStudy>> getCuratedStudies() async {
    try {
      final response = await _apiClient.dio.get('/studies');
      final data = response.data as Map<String, dynamic>;
      return (data['studies'] as List? ?? const [])
          .map((s) => CuratedStudy.fromJson(s as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw Exception('Fout bij ophalen studies: ${e.message}');
    }
  }

  /// `type` is `public`, `my`, or null for both.
  Future<List<BiblePlan>> getPlans({String? type}) async {
    try {
      final response = await _apiClient.dio.get(
        '/plans',
        queryParameters: {if (type != null) 'type': type},
      );
      final data = response.data as Map<String, dynamic>;
      return (data['plans'] as List? ?? const [])
          .map((p) => BiblePlan.fromJson(p as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw Exception('Fout bij ophalen leesplannen: ${e.message}');
    }
  }

  /// Enrols in a plan. Returns an error message when the server refuses —
  /// free accounts may hold one plan, and that refusal is worth showing.
  Future<String?> enroll(String planId) async {
    try {
      await _apiClient.dio.post('/plans/enrollment', data: {'planId': planId});
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      return 'Inschrijven mislukt. Probeer het opnieuw.';
    }
  }

  Future<void> unenroll(String planId) async {
    await _apiClient.dio.delete(
      '/plans/enrollment',
      queryParameters: {'planId': planId},
    );
  }

  Future<void> setDayCompleted(String planId, int day, bool completed) async {
    if (completed) {
      await _apiClient.dio.post(
        '/plans/progress',
        data: {'planId': planId, 'day': day},
      );
    } else {
      await _apiClient.dio.delete(
        '/plans/progress',
        queryParameters: {'planId': planId, 'day': day},
      );
    }
  }
}
