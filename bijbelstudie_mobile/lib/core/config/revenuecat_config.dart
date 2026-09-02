import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat **SDK (public) API keys** for the Purchases Flutter SDK.
///
/// These are **not** the same as server secrets. RevenueCat expects you to ship
/// the platform-specific public key inside the mobile app. Anyone can extract
/// them from the binary; security for purchases comes from Apple/Google +
/// RevenueCat validation, not from hiding this string.
///
/// There is deliberately **no hardcoded default** for this app. A key baked in
/// as a build-time default is a key nobody remembers to rotate, and a wrong one
/// silently points purchases at the wrong RevenueCat project. Pass them at
/// build/run time:
///
/// ```bash
/// flutter run --dart-define=REVENUECAT_APPLE_KEY=appl_xxx --dart-define=REVENUECAT_GOOGLE_KEY=goog_xxx
/// ```
///
/// **Test Store** (no App Store / Play setup yet): use one key for both:
///
/// ```bash
/// flutter run --dart-define=REVENUECAT_TEST_KEY=test_xxx
/// ```
///
/// CI injects them from GitHub Actions secrets — see
/// `.github/workflows/ios-release.yml`.
class RevenueCatConfig {
  RevenueCatConfig._();

  /// Public RevenueCat **iOS** SDK key. Supplied only via
  /// `--dart-define=REVENUECAT_APPLE_KEY=...`.
  static const String _defaultApplePublicKey = '';

  /// Public RevenueCat **Android** SDK key. Supplied only via
  /// `--dart-define=REVENUECAT_GOOGLE_KEY=...`.
  static const String _defaultGooglePublicKey = '';

  /// Optional: RevenueCat **Test Store** key (`test_...`) for early integration
  /// testing before iOS/Android store apps are linked.
  static const String testKey = String.fromEnvironment(
    'REVENUECAT_TEST_KEY',
    defaultValue: '',
  );

  static const String appleKey = String.fromEnvironment(
    'REVENUECAT_APPLE_KEY',
    defaultValue: _defaultApplePublicKey,
  );

  static const String googleKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_KEY',
    defaultValue: _defaultGooglePublicKey,
  );

  /// Set true only when you explicitly want to run against RevenueCat Test Store.
  static const bool useTestStore = bool.fromEnvironment(
    'REVENUECAT_USE_TEST_STORE',
    defaultValue: false,
  );

  static bool get _isApplePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Human-readable source for diagnostics/logging.
  static String sdkKeySource() {
    if (kIsWeb) return 'none:web';
    if (useTestStore && testKey.isNotEmpty) return 'test_store';
    if (_isApplePlatform) return appleKey.isNotEmpty ? 'apple' : 'none:apple';
    return googleKey.isNotEmpty ? 'google' : 'none:google';
  }

  /// Key used by [Purchases.configure] in [main.dart].
  static String sdkPublicApiKey() {
    if (kIsWeb) return '';

    // Test Store should be opt-in; avoid accidental usage in TestFlight/release.
    if (useTestStore && testKey.isNotEmpty) return testKey;

    if (_isApplePlatform) {
      return appleKey;
    }

    return googleKey;
  }

  /// Whether `Purchases.configure` has actually run in this process.
  ///
  /// Returns false rather than throwing when the plugin is not registered at
  /// all (unit tests, desktop), so callers can treat it as a plain question.
  static Future<bool> isConfigured() async {
    if (kIsWeb) return false;
    try {
      return await Purchases.isConfigured;
    } catch (_) {
      return false;
    }
  }

  /// Configures the SDK if it is not configured yet, and reports whether the
  /// store is reachable afterwards.
  ///
  /// `main.dart` configures at launch but deliberately swallows any failure so
  /// a RevenueCat outage cannot stop the app from starting. That leaves a real
  /// hole: after a failed launch-time configure, every store call throws an
  /// opaque platform error for the rest of the run and no amount of tapping
  /// "opnieuw proberen" can recover it. Calling this before loading prices
  /// closes that hole — it is a no-op when the SDK is already up.
  static Future<bool> ensureConfigured() async {
    if (kIsWeb) return false;
    final key = sdkPublicApiKey();
    if (key.isEmpty) return false;
    if (await isConfigured()) return true;
    try {
      await Purchases.configure(PurchasesConfiguration(key));
      return true;
    } catch (_) {
      return false;
    }
  }
}
