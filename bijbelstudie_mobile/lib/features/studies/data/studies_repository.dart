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
}
