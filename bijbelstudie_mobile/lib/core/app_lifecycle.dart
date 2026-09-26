import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/levensboom/present/levensboom_providers.dart';
import 'notifications/notification_scheduler.dart';
import 'notifications/retention_store.dart';

/// Re-runs the notification scheduler at launch and on every foreground
/// (`RETENTION_PLAN.md` §4.1). Because
/// `flutter_local_notifications` cannot evaluate a condition at fire time,
/// every condition is re-evaluated here and the one-shots are (re)written.
///
/// Opening the app is also what the evening slot waits for: today's evening
/// is cancelled straight away on launch and resume (DAILY_HABIT_PLAN.md §1),
/// before the recompute, so a slow network can never let it through.
class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver(this._ref);

  final Ref _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _onForeground(_ref);
        // The tree wilts with time, not with what the app did, so a session
        // resumed the next morning has to re-read it or the reader sees
        // yesterday's health until they navigate somewhere that refetches.
        _refreshTree();
      // No recompute on pause: launch/resume and every completion already
      // re-arm the batch, and a cancel-then-schedule pass started while the OS
      // suspends the app can be cut off halfway, leaving the day unarmed.
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _refreshTree() {
    // Only when something is already listening: waking a disposed provider on
    // every foreground would add a request for a screen nobody is looking at.
    if (!_ref.exists(treeStateProvider)) return;
    Future(() => _ref.read(treeStateProvider.notifier).refresh()).catchError(
        (Object e) => debugPrint('[Lifecycle] tree refresh failed: $e'));
  }
}

/// Registers the observer for the life of the app. Watched once from
/// `BijbelStudieApp.build`.
///
/// The launch only counts as an open when the app is really in the
/// foreground. The OS can start the process without showing it (iOS
/// prewarming, Android starting it for a notification action or a boot
/// receiver); marking that as "opened" would cancel today's evening for a
/// reader who never saw the app. In that case the first `resumed` does it.
final appLifecycleProvider = Provider<void>((ref) {
  if (kIsWeb) return;
  final observer = _AppLifecycleObserver(ref);
  final binding = WidgetsBinding.instance;
  binding.addObserver(observer);
  ref.onDispose(() => binding.removeObserver(observer));

  if (isForegroundState(binding.lifecycleState)) _onForeground(ref);
});

/// Only `resumed` is the reader looking at the app; `null` (not reported
/// yet), `inactive`, `hidden` and `paused` are not.
@visibleForTesting
bool isForegroundState(AppLifecycleState? state) =>
    state == AppLifecycleState.resumed;

/// An open: mark it, drop today's evening, and do a recompute.
void _onForeground(Ref ref) {
  ref.read(retentionStoreProvider.notifier).markOpened();
  _cancelTodayEvening(ref);
  ref
      .read(notificationReschedulerProvider)
      .requestReschedule(contentChanged: false);
}

void _cancelTodayEvening(Ref ref) {
  Future(() => NotificationScheduler.cancelTodayEvening(ref)).catchError(
      (Object e) => debugPrint('[Notifications] evening cancel failed: $e'));
}
