import 'package:flutter/foundation.dart';

/// Environment-based configuration for API endpoints
/// Automatically switches between development and production based on build mode
class AppConfig {
  // Production API endpoints
  static const String _productionBaseUrl =
      'https://www.bijbelstudie.io/api/v1';

  // Development API endpoints (localhost).
  // Android emulator: pass --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
  static const String _developmentBaseUrl = 'http://localhost:3000/api/v1';

  /// The staging deployment: the website's `staging` branch on Vercel.
  ///
  /// Vercel's branch URL is stable - it does not change per deployment the way
  /// the per-commit URLs do - so it can be a constant here rather than
  /// something you paste in each time. Staging runs against its own database
  /// (see the website's `lib/appEnv.ts`), so anything done here is safe.
  ///
  /// Build against it with:
  ///   flutter run --dart-define=ENV=staging
  static const String _stagingBaseUrl =
      'https://bijbelstudie-git-staging-dev-f81e211e.vercel.app/api/v1';

  /// `--dart-define=ENV=staging` (or `production`, or unset for the default).
  /// A named target beats pasting a URL: it is the difference between a
  /// one-word flag and a chance to typo the host you are testing against.
  static const String _envName = String.fromEnvironment('ENV', defaultValue: '');

  // Optional dart-define overrides:
  // --dart-define=API_BASE_URL=https://www.bijbelstudie.io/api/v1
  static const String _apiBaseUrlFromDefine = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  // Optional convenience toggle:
  // --dart-define=USE_PRODUCTION_API=true
  static const bool _useProductionApiFromDefine = bool.fromEnvironment(
    'USE_PRODUCTION_API',
    defaultValue: false,
  );

  // Legal links used in subscription and account flows.
  // Override per environment via dart-define if needed.
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://www.bijbelstudie.io/privacybeleid',
  );
  /// The subscription EULA, linked from the paywall. Apple's standard EULA is
  /// used deliberately: it is the one Apple explicitly accepts and it already
  /// carries the auto-renewal terms review checks for.
  static const String termsOfUseUrl = String.fromEnvironment(
    'TERMS_OF_USE_URL',
    defaultValue:
        'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
  );

  /// The product's own Algemene Voorwaarden, linked from the account screens.
  /// Separate from [termsOfUseUrl] so the paywall keeps the EULA while a Dutch
  /// signup screen links Dutch terms.
  static const String termsOfServiceUrl = String.fromEnvironment(
    'TERMS_OF_SERVICE_URL',
    defaultValue: 'https://www.bijbelstudie.io/algemene-voorwaarden',
  );

  /// Get the appropriate API base URL based on build mode
  /// Debug builds use localhost for local development
  /// Release builds use production URL
  static String get apiBaseUrl {
    // An explicit URL always wins, so an ad-hoc preview deployment can still be
    // targeted without adding a constant for it.
    if (_apiBaseUrlFromDefine.isNotEmpty) {
      return _apiBaseUrlFromDefine;
    }

    // Then the named environments. `staging` works in release builds too -
    // which is the point, since a TestFlight build is how the app is really
    // tested before anything reaches the store.
    if (_envName == 'staging') return _stagingBaseUrl;
    if (_envName == 'production') return _productionBaseUrl;

    if (kDebugMode) {
      if (_useProductionApiFromDefine) {
        return _productionBaseUrl;
      }

      // Development mode - use localhost by default
      return _developmentBaseUrl;
    } else {
      // Production/Release mode - use production URL
      return _productionBaseUrl;
    }
  }

  /// Get the base URL without the /api/v1 suffix
  /// Used for constructing image URLs and other resources
  static String get baseUrl {
    final apiUri = Uri.parse(effectiveApiBaseUrl);
    final authority = apiUri.hasPort
        ? '${apiUri.host}:${apiUri.port}'
        : apiUri.host;
    return '${apiUri.scheme}://$authority';
  }

  /// Returns whether app is in debug mode
  static bool get isDebugMode => kDebugMode;

  /// Returns whether app is in production/release mode
  static bool get isProduction => !kDebugMode;

  /// For testing purposes: override the API URL
  static String? _customApiBaseUrl;

  /// Set a custom API base URL (useful for testing against different servers)
  static void setCustomApiBaseUrl(String? url) {
    _customApiBaseUrl = url;
  }

  /// Get the actual API URL to use (respects custom override)
  static String get effectiveApiBaseUrl => _customApiBaseUrl ?? apiBaseUrl;

  /// True when this build talks to the live site and its live database.
  ///
  /// Read from the URL actually in use rather than from the build mode: a
  /// release build pointed at staging is not production, and a debug build
  /// pointed at the live API very much is.
  static bool get isLiveApi =>
      effectiveApiBaseUrl.startsWith('https://www.bijbelstudie.io');

  /// A short label for the badge, or null when this build is on the live API
  /// and there is nothing to warn anybody about.
  static String? get environmentLabel {
    if (isLiveApi) return null;
    if (effectiveApiBaseUrl == _stagingBaseUrl) return 'STAGING';
    final host = Uri.tryParse(effectiveApiBaseUrl)?.host;
    return host == null || host.isEmpty ? 'DEV' : 'DEV · $host';
  }
}
