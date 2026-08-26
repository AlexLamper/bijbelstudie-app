import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/features/ai/data/ai_repository.dart';

/// Guards the AI assistant's failure states against the two ways they go wrong
/// without anything visibly breaking.
///
/// **A fault sold as a paywall.** `/api/v1/ai/chat` answers 429 for two very
/// different things: `QUOTA_EXCEEDED` when the reader has spent their daily
/// allowance, and `AI_BUSY` when Gemini itself has no capacity. Reading the
/// second as the first told users they had used questions they still had,
/// offered Pro as the cure for an outage Pro does not cure, and logged a
/// `paywall_hit` for a gate that never closed.
///
/// **A raw error code shown as copy.** `errorV1(code, status)` defaults the
/// body's `message` to the code itself, so an unauthenticated call returns
/// `{"error":"UNAUTHORIZED","message":"UNAUTHORIZED"}`. Rendering that put an
/// English constant in front of a Dutch-only audience.
///
/// Both are pure mapping decisions, so they are tested through
/// [AiRepository.aiError] without a socket.
void main() {
  DioException fail(int status, Map<String, dynamic> body) {
    final request = RequestOptions(path: '/ai/chat');
    return DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  DioException noResponse(DioExceptionType type) => DioException(
    requestOptions: RequestOptions(path: '/ai/chat'),
    type: type,
  );

  group('quota versus fault', () {
    test('QUOTA_EXCEEDED is the only 429 that is a paywall', () {
      final error = AiRepository.aiError(
        fail(429, {
          'error': 'QUOTA_EXCEEDED',
          'message': 'Je hebt je 5 gratis vragen voor vandaag gebruikt.',
        }),
      );

      expect(error, isA<AiQuotaExceeded>());
      expect(
        (error as AiQuotaExceeded).message,
        'Je hebt je 5 gratis vragen voor vandaag gebruikt.',
      );
    });

    test('AI_BUSY is a fault, not a cap', () {
      final error = AiRepository.aiError(
        fail(429, {
          'error': 'AI_BUSY',
          'message':
              'Het is momenteel erg druk. Probeer het over een minuutje opnieuw.',
        }),
      );

      expect(error, isA<AiUnavailable>());
      expect(error, isNot(isA<AiQuotaExceeded>()));
    });
  });

  group('every state is explained in Dutch', () {
    test('401 asks for a new sign-in and never echoes the code', () {
      final error = AiRepository.aiError(
        fail(401, {'error': 'UNAUTHORIZED', 'message': 'UNAUTHORIZED'}),
      );

      expect(error, isA<AiAuthRequired>());
      expect((error as AiAuthRequired).message, isNot(contains('UNAUTHORIZED')));
      expect(error.message, contains('Log opnieuw in'));
    });

    test('503 without a model key states that it is unavailable', () {
      final error = AiRepository.aiError(
        fail(503, {
          'error': 'AI_NOT_CONFIGURED',
          'message': 'AI-assistent niet geconfigureerd',
        }),
      );

      expect(error, isA<AiUnavailable>());
      expect((error as AiUnavailable).message, 'AI-assistent niet geconfigureerd');
    });

    test('451 tells the reader to switch translation, not about licensing', () {
      final error = AiRepository.aiError(
        fail(451, {
          'error': 'CONTENT_NOT_LICENSED_FOR_MOBILE',
          'message':
              'Deze bron is niet gelicentieerd voor de mobiele app. '
              'This content source is not licensed for distribution in the mobile app.',
        }),
      );

      expect(error, isA<AiUnavailable>());
      final message = (error as AiUnavailable).message;
      expect(message, contains('andere vertaling'));
      expect(message, isNot(contains('licensed')));
    });

    test('a timeout says so rather than blaming the connection', () {
      final error = AiRepository.aiError(
        noResponse(DioExceptionType.receiveTimeout),
      );

      expect(error, isA<AiUnavailable>());
      expect((error as AiUnavailable).message, contains('duurde te lang'));
    });

    test('a dead connection is reported as one', () {
      final error = AiRepository.aiError(
        noResponse(DioExceptionType.connectionError),
      );

      expect((error as AiUnavailable).message, contains('verbinding'));
    });

    test('an unparseable body still yields Dutch copy', () {
      final request = RequestOptions(path: '/ai/chat');
      final error = AiRepository.aiError(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 500,
            data: '<!DOCTYPE html>',
          ),
        ),
      );

      expect(error, isA<AiUnavailable>());
      expect(
        (error as AiUnavailable).message,
        'De AI-assistent is even niet bereikbaar.',
      );
    });
  });
}
