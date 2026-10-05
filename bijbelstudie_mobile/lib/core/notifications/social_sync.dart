import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/friends/present/friends_providers.dart';
import '../../features/settings/data/notification_prefs.dart';
import '../config/preview_config.dart';
import 'notification_scheduler.dart' show notificationSessionProvider;
import 'notification_service.dart';
import 'social_notifications_store.dart';
import 'social_push.dart';
import 'social_repository.dart';

/// What one [SocialSync.sync] did, for the tests and for a debug line.
class SocialSyncOutcome {
  const SocialSyncOutcome({
    this.fetched = 0,
    this.fresh = 0,
    this.raised = 0,
    this.alreadyDelivered = 0,
    this.pendingRequests = 0,
    this.pushEnabled = false,
    this.ran = false,
  });

  static const none = SocialSyncOutcome();

  /// Events the page carried.
  final int fetched;

  /// Of those, the ones not in the delivered ledger.
  final int fresh;

  /// Of those, the ones a local notification was raised for. Zero on iOS while
  /// APNs is live, and zero whenever the reader has the social notifications
  /// switched off, is inside quiet hours, or has no OS permission.
  final int raised;

  /// Events the ledger had already seen - a push that beat the pull, or a
  /// cursor that failed to persist.
  final int alreadyDelivered;

  /// Pending incoming verzoeken, as the server counts them. Independent of the
  /// cursor, so it is right even on a run that fetched nothing new.
  final int pendingRequests;

  /// Whether the backend can push at all (`pushEnabled` in its answer). False
  /// means APNs is not configured there and even an iPhone uses the local path.
  final bool pushEnabled;

  /// False when the pull never happened at all (web, preview, signed out, or
  /// throttled).
  final bool ran;
}

/// The Android path, and the iOS offline reconcile.
///
/// Android gets **no push**: the owner rejected Firebase, and APNs has no
/// equivalent you can reach without FCM. So on Android the server is pulled
/// once, when the app comes to the foreground, and anything new becomes a badge
/// plus a local notification on the `social` channel. The honest limitation:
/// **an Android device that never opens the app learns nothing.** That is the
/// trade, by design.
///
/// iOS runs the same pull, but normally only for the badge and the cursor: a
/// real push has already shown the notification. [_raisesLocally] is the
/// structural half of the dedupe - nothing is raised on iOS while there is an
/// APNs token *and* the server says it can push (`pushEnabled`; a deployment
/// with no APNs key cannot, and then even an iPhone needs the local path).
/// [SocialNotificationStore.delivered] is the other half: an event a push
/// delivered is skipped by id even when iOS has fallen back to the local path -
/// no token, say, because registration failed.
///
/// There is no polling loop here and no timer. The only caller is
/// `app_lifecycle.dart`'s `_onForeground`, and a run is throttled to one a
/// minute so three resumes in a row are one request.
class SocialSync {
  SocialSync(this._ref);

  final Ref _ref;

  /// At most this many local notifications per run, however much the pull
  /// returns: coming back after a week with eleven hartjes should be a badge
  /// and one or two notifications, not eleven.
  static const maxRaisedPerSync = 3;

  /// How many `hasMore` pages one run follows before giving up and leaving the
  /// rest for the next foreground.
  static const maxPagesPerSync = 4;

  /// Two resumes inside this window are one pull.
  static const throttle = Duration(minutes: 1);

  bool _running = false;
  DateTime? _lastRun;
  bool _started = false;

  /// Installs the APNs callbacks. Idempotent; called from [requestSync] so the
  /// handler is in place from the first foreground on.
  void _start() {
    if (_started) return;
    _started = true;
    _ref.read(socialDeviceRegistrarProvider).start(
          // A push that iOS delivered while the app was running: its id goes
          // straight into the same ledger the pull reads, so the next pull
          // does not raise it again.
          onPushDelivered: (eventId) =>
              unawaited(SocialNotificationStore.markDeliveredOne(eventId)),
        );
  }

  /// "Please catch up on the vriendenkring", callable from anywhere. Never
  /// throws and never awaited by the caller.
  void requestSync({bool force = false}) {
    if (kIsWeb) return;
    _start();
    unawaited(sync(force: force).catchError((Object e, StackTrace st) {
      debugPrint('[Social] sync failed: $e\n$st');
      return SocialSyncOutcome.none;
    }));
  }

  Future<SocialSyncOutcome> sync({bool force = false, DateTime? now}) async {
    if (kIsWeb || PreviewConfig.enabled) return SocialSyncOutcome.none;
    final at = now ?? DateTime.now();
    final last = _lastRun;
    if (!force && (_running || (last != null && at.difference(last) < throttle))) {
      return SocialSyncOutcome.none;
    }
    _running = true;
    try {
      return await _sync(at);
    } finally {
      _running = false;
      _lastRun = at;
    }
  }

  Future<SocialSyncOutcome> _sync(DateTime at) async {
    final signedIn = await _ref.read(notificationSessionProvider)();
    if (!signedIn) return SocialSyncOutcome.none;

    final service = _ref.read(notificationServiceProvider);
    final registrar = _ref.read(socialDeviceRegistrarProvider);
    final repository = _ref.read(socialNotificationsRepositoryProvider);

    final prefsCtl = _ref.read(notificationPrefsProvider.notifier);
    await prefsCtl.loaded;
    final prefs = _ref.read(notificationPrefsProvider);

    final permitted = await service.hasPermission();
    // A token is only ever asked for once permission is there, and only once
    // there is a session to attach it to. Both are true here.
    await registrar.ensureRegistered(signedIn: true, permitted: permitted);

    var fetched = 0;
    var fresh = 0;
    var raised = 0;
    var alreadyDelivered = 0;
    var pendingRequests = 0;
    var pushEnabled = false;
    var anythingFresh = false;

    // `hasMore` means the page was cut short, so the cursor is followed a bounded
    // number of times to let it catch up. Bounded, not "until done": a run has to
    // end, and whatever is left waits for the next foreground.
    for (var page = 0; page < maxPagesPerSync; page++) {
      final result = await repository.fetch(since: await SocialNotificationStore.cursor());
      // Null is "we do not know" - offline, or the endpoint is not there on this
      // deployment. The cursor stays where it is so nothing is skipped.
      if (result == null) break;

      fetched += result.events.length;
      pendingRequests = result.pendingRequests;
      pushEnabled = result.pushEnabled;

      final ledger = (await SocialNotificationStore.delivered()).toSet();
      final unseen = [
        for (final event in result.events)
          if (!SocialNotificationStore.wasDelivered(
            ledger,
            eventId: event.id,
            ledgerKey: event.ledgerKey,
          ))
            event,
      ];
      fresh += unseen.length;
      alreadyDelivered += result.events.length - unseen.length;
      if (unseen.isNotEmpty) anythingFresh = true;

      raised += await _raise(
        service,
        registrar,
        prefs,
        unseen,
        at,
        pushEnabled: pushEnabled,
        budget: maxRaisedPerSync - raised,
      );

      // Ledger before cursor: if one of the two writes fails, the one that
      // replays is the harmless one. Every event is recorded, not only the ones a
      // notification was raised for - on the path where nothing is raised the
      // badge *is* the notification, and it must not be announced again later.
      await SocialNotificationStore.markDelivered(
        result.events.map((event) => event.ledgerKey),
      );
      // A page without a cursor leaves the stored one where it is: clearing it
      // would send the next pull back to the server's own marker and replay
      // everything the ledger has since forgotten.
      if (result.cursor != null) {
        await SocialNotificationStore.setCursor(result.cursor);
      }

      if (!result.hasMore || result.cursor == null) break;
    }

    if (anythingFresh) _refreshBadge();

    return SocialSyncOutcome(
      fetched: fetched,
      fresh: fresh,
      raised: raised,
      alreadyDelivered: alreadyDelivered,
      pendingRequests: pendingRequests,
      pushEnabled: pushEnabled,
      ran: true,
    );
  }

  /// Raises at most [maxRaisedPerSync] local notifications for [events], and
  /// returns how many it raised.
  ///
  /// Every reason not to, in the order they are checked: the OS has not given
  /// permission; the reader turned all notifications off; they switched the
  /// vriendenkring ones off; they pressed "sla vandaag over"; it is the middle
  /// of their night; or iOS already pushed it.
  Future<int> _raise(
    NotificationService service,
    SocialDeviceRegistrar registrar,
    NotificationPrefs prefs,
    List<SocialEvent> events,
    DateTime at, {
    required bool pushEnabled,
    required int budget,
  }) async {
    if (events.isEmpty || budget <= 0) return 0;
    if (!_raisesLocally(registrar, pushEnabled: pushEnabled)) return 0;
    if (!await service.hasPermission()) return 0;
    if (!prefs.masterEnabled || prefs.snoozedNow) return 0;
    if (!await SocialNotificationStore.enabled()) return 0;
    if (prefs.quietHours.contains(at.hour * 60 + at.minute)) return 0;

    var raised = 0;
    // Oldest first, so the newest ends up on top of the tray.
    final ordered = [...events]..sort((a, b) {
      final x = a.createdAt, y = b.createdAt;
      if (x == null || y == null) return 0;
      return x.compareTo(y);
    });
    for (final event in ordered.length <= budget
        ? ordered
        : ordered.sublist(ordered.length - budget)) {
      final type = event.type;
      try {
        await service.showNow(
          type,
          RenderedVariant(
            variantId: 'social:${event.kind.name}',
            title: event.title,
            body: event.body,
          ),
          deepLink: event.route,
          slot: await SocialNotificationStore.nextSlot(type.idRange.length),
        );
        raised += 1;
      } catch (e) {
        // One failed write must not cost the rest, and it must not cost the
        // cursor either: the id is recorded as delivered regardless, because a
        // notification that could not be shown twice is not worth showing late.
        debugPrint('[Social] show failed for ${event.id}: $e');
      }
    }
    return raised;
  }

  /// iOS with a live APNs token on a deployment that can push raises nothing:
  /// Apple already delivered it. Everything else uses the local path - Android
  /// always (no push exists there), and iOS whose registration failed, whose
  /// permission was never granted, or whose backend has no APNs key
  /// ([pushEnabled] false, the server's own `PUSH_NOT_CONFIGURED`).
  bool _raisesLocally(
    SocialDeviceRegistrar registrar, {
    required bool pushEnabled,
  }) {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;
    return !(pushEnabled && registrar.pushActive);
  }

  /// The in-app badge. `friendsBadgeProvider` is derived from the feed's own
  /// `newActivityCount`, which the server computes, so the badge is refreshed
  /// by refetching rather than by keeping a second count here. Only when
  /// something is already listening: waking the providers for a screen nobody
  /// is looking at would add two requests to every foreground.
  void _refreshBadge() {
    if (_ref.exists(friendsFeedProvider)) {
      unawaited(
        _ref.read(friendsFeedProvider.notifier).refresh().catchError(
              (Object e) => debugPrint('[Social] feed refresh failed: $e'),
            ),
      );
    }
    if (_ref.exists(friendsRequestsProvider)) {
      _ref.invalidate(friendsRequestsProvider);
    }
  }
}

final socialSyncProvider = Provider<SocialSync>((ref) => SocialSync(ref));
