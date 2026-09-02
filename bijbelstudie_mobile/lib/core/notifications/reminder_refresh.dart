import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/present/auth_controller.dart';
import '../../features/settings/data/reading_settings.dart';
import 'reminder_copy.dart';
import 'reminder_service.dart';

/// Tops up the locally scheduled reminders with fresh copy from the server.
///
/// `main.dart` re-arms the batch at launch from cache only, because a cold
/// start must not wait on a request. That leaves one gap: without a networked
/// refresh somewhere, the wording would only ever change when the user
/// happened to open the settings screen.
///
/// So this runs once per app session, from the dashboard - the screen almost
/// every session passes through. It is deliberately cheap:
///
/// - nothing happens when no reminder is set
/// - nothing happens while the batch is still fresh, so the usual outcome is
///   one `SharedPreferences` read and no platform calls at all
/// - re-arming fourteen OS notifications only happens when the copy has
///   actually been replaced
///
/// Failure is silent by design. A refresh that cannot reach the server leaves
/// the previously scheduled reminders exactly as they were, which is the
/// correct outcome: stale words beat no reminder.
final reminderCopyRefreshProvider = FutureProvider<void>((ref) async {
  if (kIsWeb) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt(kDailyReminderMinutesKey);
    if (minutes == null) return;

    final copySource = ReminderCopySource(ref.read(apiClientProvider).dio);
    if (!await copySource.needsRefresh()) return;

    await ref.read(reminderServiceProvider).scheduleDaily(
      hour: minutes ~/ 60,
      minute: minutes % 60,
    );
  } catch (_) {
    // See above: the existing schedule stands.
  }
});
