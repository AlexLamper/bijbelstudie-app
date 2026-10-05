import Flutter
import UIKit
import UserNotifications
// For FlutterLocalNotificationsPlugin.setPluginRegistrantCallback.
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// The APNs side of the vriendenkring notifications. iOS gets real push,
  /// straight from Apple: `registerForRemoteNotifications` here, the device
  /// token back in `didRegisterForRemoteNotificationsWithDeviceToken`, and over
  /// to Dart on this one channel. No Firebase, no FCM, no push SDK and no new
  /// dependency - the backend holds the `.p8` key and talks to
  /// `api.push.apple.com` itself.
  ///
  /// Must match `kApnsChannelName` in
  /// `lib/core/notifications/social_push.dart`.
  private static let apnsChannelName = "nl.bijbelstudie/apns"

  private var apnsChannel: FlutterMethodChannel?

  /// The last token iOS issued. A cold start from a push can beat Dart's
  /// handler to the callback, so it is held here and read back with `getToken`.
  private var lastDeviceToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // "Later vandaag" runs in a background engine; without this it has no
    // plugins and cannot re-post the notification.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: self)
    // Without a delegate iOS neither routes notification taps to the app nor
    // shows a notification that fires while the app is open.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    // Opened here rather than on first use, so a push that arrives seconds
    // after launch already has somewhere to go.
    _ = ensureApnsChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The channel, created on the Flutter view controller the storyboard already
  /// put in the window. Nil only if that controller is not there yet, in which
  /// case the next call tries again.
  private func ensureApnsChannel() -> FlutterMethodChannel? {
    if let existing = apnsChannel {
      return existing
    }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return nil
    }
    let channel = FlutterMethodChannel(
      name: AppDelegate.apnsChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "registerForRemoteNotifications":
        // Dart only calls this once notification permission has been granted,
        // so it raises no dialog of its own. Calling it again is free: UIKit
        // answers with the token it already holds.
        UIApplication.shared.registerForRemoteNotifications()
        result(nil)
      case "unregisterFromRemoteNotifications":
        // Sign-out. The token has already been withdrawn server-side.
        UIApplication.shared.unregisterForRemoteNotifications()
        self?.lastDeviceToken = nil
        result(nil)
      case "getToken":
        result(self?.lastDeviceToken)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    apnsChannel = channel
    return channel
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    lastDeviceToken = hex
    ensureApnsChannel()?.invokeMethod("onToken", arguments: hex)
    // FlutterAppDelegate hands the token on to any plugin that wants it.
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    lastDeviceToken = nil
    ensureApnsChannel()?.invokeMethod(
      "onRegistrationError",
      arguments: error.localizedDescription
    )
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  /// A push that arrived while the app was running. Its event id goes to Dart so
  /// the foreground pull does not raise the same hartje a second time as a local
  /// notification. The backend puts it in the payload as `eventId`.
  ///
  /// Note: without the `remote-notification` background mode this only fires
  /// with the app in the foreground, which is deliberate - that mode is for
  /// silent pushes, it costs an extra round of App Review scrutiny, and the
  /// pull's own event-id ledger already covers the rest.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if let eventId = userInfo["eventId"] as? String, !eventId.isEmpty {
      ensureApnsChannel()?.invokeMethod("onPushDelivered", arguments: eventId)
    }
    super.application(
      application,
      didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler
    )
  }
}
