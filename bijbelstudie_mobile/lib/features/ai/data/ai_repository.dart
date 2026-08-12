import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';

final aiRepositoryProvider = Provider((ref) {
  return AiRepository(ref.watch(apiClientProvider));
});

class AiTurn {
  const AiTurn({required this.role, required this.content});

  /// `user` or `assistant`.
  final String role;
  final String content;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AiQuota {
  const AiQuota({
    required this.configured,
    required this.used,
    required this.cap,
    required this.unlimited,
  });

  final bool configured;
  final int used;
  final int cap;
  final bool unlimited;

  int get remaining => (cap - used).clamp(0, cap);

  factory AiQuota.fromJson(Map<String, dynamic> json) {
    return AiQuota(
      configured: json['configured'] as bool? ?? false,
      used: (json['used'] as num?)?.toInt() ?? 0,
      cap: (json['cap'] as num?)?.toInt() ?? 0,
      unlimited: json['unlimited'] as bool? ?? false,
    );
  }
}

/// Raised when the daily question budget is spent, so the composer can show
/// the upgrade prompt instead of a generic failure.
class AiQuotaExceeded implements Exception {
  const AiQuotaExceeded(this.message);
  final String message;

  @override
  String toString() => message;
}

class AiRepository {
  AiRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AiQuota> getQuota() async {
    final response = await _apiClient.dio.get('/ai/chat');
    return AiQuota.fromJson(response.data as Map<String, dynamic>);
  }

  /// Sends one turn with the open chapter as context. The server holds no
  /// conversation state, so the recent history travels with each request —
  /// the same contract the website's widget uses.
  Future<String> ask({
    required String message,
    required List<AiTurn> history,
    String? book,
    int? chapter,
    String? version,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/ai/chat',
        data: {
          'message': message,
          'history': history.map((t) => t.toJson()).toList(),
          if (book != null) 'book': book,
          if (chapter != null) 'chapter': chapter,
          if (version != null) 'version': version,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return data['reply'] as String? ?? '';
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 429 && data is Map) {
        throw AiQuotaExceeded(
          data['message'] as String? ??
              'Je hebt je gratis vragen voor vandaag gebruikt.',
        );
      }
      if (data is Map && data['message'] is String) {
        throw Exception(data['message'] as String);
      }
      throw Exception('De AI-assistent is even niet bereikbaar.');
    }
  }
}
