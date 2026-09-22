import 'package:flutter/material.dart';
import '../../../../core/ui/primary_button.dart';
import 'google_logo_icon.dart';

Widget buildButton({
  required BuildContext context,
  required VoidCallback? onPressed,
  required bool isLoading,
}) {
  return PrimaryButton(
    // The same wording the website uses ("Verdergaan met Google"), and for the
    // same reason: one button that both signs in and registers. "Inloggen met
    // Google" on the register screen read as a dead end to anyone who did not
    // have an account yet, which is the one group it is meant to serve.
    text: 'Verdergaan met Google',
    isSecondary: true,
    isLoading: isLoading,
    onPressed: isLoading ? null : onPressed,
    leading: const GoogleLogoIcon(size: 20),
  );
}
