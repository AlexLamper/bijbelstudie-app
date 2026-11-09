import 'notification_service.dart' show NotifType, NotifTypeX;

/// How many reminders a reader gets, decided by how they answered the last
/// ones. Pure: the engagement store (reminder_engagement.dart) feeds it, the
/// scheduler applies it, and test/reminder_policy_test.dart pins the numbers.
///
/// THE RULES (owner's choice, Nov 2026: "at most 1-2 a day; fewer to people
/// who ignore them; stop after several ignored in a row until they come back"):
///
/// - A reminder is *answered* when it was tapped, or when the app was opened
///   within [answerWindow] after it fired. Anything else that fired is
///   *ignored*.
/// - Daily cap: [kMaxNotificationsPerDay] (2), or 1 for a reader who leaves
///   them lying - fewer than 30 % of the last ten answered (with at least six
///   to go on), or the last three ignored in a row.
/// - Run budget: the batch armed at an open holds at most [runBudget]
///   reminders (5, or 3 for that same reader), counted from now. The app can
///   only re-arm while it is open, so this is what "stop after several ignored
///   in a row" means on a phone: after that many unanswered reminders the
///   phone goes quiet, and the next open - coming back - arms a new batch.
/// - Taper: inside the budget, from the third calendar day on, at most one a
///   day. A reader away for a while hears from us less, not the same.
///
/// Celebrations shown while the app is open (a milestone, the weekly goal
/// met) are not reminders and count for none of this.

/// What one fired reminder came to.
enum ReminderOutcome { answered, ignored }

/// The types that count as a reminder (`push_opened` / `push_ignored`).
const Set<NotifType> kReminderTypes = {
  NotifType.morning,
  NotifType.evening,
  NotifType.streakAtRisk,
  NotifType.streakLost,
  NotifType.lessonHalfway,
  NotifType.weeklyGoal,
  NotifType.dormant,
  NotifType.treeWilting,
};

bool isReminderTypeId(String id) => kReminderTypes.any((t) => t.id == id);

/// A tap or an open this long after a reminder fired answers it.
const Duration answerWindow = Duration(hours: 3);

/// Outcomes remembered; older ones fall off.
const int kOutcomeMemory = 20;

class ReminderPolicy {
  const ReminderPolicy({
    required this.dailyCap,
    required this.runBudget,
    required this.lowEngagement,
    required this.ignoredInARow,
  });

  /// The engaged reader's policy, and what a reader with no history gets.
  static const normal = ReminderPolicy(
    dailyCap: 2,
    runBudget: 5,
    lowEngagement: false,
    ignoredInARow: 0,
  );

  /// The most notifications on one calendar day.
  final int dailyCap;

  /// The most reminders armed until the next open.
  final int runBudget;

  /// The reader leaves most reminders lying.
  final bool lowEngagement;

  /// Trailing ignored outcomes.
  final int ignoredInARow;

  /// [outcomes] oldest first.
  factory ReminderPolicy.from(List<ReminderOutcome> outcomes) {
    var trailing = 0;
    for (var i = outcomes.length - 1; i >= 0; i--) {
      if (outcomes[i] != ReminderOutcome.ignored) break;
      trailing++;
    }
    final recent = outcomes.length > 10 ? outcomes.sublist(outcomes.length - 10) : outcomes;
    final answered = recent.where((o) => o == ReminderOutcome.answered).length;
    final rateLow = recent.length >= 6 && answered / recent.length < 0.3;
    final low = rateLow || trailing >= 3;
    return ReminderPolicy(
      dailyCap: low ? 1 : 2,
      runBudget: low ? 3 : 5,
      lowEngagement: low,
      ignoredInARow: trailing,
    );
  }

  @override
  String toString() =>
      'ReminderPolicy(cap $dailyCap, budget $runBudget, low $lowEngagement, ignored $ignoredInARow)';
}

/// Applies the run budget and the taper to an already capped, time-ordered
/// list. [counts] says which items are reminders (celebrations are kept and
/// count for nothing); [when] is when an item fires.
List<T> applyRunBudget<T>(
  List<T> items, {
  required ReminderPolicy policy,
  required DateTime now,
  required DateTime Function(T) when,
  required bool Function(T) counts,
}) {
  final sorted = [...items]..sort((a, b) => when(a).compareTo(when(b)));
  final today = DateTime(now.year, now.month, now.day);
  final perDay = <int, int>{};
  var used = 0;
  final out = <T>[];
  for (final item in sorted) {
    if (!counts(item)) {
      out.add(item);
      continue;
    }
    if (used >= policy.runBudget) continue;
    final t = when(item);
    final dayIndex = DateTime(t.year, t.month, t.day).difference(today).inDays;
    final cap = dayIndex >= 2 ? 1 : policy.dailyCap;
    final onDay = perDay[dayIndex] ?? 0;
    if (onDay >= cap) continue;
    perDay[dayIndex] = onDay + 1;
    used++;
    out.add(item);
  }
  return out;
}

/// One reminder that fired, from the scheduler's ledger.
class FiredReminder {
  const FiredReminder(this.typeId, this.firesAtMs);

  final String typeId;
  final int firesAtMs;
}

/// One tap on a reminder (or its "Later vandaag" action).
class ReminderTap {
  const ReminderTap(this.typeId, this.atMs);

  final String typeId;
  final int atMs;
}

/// What each of [fired] came to, given the taps and opens on record. [fired]
/// in any order; the result is in firing order.
List<({FiredReminder reminder, ReminderOutcome outcome})> judgeFired({
  required List<FiredReminder> fired,
  required List<ReminderTap> taps,
  required List<int> opensMs,
}) {
  final sorted = [...fired]..sort((a, b) => a.firesAtMs.compareTo(b.firesAtMs));
  final window = answerWindow.inMilliseconds;
  final tapWindow = const Duration(hours: 24).inMilliseconds;
  return [
    for (final r in sorted)
      (
        reminder: r,
        outcome: taps.any((t) =>
                    t.typeId == r.typeId &&
                    t.atMs >= r.firesAtMs &&
                    t.atMs <= r.firesAtMs + tapWindow) ||
                opensMs.any((o) => o >= r.firesAtMs && o <= r.firesAtMs + window)
            ? ReminderOutcome.answered
            : ReminderOutcome.ignored,
      ),
  ];
}
