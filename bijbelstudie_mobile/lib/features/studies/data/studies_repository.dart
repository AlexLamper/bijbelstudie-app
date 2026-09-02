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

  /// The whole catalogue: one study per bible book plus the authored theme,
  /// person and passage studies - the same set the website browses.
  ///
  /// `/studies/catalog` also resolves the grouping metadata (`category`,
  /// `kind`, `avgMinutes`) server-side, so the screen never has to derive it.
  /// A server that predates that route still answers `/studies`, which carries
  /// the authored studies only; falling back keeps an older backend usable
  /// rather than showing an empty catalogue.
  Future<List<CuratedStudy>> getCuratedStudies() async {
    try {
      return await _fetch('/studies/catalog');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        try {
          return await _fetch('/studies');
        } on DioException catch (inner) {
          throw Exception('Fout bij ophalen studies: ${inner.message}');
        }
      }
      throw Exception('Fout bij ophalen studies: ${e.message}');
    }
  }

  Future<List<CuratedStudy>> _fetch(String path) async {
    final response = await _apiClient.dio.get(path);
    final data = response.data as Map<String, dynamic>;
    return (data['studies'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CuratedStudy.fromJson)
        .toList(growable: false);
  }
}
