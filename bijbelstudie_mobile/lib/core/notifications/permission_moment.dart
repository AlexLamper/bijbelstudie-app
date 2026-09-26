import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/levensboom/domain/tree_state.dart';
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

  /// The reader picked "Elke dag om …" when starting Bijbel in een jaar: an
  /// explicit request for a reminder, so it is offered even when an earlier
  /// moment was declined (the OS decides whether its own dialog still shows).
  planReminder,
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
      case PermissionMoment.planReminder:
        return 'Je leesplan staat klaar.';
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
    case PermissionMoment.planReminder:
      return true;
    case PermissionMoment.chaptersRead:
      return state.completionsEver >= 3;
    case PermissionMoment.firstStreak:
      return state.localStreak >= 2;
  }
}

/// Two moments landing together must not stack two sheets.
bool _sheetOpen = false;

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
  // Everything the rest needs is read before the first await: the widget
  // behind [ref] can be gone by the time the sheet or the OS dialog closes.
  final store = ref.read(retentionStoreProvider.notifier);
  final service = ref.read(notificationServiceProvider);
  final prefsCtl = ref.read(notificationPrefsProvider.notifier);
  final rescheduler = ref.read(notificationReschedulerProvider);
  await store.loaded;
  if (!context.mounted) return false;
  final state = ref.read(retentionStoreProvider);
  if (state.permissionAskedAfterFirstLesson &&
      moment != PermissionMoment.planReminder) {
    return false;
  }

  if (!permissionMomentEarned(moment, state)) return false;

  if (await service.hasPermission()) {
    // Android 12 and below grant at install, so there is nothing to ask - but
    // the reminders still have to be switched on (unless the reader turned
    // them off themselves).
    await prefsCtl.enableIfUnset();
    rescheduler.requestReschedule();
    return false;
  }
  if (!context.mounted || _sheetOpen) return false;

  _sheetOpen = true;
  final bool? wants;
  try {
    wants = await _showSheet(context, ref, moment);
  } finally {
    _sheetOpen = false;
  }
  // Spent only once the sheet was really on screen: a context that went away
  // before it could open must not burn the one ask.
  await store.markPermissionAsked();
  if (wants != true) return false;

  final granted = await service.requestPermission();
  if (granted) {
    await prefsCtl.setMasterEnabled(true);
    await prefsCtl.setStudyReminder(enabled: true);
  }
  await prefsCtl.setPendingPermissionRequest(false);
  // Captured above; `ref` itself may belong to a disposed widget by now.
  rescheduler.requestReschedule();
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
Future<bool?> _showSheet(
  BuildContext context,
  WidgetRef ref,
  PermissionMoment moment,
) {
  final tree = ref.read(treeStateProvider).value;
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    // Without this the sheet is capped at half the screen and the buttons fall
    // off the bottom on a small phone or at a large text scale.
    isScrollControlled: true,
    builder: (sheetContext) => NotificationPermissionSheet(
      moment: moment,
      tree: tree != null && !tree.disabled ? tree : null,
    ),
  );
}

/// The body of the pre-permission sheet, split out so it can be rendered at a
/// small viewport in a widget test.
///
/// It is built to never clip: the copy scrolls, the two buttons stay pinned
/// under it, and the whole thing is held inside the visible part of the screen
/// (`SafeArea` for the home indicator, `viewInsets` for anything that opens on
/// top of it).
class NotificationPermissionSheet extends StatelessWidget {
  const NotificationPermissionSheet({
    super.key,
    required this.moment,
    this.tree,
  });

  final PermissionMoment moment;

  /// The reader's tree, or null when there is none to show.
  final TreeState? tree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final tree = this.tree;

    // The drag handle and the sheet's own rounding eat a little of the screen,
    // so the content asks for at most ~88% of it and scrolls inside that.
    final maxHeight = media.size.height * 0.88;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + media.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // The tree is in the sheet because the tree is what
                          // the notification will show: the ask and the reward
                          // look alike.
                          if (tree != null) ...[
                            MiniTree(
                              tree: tree,
                              badge: '${tree.level}',
                              semanticsLabel:
                                  'Je Levensboom, niveau ${tree.level}',
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
                        "We sturen je hooguit één herinnering per dag, op het "
                        "moment dat jij kiest - nooit 's avonds laat, nooit "
                        "als je die dag al bezig bent geweest. Je zet het met "
                        "één tik weer uit.",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Pinned below the scroll view, so "Herinner me" is reachable
              // however tall the copy renders.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text(
                        'Nu niet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text(
                        'Herinner me',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
