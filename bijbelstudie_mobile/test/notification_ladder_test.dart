import 'package:flutter_test/flutter_test.dart';

import 'package:bijbelstudie_mobile/core/notifications/notification_scheduler.dart';
import 'package:bijbelstudie_mobile/core/notifications/notification_service.dart';
import 'package:bijbelstudie_mobile/features/studies/data/enrollment_models.dart';

/// Phase 2 ladder guardrails (`RETENTION_PLAN.md` §4.4, §4.5): the ≤ 1 capped
/// notification/day cap, the milestone/verse exemptions, quiet-hours never
/// scheduling inside the window, and the week-goal "days left" maths the
/// at-risk trigger leans on.
void main() {
  RenderedVariant v() => const RenderedVariant(variantId: 'x', title: 't', body: 'b');
  Candidate c(NotifType type, DateTime when) =>
      Candidate(type: type, when: when, deepLink: '/x', variant: v());

  group('frequency cap', () {
    final now = DateTime(2026, 9, 4, 9);

    test('at most one capped notification survives per calendar day', () {
      final kept = applyLadder(
        [
          c(NotifType.dormant, DateTime(2026, 9, 4, 10)),
          c(NotifType.studyReminder, DateTime(2026, 9, 4, 19)),
          c(NotifType.lessonHalfway, DateTime(2026, 9, 4, 11)),
          c(NotifType.streakLost, DateTime(2026, 9, 4, 9, 30)),
        ],
        cappedSentToday: false,
        now: now,
      );
      expect(kept.where((x) => x.type.isCapped), hasLength(1));
      expect(kept.single.type, NotifType.streakLost);
    });

    test('milestone and dailyVerse never count against the cap', () {
      expect(NotifType.milestone.isCapped, isFalse);
      expect(NotifType.dailyVerse.isCapped, isFalse);
      final kept = applyLadder(
        [
          c(NotifType.milestone, DateTime(2026, 9, 4, 12)),
          c(NotifType.dailyVerse, DateTime(2026, 9, 4, 7)),
          c(NotifType.studyReminder, DateTime(2026, 9, 4, 19)),
        ],
        cappedSentToday: true, // capped types blocked today
        now: now,
      );
      expect(kept.map((x) => x.type),
          containsAll([NotifType.milestone, NotifType.dailyVerse]));
      expect(kept.where((x) => x.type.isCapped), isEmpty);
    });

    test('separate days each keep their own single capped slot', () {
      final kept = applyLadder(
        [
          c(NotifType.studyReminder, DateTime(2026, 9, 5, 8)),
          c(NotifType.streakAtRisk, DateTime(2026, 9, 5, 20)),
          c(NotifType.studyReminder, DateTime(2026, 9, 6, 8)),
        ],
        cappedSentToday: false,
        now: now,
      );
      expect(kept, hasLength(2));
    });
  });

  group('quiet hours', () {
    test('the default window wraps midnight', () {
      const q = QuietHours.defaults; // 21:30 -> 07:30
      expect(q.contains(22 * 60), isTrue);
      expect(q.contains(3 * 60), isTrue);
      expect(q.contains(7 * 60), isTrue);
      expect(q.contains(8 * 60), isFalse);
      expect(q.contains(12 * 60), isFalse);
    });

    test('a non-wrapping window', () {
      const q = QuietHours(startMinutes: 1 * 60, endMinutes: 6 * 60);
      expect(q.contains(3 * 60), isTrue);
      expect(q.contains(23 * 60), isFalse);
    });
  });

  group('week-goal maths', () {
    test('cadenceDaysLeftThisWeek counts today through Sunday', () {
      final c3 = cadenceFrom(rhythm: StudyRhythm.threePerWeek); // Mon/Wed/Fri
      // 2026-09-09 is a Wednesday: Wed + Fri remain this week.
      expect(c3.cadenceDaysLeftThisWeek(DateTime(2026, 9, 9)), 2);
      // Saturday 2026-09-12: nothing left.
      expect(c3.cadenceDaysLeftThisWeek(DateTime(2026, 9, 12)), 0);
    });
  });
}
