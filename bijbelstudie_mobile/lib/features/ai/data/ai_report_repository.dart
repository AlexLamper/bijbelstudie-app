import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

final aiReportRepositoryProvider = Provider((ref) {
  return AiReportRepository(ref.watch(apiClientProvider));
});

/// Why a reader flags an answer. Keys match `AI_REPORT_REASONS` in the
/// website's `lib/aiReport.ts`; values are the chip labels.
const aiReportReasons = <String, String>{
  'onjuist': 'Onjuist',
  'aanstootgevend': 'Aanstootgevend',
  'schadelijk': 'Schadelijk',
  'anders': 'Anders',
};

/// One report on one AI-assistant answer.
class AiReport {
  const AiReport({
    required this.reason,
    required this.answer,
    this.question = '',
    this.comment = '',
    this.surface = 'study_ai',
    this.model,
  });

  /// A key of [aiReportReasons].
  final String reason;

  /// The answer being reported, as shown.
  final String answer;

  /// The question that produced it, when there was one.
  final String question;

  /// The reader's optional explanation.
  final String comment;

  /// `study_ai` or `lesson_ai`: which screen showed the answer.
  final String surface;

  final String? model;

  static const maxComment = 1000;
  static const maxQuestion = 2000;
  static const maxAnswer = 4000;

  static String _cap(String value, int max) {
    final trimmed = value.trim();
    return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
  }

  Map<String, dynamic> toJson() => {
    'reason': reason,
    'answer': _cap(answer, maxAnswer),
    'question': _cap(question, maxQuestion),
    'comment': _cap(comment, maxComment),
    'surface': surface,
    if (model != null) 'model': model,
    'platform': Analytics.platform,
  };
}

/// Raised when a report could not be delivered. [message] is Dutch and safe to
/// show as-is.
class AiReportFailed implements Exception {
  const AiReportFailed(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sends AI-answer reports to `POST /api/v1/feedback/ai-report`, where they
/// land in the admin feedback read-out as `touchpoint: ai_report`.
class AiReportRepository {
  AiReportRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<void> submit(AiReport report) async {
    try {
      await _apiClient.dio.post('/feedback/ai-report', data: report.toJson());
    } on DioException catch (e) {
      throw reportError(e);
    }
  }

  /// Maps a failed call onto copy the report sheet can show inline.
  static AiReportFailed reportError(DioException e) {
    final response = e.response;
    if (response == null) {
      return const AiReportFailed(
        'Geen verbinding. Controleer je internet en probeer het opnieuw.',
      );
    }
    switch (response.statusCode) {
      case 401:
        return const AiReportFailed('Log opnieuw in om een melding te sturen.');
      case 429:
        return const AiReportFailed(
          'Je hebt vandaag al veel meldingen gestuurd. Probeer het morgen opnieuw.',
        );
    }
    return const AiReportFailed('Melden mislukt. Probeer het opnieuw.');
  }
}
