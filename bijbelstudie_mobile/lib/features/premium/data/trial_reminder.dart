import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../domain/trial_offer.dart';

final trialReminderProvider = Provider<TrialReminder>((ref) {
  return TrialReminder(NotificationService.instance);
});

/// The local "je proefperiode eindigt bijna" notification.
///
/// The paywall's timeline promises it ("Dag 5: we sturen je een herinnering"),
/// so it is scheduled the moment a trial purchase completes. It is the single
/// most effective guard against the "free trial isn't free" reviews that sink
/// faith apps, and Blinkist's timeline-plus-reminder paywall raised trial
/// conversion while cutting complaints.
class TrialReminder {
  TrialReminder(this._service);

  final NotificationService _service;

  /// When the reminder fires for a trial that started at [start]: the morning
  /// of [TrialOffer.reminderDay], at 10:00 local, outside quiet hours.
  static DateTime fireAt(TrialOffer trial, DateTime start) {
    final day = DateTime(start.year, start.month, start.day).add(Duration(days: trial.reminderDay));
    return DateTime(day.year, day.month, day.day, 10);
  }

  /// The words, with the days left counted from the reminder to the charge.
  static ({String title, String body}) copy(TrialOffer trial) {
    final left = trial.days - trial.reminderDay;
    final when = left == 1 ? 'morgen' : 'over $left dagen';
    return (
      title: 'Je proefperiode eindigt $when',
      body: 'Daarna gaat je jaarabonnement in. Wil je niet verder, zeg dan vóór die tijd op - '
          'dat kan met twee tikken.',
    );
  }

  Future<void> schedule(TrialOffer trial, {DateTime? now}) async {
    final start = now ?? DateTime.now();
    final at = fireAt(trial, start);
    if (!at.isAfter(start)) return;
    final words = copy(trial);
    await _service.scheduleTrialReminder(at, title: words.title, body: words.body);
  }
}
