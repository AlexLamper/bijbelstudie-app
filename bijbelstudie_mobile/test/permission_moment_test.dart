import 'package:bijbelstudie_mobile/core/notifications/permission_moment.dart';
import 'package:bijbelstudie_mobile/core/notifications/retention_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ask is never spent in onboarding and never on a first launch: it is
/// earned (`AVATAR_NOTIFICATIONS_PLAN.md` §7). These assert the two moments a
/// screen may offer blindly, on every chapter read, without asking too early.
void main() {
  group('permissionMomentEarned', () {
    test('a first chapter is not a reason to ask', () {
      const state = RetentionState(completionsEver: 1, localStreak: 1);
      expect(permissionMomentEarned(PermissionMoment.chaptersRead, state), isFalse);
      expect(permissionMomentEarned(PermissionMoment.firstStreak, state), isFalse);
    });

    test('a third chapter is', () {
      const state = RetentionState(completionsEver: 3, localStreak: 1);
      expect(permissionMomentEarned(PermissionMoment.chaptersRead, state), isTrue);
    });

    test('so is coming back a second day', () {
      const state = RetentionState(completionsEver: 2, localStreak: 2);
      expect(permissionMomentEarned(PermissionMoment.firstStreak, state), isTrue);
    });

    test('the moments the caller owns are always allowed through', () {
      const fresh = RetentionState();
      expect(permissionMomentEarned(PermissionMoment.firstLesson, fresh), isTrue);
      expect(permissionMomentEarned(PermissionMoment.firstMilestone, fresh), isTrue);
    });
  });

  group('lead copy', () {
    test('every moment says why we are asking now, in Dutch', () {
      for (final moment in PermissionMoment.values) {
        expect(moment.lead, isNotEmpty);
        expect(moment.lead.endsWith('.'), isTrue, reason: '${moment.name}: $moment');
      }
      expect(PermissionMoment.chaptersRead.lead, contains('derde hoofdstuk'));
      expect(PermissionMoment.firstStreak.lead, contains('Twee dagen'));
    });
  });
}
