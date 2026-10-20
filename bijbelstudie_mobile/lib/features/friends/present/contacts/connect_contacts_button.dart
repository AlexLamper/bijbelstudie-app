import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_widgets.dart';

/// "Verbind Contacten": the full-width row at the top of Vriendenkring.
///
/// The platform's own contacts mark on the left, the label beside it and a
/// plain chevron on the right, in the app's card style. It only reports the
/// tap: the caller opens `ContactsDisclosureScreen`, which stays the one route
/// to the OS permission prompt.
class ConnectContactsButton extends StatelessWidget {
  const ConnectContactsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const label = 'Verbind Contacten';

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final scheme = Theme.of(context).colorScheme;
    final platform = Theme.of(context).platform;
    final apple = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        borderColor: AppTheme.teal,
        onTap: onPressed,
        child: Row(
          children: [
            Icon(
              apple ? CupertinoIcons.person_crop_circle : Icons.contacts,
              size: 26,
              color: AppTheme.teal,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppTheme.bodyStrong.copyWith(fontSize: 16, color: scheme.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              apple ? CupertinoIcons.chevron_right : Icons.chevron_right,
              size: apple ? 18 : 22,
              color: AppTheme.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
