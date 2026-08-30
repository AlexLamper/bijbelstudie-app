import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../../core/config/apple_sign_in_config.dart';

/// Renders an Apple-approved "Sign in with Apple" button.
/// Returns an empty widget on non-Apple platforms (Android, web).
///
/// Guideline 4.8 is why this sits next to the Google button rather than
/// instead of it: an app that offers a third-party login on iOS must also
/// offer a privacy-preserving equivalent. Sign in with Apple is that
/// equivalent, so the two ship together or Google does not ship at all.
Widget buildAppleSignInButton({
  required VoidCallback? onPressed,
  required bool isLoading,
}) {
  // `defaultTargetPlatform`, not `dart:io`'s `Platform`: importing dart:io
  // here would fail to compile the web build the moment this widget is
  // actually referenced from a screen.
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return const SizedBox.shrink();
  }

  return FutureBuilder<bool>(
    future: SignInWithApple.isAvailable(),
    builder: (context, snapshot) {
      final appleAvailable =
          (snapshot.data == true) || AppleSignInConfig.hasWebFallbackConfig;
      if (!appleAvailable) {
        return const SizedBox.shrink();
      }

      return AbsorbPointer(
        absorbing: isLoading || onPressed == null,
        child: Opacity(
          opacity: (isLoading || onPressed == null) ? 0.5 : 1.0,
          child: SignInWithAppleButton(onPressed: onPressed ?? () {}),
        ),
      );
    },
  );
}

/// Whether the button above would render anything on this platform.
///
/// The screens need to know before laying out the divider, and a divider
/// above an empty box reads as a broken screen.
bool get isAppleSignInAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
