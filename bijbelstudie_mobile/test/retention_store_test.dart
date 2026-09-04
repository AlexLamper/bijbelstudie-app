import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bijbelstudie_mobile/core/notifications/notification_service.dart';
import 'package:bijbelstudie_mobile/core/notifications/retention_store.dart';

/// The local habit mirror (`RETENTION_PLAN.md` §2). It only ever decides
/// whether to *nudge*, so its one hard requirement is that a timezone change or
/// a clock rewind can never inflate or destroy a count.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('date keys', () {
    test('dayKey is a lexicographically ordered wall-clock date', () {
      expect(retentionDayKey(DateTime(2026, 9, 4)), '2026-09-04');
      expect(retentionDayKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect('2026-09-04'.compareTo('2026-09-05') < 0, isTrue);
    });

    test('dayGap counts whole days, negative on a rewind', () {
      expect(retentionDayGap('2026-09-01', '2026-09-03'), 2);
      expect(retentionDayGap('2026-09-03', '2026-09-02'), -1);
    });

    test('weekKey is stable within an ISO week and changes at the Monday', () {
      final monday = retentionWeekKey(DateTime(2026, 8, 31));
      final sunday = retentionWeekKey(DateTime(2026, 9, 6));
      final nextMonday = retentionWeekKey(DateTime(2026, 9, 7));
      expect(monday, sunday);
      expect(monday, isNot(nextMonday));
    });
  });

  group('markCompleted', () {
    late ProviderContainer container;
    late RetentionStore store;

    setUp(() async {
      container = ProviderContainer();
      store = container.read(retentionStoreProvider.notifier);
      await store.loaded;
    });
    tearDown(() => container.dispose());

    test('is idempotent per day and advances the streak on consecutive days',
        () async {
      await store.markCompleted(now: DateTime(2026, 9, 1, 8));
      await store.markCompleted(now: DateTime(2026, 9, 1, 21)); // same day
      expect(container.read(retentionStoreProvider).localStreak, 1);

      await store.markCompleted(now: DateTime(2026, 9, 2, 8));
      expect(container.read(retentionStoreProvider).localStreak, 2);

      // A gap resets to 1.
      await store.markCompleted(now: DateTime(2026, 9, 5, 8));
      expect(container.read(retentionStoreProvider).localStreak, 1);
    });

    test('a clock rewind never rewrites the last day or decrements', () async {
      await store.markCompleted(now: DateTime(2026, 9, 10, 8));
      final streakAfter = container.read(retentionStoreProvider).localStreak;

      await store.markCompleted(now: DateTime(2026, 9, 8, 8)); // rewind
      final state = container.read(retentionStoreProvider);
      expect(state.lastCompletionDay, '2026-09-10');
      expect(state.localStreak, streakAfter);
      // The earlier day still lands in its own week bucket.
      expect(store.completionsInWeek(retentionWeekKey(DateTime(2026, 9, 8))),
          greaterThan(0));
    });

    test('completionsThisWeek counts distinct days, capped to 8 weeks',
        () async {
      for (var w = 0; w < 12; w++) {
        await store.markCompleted(now: DateTime(2026, 1, 5).add(Duration(days: w * 7)));
      }
      expect(container.read(retentionStoreProvider).completionsByWeek.length,
          lessThanOrEqualTo(8));
    });
  });

  group('server reconcile + cap ledger', () {
    late ProviderContainer container;
    late RetentionStore store;

    setUp(() async {
      container = ProviderContainer();
      store = container.read(retentionStoreProvider.notifier);
      await store.loaded;
    });
    tearDown(() => container.dispose());

    test('adopts the server streak and remembers it', () async {
      await store.reconcileServerStreak(9);
      expect(container.read(retentionStoreProvider).localStreak, 9);
      expect(container.read(retentionStoreProvider).serverStreakSeen, 9);
    });

    test('recordNotificationSent flips the per-day capped flag', () async {
      final now = DateTime(2026, 9, 4, 9);
      expect(store.cappedSentToday, isFalse);
      await store.recordNotificationSent(NotifType.studyReminder, now: now);
      // cappedSentToday reads "today" — align by re-recording for the real today.
      await store.recordNotificationSent(NotifType.studyReminder);
      expect(store.cappedSentToday, isTrue);
      expect(store.sentTypeToday(NotifType.dailyVerse), isFalse);
    });

    test('milestone dedupe', () async {
      expect(store.hasMilestone('streak-7'), isFalse);
      await store.markMilestone('streak-7');
      await store.markMilestone('streak-7');
      expect(store.hasMilestone('streak-7'), isTrue);
      expect(
        container.read(retentionStoreProvider).milestonesReached.length,
        1,
      );
    });
  });
}
