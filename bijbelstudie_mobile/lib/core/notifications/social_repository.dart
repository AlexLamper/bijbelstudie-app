import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/present/auth_controller.dart' show apiClientProvider;
import '../config/preview_config.dart';
import 'notification_service.dart' show NotifType, isAllowedNotificationRoute;

/// What a vriendenkring notification is about.
///
/// Mirrors the social kinds the backend adds to `lib/notificationCopy.ts`.
/// [other] is any kind a newer server sends that this build does not know: it
/// still updates the badge and is still shown with the server's own words, on
/// the social channel, deep-linking to the kring.
enum SocialEventKind { friendRequest, friendAccepted, postLike, postComment, other }

SocialEventKind socialEventKindFrom(Object? raw) {
  final s = raw is String ? raw.trim() : '';
  return switch (s) {
    'friendRequest' || 'friend_request' || 'friendRequestReceived' =>
      SocialEventKind.friendRequest,
    'friendAccepted' || 'friend_accepted' || 'friendRequestAccepted' =>
      SocialEventKind.friendAccepted,
    'postLike' || 'post_like' || 'like' => SocialEventKind.postLike,
    'postComment' || 'post_comment' || 'comment' => SocialEventKind.postComment,
    _ => SocialEventKind.other,
  };
}

/// The [NotifType] a kind is shown as. [SocialEventKind.other] rides
/// [NotifType.friendRequest]'s ids and channel rather than needing one of its
/// own; it is the kind we do not understand, not a kind we invent.
NotifType notifTypeForSocial(SocialEventKind kind) => switch (kind) {
  SocialEventKind.friendRequest => NotifType.friendRequest,
  SocialEventKind.friendAccepted => NotifType.friendAccepted,
  SocialEventKind.postLike => NotifType.postLike,
  SocialEventKind.postComment => NotifType.postComment,
  SocialEventKind.other => NotifType.friendRequest,
};

/// The Dutch words to show when the server sends an event without any, and the
/// route to open when it sends no deep link.
///
/// Normally both come from the server (`lib/notificationCopy.ts`), so that one
/// place owns the tone for the website, the push and this local fallback. These
/// are only the floor: a kind with no copy is still worth a notification.
({String title, String body}) socialFallbackCopy(
  SocialEventKind kind, {
  String? actorName,
}) {
  final who = (actorName == null || actorName.trim().isEmpty)
      ? 'Iemand'
      : actorName.trim();
  return switch (kind) {
    SocialEventKind.friendRequest => (
      title: 'Nieuw verzoek',
      body: '$who wil je toevoegen aan je vriendenkring.',
    ),
    SocialEventKind.friendAccepted => (
      title: 'Je verzoek is geaccepteerd',
      body: '$who zit nu in je vriendenkring.',
    ),
    SocialEventKind.postLike => (
      title: 'Een hartje',
      body: '$who vond je bericht mooi.',
    ),
    SocialEventKind.postComment => (
      title: 'Een reactie',
      body: '$who reageerde op je bericht.',
    ),
    SocialEventKind.other => (
      title: 'Vriendenkring',
      body: 'Er is iets nieuws in je vriendenkring.',
    ),
  };
}

/// Where a kind's notification deep-links when the server sends no route.
///
/// A friend request goes to the Verzoeken tab, a like or a reaction to that
/// post's thread, an accepted request to that person's profile. The feed is the
/// floor: `/vriendenkring` exists, the two query forms are ignored by a screen
/// that does not read them yet, and anything off the whitelist in
/// `notification_service.dart` would land on the dashboard instead.
String socialFallbackRoute(
  SocialEventKind kind, {
  String? actorId,
  String? postId,
}) {
  String? candidate = switch (kind) {
    SocialEventKind.friendRequest => '/vriendenkring?tab=verzoeken',
    SocialEventKind.friendAccepted =>
      (actorId == null || actorId.isEmpty) ? null : '/vriendenkring/$actorId',
    SocialEventKind.postLike || SocialEventKind.postComment =>
      (postId == null || postId.isEmpty) ? null : '/vriendenkring?post=$postId',
    SocialEventKind.other => null,
  };
  if (candidate == null || !isAllowedNotificationRoute(candidate)) {
    candidate = '/vriendenkring';
  }
  return candidate;
}

/// One thing that happened in the reader's vriendenkring while they were away.
class SocialEvent {
  const SocialEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
    this.createdAt,
    this.rawCreatedAt,
  });

  /// The server's own id for this event (`request:<id>`, `like:<post>:<actor>`,
  /// ...), and the same string the APNs payload carries as `eventId`. The whole
  /// dedupe hangs off it, so an event without one is dropped rather than guessed
  /// at ([tryParse]).
  final String id;

  final SocialEventKind kind;
  final String title;
  final String body;

  /// Already checked against the notification route whitelist.
  final String route;

  final DateTime? createdAt;

  /// The `createdAt` exactly as the server wrote it. Part of the ledger key:
  /// `lib/push/social.ts` keeps a friend request's id stable across a re-open
  /// (a declined verzoek sent again is the same document) and moves its
  /// timestamp instead, so "the same event again" is id *and* timestamp.
  final String? rawCreatedAt;

  NotifType get type => notifTypeForSocial(kind);

  /// The ledger key for "this exact event". [SocialNotificationStore] also holds
  /// bare ids, written by the push callback, and either one is a match - see
  /// `socialLedgerKeys`.
  String get ledgerKey => rawCreatedAt == null ? id : '$id@$rawCreatedAt';

  /// Null when the payload has no usable id. Everything else degrades: missing
  /// copy falls back to [socialFallbackCopy], a missing or unsafe route to
  /// [socialFallbackRoute].
  static SocialEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;

    String? str(Object? v) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    final id = str(raw['id']) ?? str(raw['_id']) ?? str(raw['eventId']);
    if (id == null) return null;

    final kind = socialEventKindFrom(raw['type'] ?? raw['kind']);
    final actor = raw['actor'] ?? raw['from'] ?? raw['user'];
    final actorMap = actor is Map ? actor : const {};
    final actorName = str(raw['actorName']) ?? str(actorMap['name']);
    final actorId = str(raw['actorId']) ??
        str(actorMap['userId']) ??
        str(actorMap['id']) ??
        str(actorMap['_id']);
    final postId = str(raw['postId']) ?? str((raw['post'] is Map ? raw['post'] : const {})['id']);

    final fallback = socialFallbackCopy(kind, actorName: actorName);
    final sent = str(raw['route']) ?? str(raw['deepLink']) ?? str(raw['url']);
    final route = sent != null && isAllowedNotificationRoute(sent)
        ? sent
        : socialFallbackRoute(kind, actorId: actorId, postId: postId);

    final rawCreatedAt =
        str(raw['createdAt']) ?? str(raw['at']) ?? str(raw['timestamp']);
    return SocialEvent(
      id: id,
      kind: kind,
      title: str(raw['title']) ?? fallback.title,
      body: str(raw['body']) ?? str(raw['message']) ?? fallback.body,
      route: route,
      createdAt: DateTime.tryParse(rawCreatedAt ?? '')?.toLocal(),
      rawCreatedAt: rawCreatedAt,
    );
  }
}

/// One page of `GET /api/v1/notifications/social`, as
/// `SocialNotificationsResponse` in the website's `lib/push/social.ts`.
class SocialEventPage {
  const SocialEventPage({
    required this.events,
    this.cursor,
    this.hasMore = false,
    this.pendingRequests = 0,
    this.pushEnabled = false,
  });

  /// Oldest first, as the server sends them.
  final List<SocialEvent> events;

  /// An ISO timestamp, sent back as `?since=` next time. Null means "keep the
  /// cursor you have": a server that sends none must not reset us to the
  /// beginning of time.
  final String? cursor;

  /// The page was cut short; call again at once with [cursor].
  final bool hasMore;

  /// Pending incoming verzoeken, cursor or no cursor: a badge count.
  final int pendingRequests;

  /// Whether this deployment can push at all. False means APNs is not
  /// configured there, so even an iPhone has to fall back to the local path -
  /// which is why it gates the raise alongside the device token.
  final bool pushEnabled;

  static SocialEventPage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['items'] ?? raw['events'] ?? raw['notifications'] ?? raw['data'];
    if (list is! List) return null;
    final events = [
      for (final item in list)
        if (SocialEvent.tryParse(item) case final e?) e,
    ];
    final cursor = raw['cursor'] ?? raw['nextCursor'];
    final pending = raw['pendingRequests'];
    return SocialEventPage(
      events: events,
      cursor: cursor is String && cursor.isNotEmpty ? cursor : null,
      hasMore: raw['hasMore'] == true || raw['has_more'] == true,
      pendingRequests: pending is num && pending >= 0 ? pending.toInt() : 0,
      pushEnabled: raw['pushEnabled'] == true,
    );
  }
}

/// `/api/v1/notifications/*` for the vriendenkring: the device-token register
/// and the pull. The only Dio in this feature - the sync controller and the
/// registrar go through here.
class SocialNotificationsRepository {
  SocialNotificationsRepository(this._dio);

  /// Null in a unit test that only exercises the parsing.
  final Dio? _dio;

  static const _timeout = Duration(seconds: 10);

  /// An APNs device token as the backend's `TOKEN_PATTERN` wants it: lowercase
  /// hex, at least 64 characters. Checked here so a malformed token is not sent
  /// at all rather than coming back as a 400 on every foreground.
  static final _tokenPattern = RegExp(r'^[0-9a-f]{64,200}$');

  /// Which APNs host this build's tokens are valid on. A token minted by a
  /// build signed with a development profile only works against the sandbox
  /// host; sending it to production comes back as `BadDeviceToken`, which the
  /// sender reads as a dead device and deletes. The two values are the ones
  /// `ApnsEnvironment` in `lib/push/devices.ts` accepts - `development` is the
  /// entitlement's word for it, not the API's.
  static String get apnsEnvironment => kReleaseMode ? 'production' : 'sandbox';

  /// `POST /notifications/devices`. True when the backend took the token.
  ///
  /// False also covers the 503 this answers when the deployment has no APNs
  /// key (`PUSH_NOT_CONFIGURED`): there is no push there, so the app keeps to
  /// the local path. Nothing is cached from that - turning APNs on server-side
  /// needs no app release, because the next launch registers again.
  Future<bool> registerDevice({
    required String token,
    String platform = 'ios',
    String? environment,
  }) async {
    final dio = _dio;
    if (dio == null || PreviewConfig.enabled) return false;
    final normalised = token.trim().toLowerCase();
    if (!_tokenPattern.hasMatch(normalised)) {
      debugPrint('[Push] refusing to register a malformed token');
      return false;
    }
    try {
      await dio
          .post<Object?>('/notifications/devices', data: {
            'platform': platform,
            'token': normalised,
            'environment': environment ?? apnsEnvironment,
          })
          .timeout(_timeout);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 503) {
        debugPrint('[Push] APNs is not configured on this deployment');
      } else {
        debugPrint('[Push] device register failed: ${e.response?.statusCode ?? e.type}');
      }
      return false;
    } catch (e) {
      debugPrint('[Push] device register failed: $e');
      return false;
    }
  }

  /// `DELETE /notifications/devices`. Authenticated, so it has to run before
  /// the session is cleared on sign-out.
  Future<bool> unregisterDevice({required String token}) async {
    final dio = _dio;
    if (dio == null || PreviewConfig.enabled) return false;
    try {
      await dio
          .delete<Object?>('/notifications/devices',
              data: {'token': token.trim().toLowerCase()})
          .timeout(_timeout);
      return true;
    } catch (e) {
      debugPrint('[Push] device unregister failed: $e');
      return false;
    }
  }

  /// `GET /notifications/social?since=<iso>`. Null on any failure, which leaves
  /// the cursor exactly where it was: a dead network must not skip events.
  ///
  /// The cursor is an ISO timestamp, the `cursor` the previous page answered
  /// with. Without one the server starts from its own `socialSeenAt` marker, so
  /// a fresh install does not replay a month of hartjes.
  ///
  /// A 404 is not logged on every foreground - it is what a deployment older
  /// than the endpoint answers, and the pull is simply unavailable then.
  Future<SocialEventPage?> fetch({String? since, int limit = 50}) async {
    final dio = _dio;
    if (dio == null || PreviewConfig.enabled) return null;
    try {
      final response = await dio
          .get<Object?>('/notifications/social', queryParameters: {
            if (since != null && since.isNotEmpty) 'since': since,
            // `SOCIAL_MAX_PAGE_SIZE` is 100 there; anything above it is a 400.
            'limit': limit.clamp(1, 100),
          })
          .timeout(_timeout);
      return SocialEventPage.tryParse(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        debugPrint('[Social] pull failed: ${e.response?.statusCode ?? e.type}');
      }
      return null;
    } catch (e) {
      debugPrint('[Social] pull failed: $e');
      return null;
    }
  }
}

final socialNotificationsRepositoryProvider =
    Provider<SocialNotificationsRepository>((ref) {
  return SocialNotificationsRepository(ref.watch(apiClientProvider).dio);
});
