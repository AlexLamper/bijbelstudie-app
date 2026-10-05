import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/preview_config.dart';
import 'social_notifications_store.dart';
import 'social_repository.dart';

/// The MethodChannel `ios/Runner/AppDelegate.swift` opens. Changing the name
/// means changing it in both places.
const String kApnsChannelName = 'nl.bijbelstudie/apns';

/// iOS only, and deliberately tiny: `registerForRemoteNotifications` on the
/// native side, `didRegisterForRemoteNotificationsWithDeviceToken` back.
///
/// There is no Firebase, no `firebase_messaging` and no third-party push SDK
/// behind this - the APNs device token is a UIKit callback, and the backend
/// holds the `.p8` key and talks to `api.push.apple.com` itself. Android never
/// touches this class: it has no push at all, by design, and gets a local
/// notification from the foreground pull instead (see `social_sync.dart`).
class ApnsTokenChannel {
  ApnsTokenChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(kApnsChannelName);

  final MethodChannel _channel;

  /// Whether this platform can have an APNs token at all.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Installs the handler for the three things the native side calls:
  /// a new (or refreshed) token, a failed registration, and the id of an event
  /// a real push just delivered - which is what keeps the pull from raising
  /// the same thing twice.
  void listen({
    required void Function(String token) onToken,
    required void Function(String eventId) onPushDelivered,
    void Function(String message)? onError,
  }) {
    _channel.setMethodCallHandler((call) async {
      final arg = call.arguments;
      switch (call.method) {
        case 'onToken':
          if (arg is String && arg.isNotEmpty) onToken(arg);
        case 'onPushDelivered':
          if (arg is String && arg.isNotEmpty) onPushDelivered(arg);
        case 'onRegistrationError':
          onError?.call(arg is String && arg.isNotEmpty ? arg : 'onbekend');
      }
      return null;
    });
  }

  /// Asks iOS for a device token. Idempotent: UIKit answers with the token it
  /// already holds rather than minting a new one, and it raises no dialog of
  /// its own - the permission prompt is a separate thing, and this is only
  /// ever called once it has been granted.
  Future<void> register() => _invoke('registerForRemoteNotifications');

  /// Tells iOS to stop delivering remote notifications to this install. Called
  /// on sign-out, after the token has been withdrawn server-side.
  Future<void> unregister() => _invoke('unregisterFromRemoteNotifications');

  /// The token the native side already has, if any. A cold start from a push
  /// can beat [listen] to the callback, so AppDelegate holds the last token
  /// and this reads it back.
  Future<String?> currentToken() async {
    if (!supported) return null;
    try {
      final token = await _channel.invokeMethod<String>('getToken');
      return token == null || token.isEmpty ? null : token;
    } on MissingPluginException {
      // An older binary without the channel, or a unit test.
      return null;
    } catch (e) {
      debugPrint('[Push] token read failed: $e');
      return null;
    }
  }

  Future<void> _invoke(String method) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Nothing to do: this build has no native half.
    } catch (e) {
      debugPrint('[Push] $method failed: $e');
    }
  }
}

/// Keeps the backend's idea of this device's APNs token in step with iOS's.
///
/// Four things it has to survive, all of them normal:
/// - **permission denied** - no token is ever issued, so nothing is sent and
///   [pushActive] stays false; the pull then raises locally instead;
/// - **a token before sign-in** - iOS can hand one over at launch, before the
///   session is restored. It is remembered in memory and registered the moment
///   [ensureRegistered] is called with a session;
/// - **a token change** - iOS re-issues after a restore or a reinstall. The
///   last registered token is persisted, so a changed one is re-POSTed and an
///   unchanged one is left alone (re-POSTed once a week, so a row pruned
///   server-side comes back);
/// - **sign-out** - [unregister] withdraws it server-side *before* the session
///   is torn down, then tells iOS to stop.
class SocialDeviceRegistrar {
  SocialDeviceRegistrar(this._repository, {ApnsTokenChannel? channel})
      : _channel = channel ?? ApnsTokenChannel();

  final SocialNotificationsRepository _repository;
  final ApnsTokenChannel _channel;

  /// Re-register after this long even when the token has not changed, so a
  /// device row that was pruned (or a backend that lost one) comes back.
  static const refreshAfter = Duration(days: 7);

  /// The last token iOS handed over this run, registered or not.
  String? _seen;

  /// Whether a real APNs token is registered for this install right now. The
  /// one gate on the iOS side of the dedupe: true means APNs owns delivery and
  /// the pull must not raise a local notification.
  bool get pushActive => _pushActive;
  bool _pushActive = false;

  /// Wires the native callbacks. Call once, early; [onPushDelivered] is how an
  /// event id that arrived as a real push reaches the ledger.
  void start({required void Function(String eventId) onPushDelivered}) {
    if (!ApnsTokenChannel.supported) return;
    _channel.listen(
      onToken: (token) {
        _seen = token;
        // Not awaited: a token can land at any moment and nothing is waiting
        // on it. A failure only means the next foreground tries again.
        unawaited(_sendIfNeeded(token));
      },
      onPushDelivered: onPushDelivered,
      onError: (message) {
        _pushActive = false;
        debugPrint('[Push] APNs registration failed: $message');
      },
    );
  }

  /// Asks iOS for a token and registers it if the backend does not have it.
  ///
  /// [permitted] is the OS notification permission: without it iOS never
  /// issues a token, so asking is pointless. [signedIn] false parks whatever
  /// token we have until there is a session to attach it to.
  Future<void> ensureRegistered({
    required bool signedIn,
    required bool permitted,
  }) async {
    if (!ApnsTokenChannel.supported || PreviewConfig.enabled) return;
    if (!permitted) {
      _pushActive = false;
      return;
    }
    await _channel.register();
    final token = _seen ?? await _channel.currentToken();
    if (token == null) {
      _pushActive = false;
      return;
    }
    _seen = token;
    if (!signedIn) {
      // Registered under no account is worse than not registered: the backend
      // would have nobody to send to. It waits for the next foreground.
      _pushActive = false;
      return;
    }
    await _sendIfNeeded(token);
  }

  Future<void> _sendIfNeeded(String token) async {
    final stored = await SocialNotificationStore.deviceToken();
    final at = await SocialNotificationStore.deviceTokenAt();
    final fresh = stored == token &&
        at != null &&
        DateTime.now().difference(at) < refreshAfter;
    if (fresh) {
      _pushActive = true;
      return;
    }
    final ok = await _repository.registerDevice(token: token);
    if (ok) {
      await SocialNotificationStore.setDeviceToken(token);
      _pushActive = true;
    } else {
      // The endpoint may simply not be there yet. Nothing is cached, so the
      // next foreground tries again; meanwhile the pull is the only path.
      _pushActive = false;
    }
  }

  /// Sign-out: withdraw the token server-side, forget it locally, and stop
  /// iOS from delivering to this install.
  ///
  /// Must run **before** the session is cleared - the DELETE is authenticated.
  Future<void> unregister() async {
    _pushActive = false;
    final token = _seen ?? await SocialNotificationStore.deviceToken();
    if (token != null && token.isNotEmpty) {
      await _repository.unregisterDevice(token: token);
    }
    _seen = null;
    await SocialNotificationStore.clearDeviceToken();
    await _channel.unregister();
  }
}

final socialDeviceRegistrarProvider = Provider<SocialDeviceRegistrar>((ref) {
  return SocialDeviceRegistrar(ref.watch(socialNotificationsRepositoryProvider));
});
