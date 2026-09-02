import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';
import 'enrollment_models.dart';

final enrollmentRepositoryProvider = Provider((ref) {
  return EnrollmentRepository(ref.watch(apiClientProvider));
});

/// A study enrollment could not be read or written.
///
/// Separated from the generic failure so callers can tell "you are not signed
/// in" (which needs a login prompt) from "the network is down" (which needs a
/// retry), rather than showing one apologetic message for both.
class EnrollmentException implements Exception {
  const EnrollmentException(this.message, {this.isUnauthorized = false});

  final String message;
  final bool isUnauthorized;

  @override
  String toString() => message;
}

class EnrollmentRepository {
  EnrollmentRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Every study this account has started, most recently touched first - the
  /// server already sorts by `lastActivityAt`.
  Future<List<StudyEnrollment>> list() async {
    if (PreviewConfig.enabled) return const [];
    try {
      final response = await _apiClient.dio.get('/study-enrollments');
      final data = response.data as Map<String, dynamic>;
      return (data['enrollments'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StudyEnrollment.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _translate(e, 'Je studies konden niet worden geladen.');
    }
  }

  /// One enrollment, or null when this account never started the study.
  Future<StudyEnrollment?> find(String studyId) async {
    if (PreviewConfig.enabled) return null;
    try {
      final response = await _apiClient.dio.get('/study-enrollments/$studyId');
      final data = response.data as Map<String, dynamic>;
      final enrollment = data['enrollment'];
      if (enrollment is! Map<String, dynamic>) return null;
      return StudyEnrollment.fromJson(enrollment);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _translate(e, 'Deze studie kon niet worden geladen.');
    }
  }

  /// Start the study, or re-save its settings if it was already started.
  ///
  /// The endpoint is idempotent: re-enrolling returns the existing record
  /// rather than resetting progress, which is what lets the settings sheet use
  /// the same call for "Opslaan" and "Opslaan en starten".
  Future<StudyEnrollment> enrol(String studyId, EnrollmentSettings settings) async {
    try {
      final response = await _apiClient.dio.post(
        '/study-enrollments',
        data: settings.toJson(studyId),
      );
      final data = response.data as Map<String, dynamic>;
      return StudyEnrollment.fromJson(data['enrollment'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _translate(e, 'De studie kon niet worden gestart.');
    }
  }

  /// Change the settings of a study already under way.
  Future<StudyEnrollment> updateSettings(
    String studyId,
    EnrollmentSettings settings,
  ) async {
    try {
      final body = settings.toJson(studyId)..remove('studyId');
      final response = await _apiClient.dio.patch(
        '/study-enrollments/$studyId',
        data: body,
      );
      final data = response.data as Map<String, dynamic>;
      return StudyEnrollment.fromJson(data['enrollment'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _translate(e, 'De instellingen konden niet worden opgeslagen.');
    }
  }

  /// Stop a study. The server marks it abandoned and silences its reminders -
  /// completed lessons and reflections are kept, so restarting resumes.
  Future<void> abandon(String studyId) async {
    try {
      await _apiClient.dio.delete('/study-enrollments/$studyId');
    } on DioException catch (e) {
      throw _translate(e, 'De studie kon niet worden gestopt.');
    }
  }

  EnrollmentException _translate(DioException e, String fallback) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return const EnrollmentException(
        'Meld je aan om een studie te volgen.',
        isUnauthorized: true,
      );
    }
    if (status == 404) {
      return const EnrollmentException('Deze studie bestaat niet meer.');
    }
    return EnrollmentException(fallback);
  }
}
