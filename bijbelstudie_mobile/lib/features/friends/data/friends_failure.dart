import 'dart:io';

import 'package:dio/dio.dart';

/// Why a vriendenkring call did not answer.
///
/// The point of naming these is that "je hebt nog geen vrienden" and "de
/// server is er even niet" are different sentences, and a reader who is told
/// the first when the second is true will go looking for a bug in their own
/// account. A real empty result is not in this enum at all: it is
/// `FriendsFeed.empty` / `FriendsKring.empty` with no failure beside it.
enum FriendsFailure {
  /// No usable connection, or the request timed out. Retrying is the fix.
  offline,

  /// The server answered 5xx. Retrying later is the fix, not retrying now.
  server,

  /// 401 / 403 after the refresh interceptor already gave up: the session is
  /// gone and only logging in again helps.
  unauthorized,

  /// The thing asked for is not there any more - a post somebody deleted, a
  /// friend who unfriended first. Not an error to retry.
  notFound,

  /// The route exists but the feature is switched off server-side (a 503 from
  /// `/friends/discovery/*` when `FRIENDS_CONTACT_PEPPER` is unset). Callers
  /// degrade quietly on this one: nothing is wrong, there is simply nothing to
  /// offer, so no error card and no retry button.
  unavailable,

  /// Anything else, including a body in a shape this build cannot read.
  unknown,
}

/// A failed vriendenkring call, with the Dutch line a screen can print.
///
/// Thrown rather than returned so the Riverpod providers can keep their plain
/// `AsyncNotifier<FriendsFeed>` shape and let `AsyncValue.error` carry it.
class FriendsException implements Exception {
  const FriendsException(this.kind, {this.serverMessage});

  final FriendsFailure kind;

  /// The server's own Dutch `message`, when it sent one. Preferred over the
  /// generic line, because it is more specific than anything guessed here.
  final String? serverMessage;

  /// Short, for a card title.
  String get title => switch (kind) {
    FriendsFailure.offline => 'Geen verbinding',
    FriendsFailure.server => 'Even niet beschikbaar',
    FriendsFailure.unauthorized => 'Je bent niet meer ingelogd',
    FriendsFailure.notFound => 'Niet meer te vinden',
    FriendsFailure.unavailable => 'Nu niet beschikbaar',
    FriendsFailure.unknown => 'Dat lukte niet',
  };

  /// One sentence under the title. Says what is wrong and what helps.
  String get message =>
      serverMessage ??
      switch (kind) {
        FriendsFailure.offline =>
          'We konden je vriendenkring niet ophalen. Controleer je internet en '
              'probeer het opnieuw.',
        FriendsFailure.server =>
          'De server antwoordt nu niet. Je kring is er nog, probeer het straks '
              'nog eens.',
        FriendsFailure.unauthorized =>
          'Log opnieuw in om je vriendenkring te zien.',
        FriendsFailure.notFound => 'Dit is er niet meer.',
        FriendsFailure.unavailable => 'Dit onderdeel staat nu uit.',
        FriendsFailure.unknown =>
          'We konden je vriendenkring niet ophalen. Probeer het opnieuw.',
      };

  /// Whether offering a "Opnieuw proberen" button makes sense.
  bool get retryable =>
      kind == FriendsFailure.offline ||
      kind == FriendsFailure.server ||
      kind == FriendsFailure.unknown;

  @override
  String toString() => 'FriendsException(${kind.name}: $message)';
}

/// Reads a `{ "message": "..." }` body, which every `/friends/*` route sends
/// on an error (`errorV1`).
String? friendsServerMessage(Object? data) {
  if (data is Map && data['message'] is String) {
    final message = (data['message'] as String).trim();
    if (message.isNotEmpty) return message;
  }
  return null;
}

/// Maps whatever Dio threw onto [FriendsFailure].
///
/// A 404 is deliberately *not* special-cased here: whether "niets gevonden"
/// means an empty kring or a missing post depends on the route, so each
/// repository method decides that before calling this.
FriendsException friendsFailureFrom(Object error) {
  if (error is FriendsException) return error;
  if (error is! DioException) {
    if (error is SocketException) return const FriendsException(FriendsFailure.offline);
    return const FriendsException(FriendsFailure.unknown);
  }

  final status = error.response?.statusCode;
  final serverMessage = friendsServerMessage(error.response?.data);

  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout ||
    DioExceptionType.connectionError => const FriendsException(FriendsFailure.offline),
    DioExceptionType.badCertificate => const FriendsException(FriendsFailure.server),
    DioExceptionType.badResponse => _fromStatus(status, serverMessage),
    DioExceptionType.cancel => const FriendsException(FriendsFailure.unknown),
    DioExceptionType.unknown => error.error is SocketException
        ? const FriendsException(FriendsFailure.offline)
        : _fromStatus(status, serverMessage),
  };
}

FriendsException _fromStatus(int? status, String? serverMessage) {
  if (status == null) return FriendsException(FriendsFailure.unknown, serverMessage: serverMessage);
  if (status == 401 || status == 403) {
    return FriendsException(FriendsFailure.unauthorized, serverMessage: serverMessage);
  }
  if (status == 404 || status == 410) {
    return FriendsException(FriendsFailure.notFound, serverMessage: serverMessage);
  }
  if (status == 503 || status == 501) {
    return FriendsException(FriendsFailure.unavailable, serverMessage: serverMessage);
  }
  if (status >= 500) {
    return FriendsException(FriendsFailure.server, serverMessage: serverMessage);
  }
  return FriendsException(FriendsFailure.unknown, serverMessage: serverMessage);
}

/// True for the statuses a route answers when the feature is simply not there
/// for this reader: an empty kring, or contact matching without a pepper.
bool friendsStatusIsAbsent(int? status) => status == 404 || status == 503;
