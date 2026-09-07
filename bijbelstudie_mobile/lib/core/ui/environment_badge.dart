import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// A small badge naming the API this build is talking to.
///
/// The mirror of the website's `EnvironmentBanner`. A staging build and a store
/// build are identical on screen, and the mistakes that follow from confusing
/// them are quiet and expensive: reporting a bug against a build nobody
/// shipped, or - worse - believing you are on staging while writing to real
/// accounts.
///
/// Renders nothing when the build is on the live API, so it costs a store build
/// one string comparison. It ignores touches, so it can never sit between the
/// reader and a control underneath it.
class EnvironmentBadge extends StatelessWidget {
  const EnvironmentBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final label = AppConfig.environmentLabel;
    if (label == null) return child;

    return Stack(
      children: [
        child,
        Positioned(
          left: 8,
          bottom: 8,
          child: IgnorePointer(
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.teal,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
