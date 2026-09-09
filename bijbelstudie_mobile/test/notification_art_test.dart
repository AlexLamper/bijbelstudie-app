import 'package:bijbelstudie_mobile/core/notifications/notification_art.dart';
import 'package:bijbelstudie_mobile/core/notifications/notification_copy.dart';
import 'package:bijbelstudie_mobile/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The countdown burned into the picture and the countdown in the notification
/// body come from the same number (`AVATAR_NOTIFICATIONS_PLAN.md` §11): if they
/// ever disagree the reader is told two different deadlines at once.
void main() {
  group('hoursToMidnight', () {
    test('counts to the end of the day the streak actually belongs to', () {
      expect(NotificationArt.hoursToMidnight(DateTime(2026, 5, 4, 20, 30)), 3);
      expect(NotificationArt.hoursToMidnight(DateTime(2026, 5, 4, 21, 0)), 3);
      expect(NotificationArt.hoursToMidnight(DateTime(2026, 5, 4, 23, 30)), 0);
    });

    test('says nothing when the deadline is not yet worth a number', () {
      // Noon is twelve hours out: a countdown that early is pressure, not help.
      expect(NotificationArt.hoursToMidnight(DateTime(2026, 5, 4, 12, 0)), isNull);
      expect(NotificationArt.hoursToMidnight(DateTime(2026, 5, 4, 8, 0)), isNull);
    });

    test('survives the last minute of the day', () {
      expect(NotificationArt.hoursToMidnight(DateTime(2026, 5, 4, 23, 59)), 0);
    });

    test('crosses a DST boundary without going negative', () {
      // The Dutch clocks move on the last Sunday of March.
      final hours = NotificationArt.hoursToMidnight(DateTime(2026, 3, 29, 22, 0));
      expect(hours, isNotNull);
      expect(hours, greaterThanOrEqualTo(0));
    });
  });

  group('streakAtRisk copy', () {
    test('says the hours in words as well as in pixels', () {
      final variant = pickVariant(
        NotifType.streakAtRisk,
        rotation: 0,
        tokens: {'hours': '3', 'streak': '12'},
      );
      expect(variant.variantId, 'ar9');
      expect(variant.title, 'Nog 3 uur vandaag');
      expect(variant.body, contains('12 dagen'));
    });

    test('falls through to a line that needs no hours when they are missing', () {
      final variant = pickVariant(
        NotifType.streakAtRisk,
        rotation: 0,
        tokens: {'streak': '12'},
      );
      expect(variant.variantId, isNot('ar9'));
      expect(variant.variantId, isNot('ar10'));
      expect(variant.title, isNot(contains('{')));
      expect(variant.body, isNot(contains('{')));
    });
  });

  group('win-back copy', () {
    test('spends the reader’s name on the nudges that have earned it', () {
      final wilting = pickVariant(
        NotifType.treeWilting,
        rotation: 0,
        tokens: {'name': 'Ruth'},
      );
      expect(wilting.title, 'Ruth, je boom mist wat licht');

      final dormant = pickVariant(
        NotifType.dormant,
        rotation: 0,
        tokens: {'name': 'Ruth'},
      );
      expect(dormant.title, 'Ruth, je boom staat er nog');
    });

    test('never leaves a hole where the name should have been', () {
      final wilting = pickVariant(NotifType.treeWilting, rotation: 0, tokens: {});
      expect(wilting.title, isNot(contains('{')));
      expect(wilting.title, isNot(startsWith(',')));

      // A daily reminder must not carry the name at all (D12).
      for (var rotation = 0; rotation < 12; rotation++) {
        final reminder = pickVariant(
          NotifType.studyReminder,
          rotation: rotation,
          tokens: {'name': 'Ruth', 'study': 'Romeinen', 'lesson': '3'},
        );
        expect(reminder.title, isNot(contains('Ruth')));
        expect(reminder.body, isNot(contains('Ruth')));
      }
    });
  });
}
