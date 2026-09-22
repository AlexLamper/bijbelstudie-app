import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The running Android API level, read once at startup.
///
/// Android 15 (API 35) turned edge-to-edge on for every app targeting SDK 35
/// or higher - this app targets 36, so there is no opting out - and in the
/// same release deprecated the window APIs that used to colour the two system
/// bars: `setStatusBarColor`, `setNavigationBarColor`,
/// `setNavigationBarDividerColor` and `setNavigationBarContrastEnforced`. On
/// 35+ they do nothing at all; the platform draws both bars transparent by
/// itself. Google Play flags an app that still calls them.
///
/// Flutter forwards those four values only when the corresponding field of a
/// [SystemUiOverlayStyle] is non-null, so leaving them null on 35+ removes the
/// calls entirely. Below 35 they still have to be set, or the navigation bar
/// keeps the opaque colour from the launch theme and the band under every
/// bottom bar comes back - so this is a version check, not a deletion.
///
/// The icon-brightness fields are deliberately *not* gated: those go through
/// `WindowInsetsController`, which is current API on every supported release.
abstract final class AndroidSdk {
  static const MethodChannel _channel = MethodChannel(
    'com.bijbelstudie.app/platform',
  );

  static int _sdkInt = 0;

  /// The API level, or 0 on any non-Android platform and before [load] runs.
  static int get sdkInt => _sdkInt;

  /// Whether the OS enforces edge-to-edge and ignores the deprecated bar
  /// colour setters. False on iOS and on the web, where the question does not
  /// arise and the Android-only fields are ignored anyway.
  static bool get enforcesEdgeToEdge => _sdkInt >= 35;

  /// Reads the API level. Safe to call on any platform and more than once;
  /// a failure leaves [sdkInt] at 0, which keeps the pre-15 behaviour.
  static Future<void> load() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      _sdkInt = await _channel.invokeMethod<int>('getSdkInt') ?? 0;
    } on PlatformException catch (error) {
      debugPrint('[AndroidSdk] API level unavailable: ${error.message}');
    } on MissingPluginException {
      // Widget tests run without the host activity; the default is correct.
    }
  }

  @visibleForTesting
  static void debugSetSdkInt(int value) => _sdkInt = value;
}
