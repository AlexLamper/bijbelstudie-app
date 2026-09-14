import 'dart:async';

import 'package:flutter/material.dart';

/// How long a SnackBar with an action stays up before it goes away on its own.
const kActionSnackBarDuration = Duration(seconds: 4);

/// Shows [snackBar] and guarantees it dismisses itself after its duration.
///
/// Flutter's own timeout skips any SnackBar that has an action whenever
/// `MediaQuery.accessibleNavigation` is true - VoiceOver or Switch Control on
/// iOS, and on Android *any* enabled accessibility service, which includes
/// password managers and similar apps. For those users "Notitie verwijderd"
/// with "Ongedaan maken" never went away. This closes it explicitly instead.
///
/// Anything already showing or queued is cleared first, so [snackBar] is the
/// current one and closing its controller cannot hit a different SnackBar.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showTimedSnackBar(
  ScaffoldMessengerState messenger,
  SnackBar snackBar,
) {
  messenger
    ..clearSnackBars()
    ..removeCurrentSnackBar();
  final controller = messenger.showSnackBar(snackBar);

  // The framework's timer starts once the entrance animation (250ms) is done;
  // match that so the action is tappable for the full duration.
  final timer = Timer(snackBar.duration + const Duration(milliseconds: 250), () {
    if (messenger.mounted) controller.close();
  });
  controller.closed.whenComplete(timer.cancel);
  return controller;
}
