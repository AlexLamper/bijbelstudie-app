import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/notifications/notification_copy.dart';
import 'package:bijbelstudie_mobile/core/notifications/notification_scheduler.dart';
import 'package:bijbelstudie_mobile/core/notifications/notification_service.dart';
import 'package:bijbelstudie_mobile/features/studies/data/enrollment_models.dart';
import 'package:bijbelstudie_mobile/features/studies/data/study_plan_store.dart';

/// The scheduler is a pure function of cached state; these cover the parts that
/// decide *whether* and *when* — cadence resolution and the priority/cap ladder
/// (`RETENTION_PLAN.md` §2, §4.4). The platform-channel write path is not
/// exercised here.
void main() {
  RenderedVariant variant() =>
      const RenderedVariant(variantId: 'x', title: 't', body: 'b');

  Candidate candidate(NotifType type, DateTime when) => Candidate(
        type: type,
        when: when,
        deepLink: '/dashboard',
        variant: variant(),
      );

  group('cadenceFrom', () {
    test('server rhythm wins and maps to the right model', () {
      expect(cadenceFrom(rhythm: StudyRhythm.daily).model,
          RetentionModel.dailyStreak);
      expect(cadenceFrom(rhythm: StudyRhythm.threePerWeek).model,
          RetentionModel.weekGoal);
      expect(cadenceFrom(rhythm: StudyRhythm.threePerWeek).weekGoalTarget, 3);
      expect(cadenceFrom(rhythm: StudyRhythm.free).model, RetentionModel.none);
      expect(cadenceFrom(rhythm: StudyRhythm.free).remind, isFalse);
    });

    test('ownDays derives target and weekdays from reminderDays (0=Sun)', () {
      final c = cadenceFrom(
        rhythm: StudyRhythm.ownDays,
        reminderDays: const [0, 2, 4], // Sun, Tue, Thu
      );
      expect(c.model, RetentionModel.weekGoal);
      expect(c.weekGoalTarget, 3);
      expect(c.fixedWeekdays, {7, 2, 4});
    });

    test('local cadence is the offline fallback; ownPace schedules nothing', () {
      expect(cadenceFrom(localCadence: StudyCadence.daily).model,
          RetentionModel.dailyStreak);
      expect(cadenceFrom(localCadence: StudyCadence.ownPace).remind, isFalse);
      expect(cadenceFrom(localCadence: StudyCadence.threePerWeek).model,
          RetentionModel.weekGoal);
    });
  });

  group('CadenceInfo.isCadenceDay', () {
    test('3x/week is silent on off days', () {
      final c = cadenceFrom(rhythm: StudyRhythm.threePerWeek);
      // 2026-09-07 is a Monday, 08 Tue, 09 Wed.
      expect(c.isCadenceDay(DateTime(2026, 9, 7)), isTrue); // Mon
      expect(c.isCadenceDay(DateTime(2026, 9, 8)), isFalse); // Tue
      expect(c.isCadenceDay(DateTime(2026, 9, 9)), isTrue); // Wed
    });

    test('everyOtherDay counts from the anchor', () {
      final c = cadenceFrom(
        localCadence: StudyCadence.everyOtherDay,
        startedAt: DateTime(2026, 9, 1),
      );
      expect(c.isCadenceDay(DateTime(2026, 9, 1)), isTrue);
      expect(c.isCadenceDay(DateTime(2026, 9, 2)), isFalse);
      expect(c.isCadenceDay(DateTime(2026, 9, 3)), isTrue);
    });

    test('free never has a cadence day', () {
      final c = cadenceFrom(rhythm: StudyRhythm.free);
      expect(c.isCadenceDay(DateTime(2026, 9, 9)), isFalse);
    });
  });

  group('applyLadder', () {
    final today = DateTime(2026, 9, 4, 12);

    test('keeps only the highest-priority capped candidate per day', () {
      final kept = applyLadder(
        [
          candidate(NotifType.studyReminder, DateTime(2026, 9, 4, 20)),
          candidate(NotifType.streakAtRisk, DateTime(2026, 9, 4, 20, 30)),
          candidate(NotifType.dormant, DateTime(2026, 9, 4, 10)),
        ],
        cappedSentToday: false,
        now: today,
      );
      expect(kept, hasLength(1));
      expect(kept.single.type, NotifType.streakAtRisk); // beats reminder + dormant
    });

    test('dailyVerse is exempt from the cap', () {
      final kept = applyLadder(
        [
          candidate(NotifType.studyReminder, DateTime(2026, 9, 4, 20)),
          candidate(NotifType.streakAtRisk, DateTime(2026, 9, 4, 20, 30)),
          candidate(NotifType.dailyVerse, DateTime(2026, 9, 4, 7, 30)),
        ],
        cappedSentToday: false,
        now: today,
      );
      expect(kept.where((c) => c.type == NotifType.dailyVerse), hasLength(1));
      expect(kept.where((c) => c.type.isCapped), hasLength(1));
    });

    test('a capped type already sent today suppresses the rest for today', () {
      final kept = applyLadder(
        [
          candidate(NotifType.streakAtRisk, DateTime(2026, 9, 4, 20, 30)),
          candidate(NotifType.studyReminder, DateTime(2026, 9, 6, 8)), // future day
        ],
        cappedSentToday: true,
        now: today,
      );
      expect(kept.where((c) => c.type == NotifType.streakAtRisk), isEmpty);
      // A different calendar day is still allowed one.
      expect(kept.where((c) => c.type == NotifType.studyReminder), hasLength(1));
    });

    test('priority order matches the plan', () {
      expect(NotifType.milestone.priority, greaterThan(NotifType.streakLost.priority));
      expect(NotifType.streakLost.priority, greaterThan(NotifType.lessonHalfway.priority));
      expect(NotifType.lessonHalfway.priority, greaterThan(NotifType.streakAtRisk.priority));
      expect(NotifType.streakAtRisk.priority, greaterThan(NotifType.studyReminder.priority));
      expect(NotifType.studyReminder.priority, greaterThan(NotifType.weeklyGoal.priority));
      expect(NotifType.weeklyGoal.priority, greaterThan(NotifType.dormant.priority));
    });
  });

  group('copy rendering', () {
    test('a missing token falls back to a token-free line in the same pool', () {
      final rendered = renderVariant(
        NotifType.studyReminder,
        notificationCopy[NotifType.studyReminder]!
            .firstWhere((t) => t.body.contains('{study}')),
        const {'study': null, 'lesson': null},
      );
      expect(rendered.title.contains('{'), isFalse);
      expect(rendered.body.contains('{'), isFalse);
    });

    test('tokens are interpolated when present', () {
      final rendered = pickVariant(
        NotifType.streakAtRisk,
        rotation: 0,
        tokens: const {'streak': '5'},
      );
      expect(rendered.title.contains('{'), isFalse);
    });

    test('weeklyGoal met vs behind pull from different halves of the pool', () {
      final met = pickVariant(NotifType.weeklyGoal,
          rotation: 0, weeklyGoalMet: true, tokens: const {'target': '3', 'done': '3'});
      final behind = pickVariant(NotifType.weeklyGoal,
          rotation: 0, tokens: const {'target': '3', 'done': '1', 'n': '2'});
      expect(met.title, isNot(behind.title));
    });
  });

  group('NotificationScheduler.milestoneVariant', () {
    // Regression for the bug where a real 14- or 30-day streak celebrated
    // with the "100 dagen" copy: the old code picked a pool slot with
    // `n % pool.length` (pool.length == 8), and 14 % 8 == 30 % 8 == 6, the
    // index of `ms7` ("100 dagen"). Each streak length must render its own,
    // distinct copy - never another length's hard-coded text.
    test('each dedicated streak length gets its own copy, not another one\'s', () {
      const tokens = {'streak': '0', 'name': 'Alex'};
      final byLength = {
        for (final n in [7, 14, 30, 100])
          n: NotificationScheduler.milestoneVariant('streak-$n', tokens: tokens),
      };
      expect(byLength[7]!.title, 'Een week volgehouden');
      expect(byLength[14]!.title, '14 dagen');
      expect(byLength[30]!.title, '30 dagen');
      expect(byLength[100]!.title, '100 dagen');

      // No two of these dedicated milestones ever collide on the same copy -
      // which is exactly how 14 and 30 both used to end up saying "100 dagen".
      final titles = byLength.values.map((v) => v.title).toSet();
      expect(titles, hasLength(4));
    });

    test('a threshold with no dedicated line uses the generic count', () {
      final variant = NotificationScheduler.milestoneVariant(
        'streak-3',
        tokens: const {'streak': '3', 'name': 'Alex'},
      );
      expect(variant.title, '3 dagen op rij');

      final fifty = NotificationScheduler.milestoneVariant(
        'streak-50',
        tokens: const {'streak': '50', 'name': 'Alex'},
      );
      expect(fifty.title, '50 dagen op rij');
    });

    test('a badge milestone gets the generic new-badge line, never streak copy', () {
      final variant = NotificationScheduler.milestoneVariant(
        'badge-firstlesson',
        tokens: const {'streak': '0', 'name': 'Alex'},
      );
      expect(variant.title, 'Nieuw zegel verdiend');
    });

    test('never leaves an unresolved {token} in what is shown', () {
      for (final id in ['streak-3', 'streak-7', 'streak-14', 'streak-30',
          'streak-50', 'streak-100', 'badge-completed1']) {
        final variant = NotificationScheduler.milestoneVariant(
          id,
          tokens: const {'streak': '30', 'name': 'Alex'},
        );
        expect(variant.title.contains('{'), isFalse, reason: id);
        expect(variant.body.contains('{'), isFalse, reason: id);
      }
    });
  });
}
