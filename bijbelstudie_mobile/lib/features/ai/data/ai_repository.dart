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

/// Raised when the assistant itself cannot answer: no model key on the server,
/// Gemini out of capacity, a blocked translation, or a request that never came
/// back. Deliberately not [AiQuotaExceeded]: selling Pro as the answer to a
/// fault sells nothing and reads as opportunism.
class AiUnavailable implements Exception {
  const AiUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raised on a 401 the refresh interceptor could not repair. The session is
/// gone, so the only thing the user can do is sign in again - and they have to
/// be told that rather than shown a raw error code.
class AiAuthRequired implements Exception {
  const AiAuthRequired([
    this.message = 'Log opnieuw in om de AI-assistent te gebruiken.',
  ]);
  final String message;

  @override
  String toString() => message;
}

class AiRepository {
  AiRepository(this._apiClient);

  final ApiClient _apiClient;

  /// How long one answer may take.
  ///
  /// The client's global receive timeout is 15s, which is right for scripture
  /// JSON and far too short for a model answer: `generateChatReply` walks a
  /// six-model fallback chain and the route budgets 60s for it (`maxDuration`).
  /// Every question was therefore aborted on this side before the server had
  /// any chance to answer it, which is what made the assistant look dead. 65s
  /// sits just outside the server's own ceiling, so the server's error - which
  /// can be explained - always wins the race against a bare timeout.
  static const _answerTimeout = Duration(seconds: 65);

  Future<AiQuota> getQuota() async {
    try {
      final response = await _apiClient.dio.get('/ai/chat');
      return AiQuota.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw aiError(e);
    }
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
        options: Options(
          receiveTimeout: _answerTimeout,
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      final data = response.data as Map<String, dynamic>;
      final reply = data['reply'] as String? ?? '';
      // A 200 with nothing in it is still a failure, and showing an empty
      // bubble would claim the assistant answered when it did not.
      if (reply.trim().isEmpty) {
        throw const AiUnavailable(
          'De assistent gaf geen antwoord. Probeer het opnieuw.',
        );
      }
      return reply;
    } on DioException catch (e) {
      throw aiError(e);
    }
  }

  /// Maps a failed call onto the one state the pane can honestly explain.
  ///
  /// Static and separate from the request so every branch is testable without
  /// a socket. The distinction that matters is *cap versus fault*: the server
  /// answers both with 429 - `QUOTA_EXCEEDED` for the daily allowance and
  /// `AI_BUSY` when Gemini itself has no capacity - and reading the second as
  /// the first told users they had spent questions they still had, sold them
  /// Pro to fix an outage Pro does not fix, and logged a `paywall_hit` for a
  /// gate that never closed.
  static Object aiError(DioException e) {
    final response = e.response;
    if (response == null) {
      final timedOut =
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout;
      return AiUnavailable(
        timedOut
            ? 'Het antwoord duurde te lang. Probeer het opnieuw.'
            : 'De AI-assistent is even niet bereikbaar. Controleer je verbinding.',
      );
    }

    final data = response.data;
    final body = data is Map ? data : const {};
    final code = body['error'] as String?;
    final raw = body['message'] as String?;
    // `errorV1` defaults `message` to the error code, so a route that passes no
    // copy yields `message: "UNAUTHORIZED"`. That is not Dutch and means
    // nothing to a reader, so it is dropped in favour of our own wording.
    final message = (raw != null && raw.isNotEmpty && raw != code) ? raw : null;

    switch (response.statusCode) {
      case 401:
        return const AiAuthRequired();
      case 429:
        if (code == 'QUOTA_EXCEEDED') {
          return AiQuotaExceeded(
            message ?? 'Je hebt je gratis vragen voor vandaag gebruikt.',
          );
        }
        return AiUnavailable(
          message ??
              'Het is momenteel erg druk. Probeer het over een minuutje opnieuw.',
        );
      case 451:
        // The server's own 451 copy is half English and explains licensing,
        // which is not the reader's problem. Give them the action instead.
        return const AiUnavailable(
          'Deze vertaling kan niet met de AI-assistent worden gebruikt. '
          'Kies een andere vertaling.',
        );
    }

    return AiUnavailable(message ?? 'De AI-assistent is even niet bereikbaar.');
  }
}
