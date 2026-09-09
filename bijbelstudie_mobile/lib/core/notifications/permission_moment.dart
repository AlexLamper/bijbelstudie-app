import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/levensboom/present/levensboom_providers.dart';
import '../../features/levensboom/present/mini_tree.dart';
import '../../features/settings/data/notification_prefs.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';
import 'retention_store.dart';

/// The earned moments at which the app may ask for notification permission
/// (`AVATAR_NOTIFICATIONS_PLAN.md` §7).
///
/// Never on first launch and never in the onboarding wizard: the reader taps
/// "niet toestaan" there and the one chance is gone. The ask is offered after
/// something has actually gone well, and only once - whichever moment lands
/// first wins, the rest become no-ops.
enum PermissionMoment {
  /// The first finished lesson. The original moment (`RETENTION_PLAN.md` §4.6).
  firstLesson,

  /// Three chapters read. Catches the reader who never starts a study.
  chaptersRead,

  /// Two days in a row - the first streak worth protecting.
  firstStreak,

  /// A first badge, or a finished study.
  firstMilestone,
}

extension PermissionMomentCopy on PermissionMoment {
  /// The one line that says why we are asking *now*. The rest of the sheet is
  /// the same every time.
  String get lead {
    switch (this) {
      case PermissionMoment.firstLesson:
        return 'Je eerste les zit erop.';
      case PermissionMoment.chaptersRead:
        return 'Je hebt net je derde hoofdstuk gelezen.';
      case PermissionMoment.firstStreak:
        return 'Twee dagen op rij - mooi.';
      case PermissionMoment.firstMilestone:
        return 'Je hebt iets bereikt.';
    }
  }
}

/// Whether [moment] has actually happened yet, from what the store knows.
///
/// [PermissionMoment.firstLesson] and [PermissionMoment.firstMilestone] are the
/// caller's to judge: only the lesson screen knows a lesson just ended, and only
/// the scheduler knows a milestone is new. The two counted moments are checked
/// here, so a screen can offer them on every read without thinking about it.
bool permissionMomentEarned(PermissionMoment moment, RetentionState state) {
  switch (moment) {
    case PermissionMoment.firstLesson:
    case PermissionMoment.firstMilestone:
      return true;
    case PermissionMoment.chaptersRead:
      return state.completionsEver >= 3;
    case PermissionMoment.firstStreak:
      return state.localStreak >= 2;
  }
}

/// Offers the pre-permission sheet if [moment] has genuinely been earned and
/// the ask has not been spent yet.
///
/// Returns true when the OS dialog was shown and permission was granted.
/// Everything else - already asked, already granted, notifications switched off
/// by hand - returns false without showing anything.
Future<bool> maybeAskForNotifications(
  BuildContext context,
  WidgetRef ref,
  PermissionMoment moment,
) async {
  final store = ref.read(retentionStoreProvider.notifier);
  await store.loaded;
  final state = ref.read(retentionStoreProvider);
  if (state.permissionAskedAfterFirstLesson) return false;

  if (!permissionMomentEarned(moment, state)) return false;

  final service = ref.read(notificationServiceProvider);
  if (await service.hasPermission()) return false;
  if (!context.mounted) return false;

  await store.markPermissionAsked();
  if (!context.mounted) return false;

  final wants = await _showSheet(context, ref, moment);
  if (wants != true) return false;

  final granted = await service.requestPermission();
  if (granted) {
    final prefs = ref.read(notificationPrefsProvider.notifier);
    await prefs.setMasterEnabled(true);
    await prefs.setStudyReminder(enabled: true);
  }
  await ref
      .read(notificationPrefsProvider.notifier)
      .setPendingPermissionRequest(false);
  ref.invalidate(notificationRecomputeProvider);
  return granted;
}

/// The reading side of §7: offered after a chapter is claimed as read, once the
/// reader has either come back a second day or read a third chapter.
///
/// [PermissionMoment.firstStreak] is tried first - "twee dagen op rij" is a
/// better reason than a count - and both are no-ops until they are earned.
Future<void> maybeAskAfterReading(BuildContext context, WidgetRef ref) async {
  if (await maybeAskForNotifications(context, ref, PermissionMoment.firstStreak)) {
    return;
  }
  if (!context.mounted) return;
  await maybeAskForNotifications(context, ref, PermissionMoment.chaptersRead);
}

/// The Dutch pre-permission bottom sheet (`RETENTION_PLAN.md` §4.6, extended by
/// §7). Shown in-app before the OS dialog; "Nu niet" only sets the guard, it
/// never re-prompts - Settings is the way back.
Future<bool?> _showSheet(
  BuildContext context,
  WidgetRef ref,
  PermissionMoment moment,
) {
  final tree = ref.read(treeStateProvider).value;
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The tree is in the sheet because the tree is what the
                // notification will show: the ask and the reward look alike.
                if (tree != null && !tree.disabled) ...[
                  MiniTree(
                    tree: tree,
                    badge: '${tree.level}',
                    semanticsLabel: 'Je Levensboom, niveau ${tree.level}',
                    size: 56,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        moment.lead,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Wil je een rustig zetje op je studiedag?',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "We sturen je hooguit één herinnering per dag, op het moment dat "
              "jij kiest - nooit 's avonds laat, nooit als je die dag al bezig "
              "bent geweest. Je zet het met één tik weer uit.",
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Nu niet'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('Herinner me'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
