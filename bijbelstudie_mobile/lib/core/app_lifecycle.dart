import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications/notification_scheduler.dart';
import 'notifications/retention_store.dart';

/// Re-runs the notification scheduler on every foreground and arms the
/// "on close" one-shots on background (`RETENTION_PLAN.md` §4.1). Because
/// `flutter_local_notifications` cannot evaluate a condition at fire time,
/// every condition is re-evaluated here and the one-shots are (re)written.
class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver(this._ref);

  final Ref _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _ref.read(retentionStoreProvider.notifier).markOpened();
        _recompute();
      case AppLifecycleState.paused:
        // Arm the dormant ladder and tomorrow's at-risk/lost before we lose
        // the chance to run.
        _recompute();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _recompute() {
    // Fire-and-forget; a scheduler hiccup must never surface to the user.
    Future(() => NotificationScheduler.recompute(_ref)).catchError((_) {});
  }
}

/// Registers the observer for the life of the app. Watched once from
/// `BijbelStudieApp.build`.
final appLifecycleProvider = Provider<void>((ref) {
  if (kIsWeb) return;
  final observer = _AppLifecycleObserver(ref);
  final binding = WidgetsBinding.instance;
  binding.addObserver(observer);
  ref.onDispose(() => binding.removeObserver(observer));

  // Mark this launch as an "open" and do a first recompute.
  ref.read(retentionStoreProvider.notifier).markOpened();
  Future(() => NotificationScheduler.recompute(ref)).catchError((_) {});
});
