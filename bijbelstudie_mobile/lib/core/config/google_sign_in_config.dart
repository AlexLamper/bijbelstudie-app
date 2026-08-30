import 'package:flutter/foundation.dart';

/// Google Sign-In client ids, supplied at build time.
///
/// Google issues a *different* OAuth client per platform and the app must send
/// the right one, because the server pins the ID token's `aud` claim
/// (`lib/oauthVerify.ts` → `googleAudiences()`). A token minted for another
/// client is a perfectly valid JWT and is rejected on purpose.
///
///  - **Web / Android** use the *web* client id. On Android it is passed as
///    `serverClientId`, which is what makes `google_sign_in` v7 return an
///    `idToken` at all; the Android client itself is matched by package name
///    and SHA-1/SHA-256 fingerprint rather than by an id in the binary.
///  - **iOS** uses its own iOS client id, and additionally needs that id's
///    reversed form registered as a URL scheme in `ios/Runner/Info.plist` so
///    the browser can hand the result back to the app.
///
/// Nothing is hardcoded: an unset define means the Google button is hidden on
/// that platform rather than shown and broken.
class GoogleSignInConfig {
  /// `--dart-define=GOOGLE_WEB_CLIENT_ID=...`
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  /// `--dart-define=GOOGLE_IOS_CLIENT_ID=...`
  ///
  /// Create it under the same Google Cloud project as the web client, type
  /// "iOS", bundle id `com.bijbel-studie.app`. Then add the id to
  /// `GOOGLE_MOBILE_CLIENT_IDS` on Vercel (comma-separated, alongside the web
  /// client id) or the server will reject every token it mints.
  static const String iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  /// The client id to hand `GoogleSignIn.initialize`, or null to let the
  /// platform resolve it from its own config (`google-services.json` on
  /// Android, `GIDClientID` in `Info.plist` on iOS).
  static String? get clientId {
    if (kIsWeb) return webClientId.isEmpty ? null : webClientId;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return iosClientId.isEmpty ? null : iosClientId;
    }
    return null;
  }

  /// Android needs the *web* client id here to get an `idToken` back.
  static String? get serverClientId {
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    return webClientId.isEmpty ? null : webClientId;
  }

  /// Whether to offer "Inloggen met Google" on this platform at all.
  ///
  /// A button that cannot possibly work is worse than no button: on iOS it was
  /// hidden outright until an iOS OAuth client existed. That is now a config
  /// question rather than a hardcoded platform check, so shipping the client
  /// id turns it on with no code change — and forgetting to ship it leaves the
  /// screen exactly as it was, with Sign in with Apple and email/password.
  static bool get isAvailable {
    if (kIsWeb) return webClientId.isNotEmpty;
    if (defaultTargetPlatform == TargetPlatform.iOS) return iosClientId.isNotEmpty;
    if (defaultTargetPlatform == TargetPlatform.android) return webClientId.isNotEmpty;
    return false;
  }
}
