import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// An ink-reacting tap target for the part of a kring row that opens a person.
///
/// Two reasons it is not a bare [InkWell]. An [AppCard] draws its own opaque
/// background over whatever [Material] is behind it, so ink from a plain
/// InkWell inside a card paints underneath that background and is never seen;
/// a transparent Material of its own puts the splash above it. And an InkWell
/// with no Material ancestor at all throws, which is what happens the moment
/// one of these rows is pumped outside a Scaffold - in a test, or in a sheet.
class FriendTapTarget extends StatelessWidget {
  const FriendTapTarget({
    super.key,
    required this.child,
    this.onTap,
    this.circle = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Round ink, for an avatar on its own.
  final bool circle;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: circle ? const CircleBorder() : null,
        borderRadius: circle ? null : BorderRadius.circular(AppTheme.radiusMd),
        child: child,
      ),
    );
  }
}
