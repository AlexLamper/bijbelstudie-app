import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_policy.dart';
import 'retention_store.dart' show parseSentTag;

/// What the reader did with the reminders: taps, opens, and the outcome of
/// every reminder that fired. Feeds [ReminderPolicy].
///
/// Static and on SharedPreferences rather than a provider, because a tap can
/// arrive before Riverpod has anything running (a cold start from the
/// notification) and the tap handlers in notification_service.dart have no
/// `Ref`. Everything here is best effort and never throws.
class ReminderEngagement {
  ReminderEngagement._();

  static const _taps = 'engage.taps';
  static const _opens = 'engage.opens';
  static const _outcomes = 'engage.outcomes';
  static const _cursor = 'engage.cursorMs';

  static const _maxTaps = 30;
  static const _maxOpens = 40;

  /// An open this soon after the last one is the same visit.
  static const _openThrottle = Duration(minutes: 10);

  /// A tap on a notification of [typeId] (or its "Later vandaag" action).
  static Future<void> recordTap(String? typeId, {DateTime? at}) async {
    if (typeId == null || typeId.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = _decodeList(p.getString(_taps));
      list.add([typeId, (at ?? DateTime.now()).millisecondsSinceEpoch]);
      while (list.length > _maxTaps) {
        list.removeAt(0);
      }
      await p.setString(_taps, jsonEncode(list));
    } catch (_) {}
  }

  /// The app came to the foreground.
  static Future<void> recordOpen({DateTime? at}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
      final opens = _decodeInts(p.getString(_opens));
      if (opens.isNotEmpty && ms - opens.last < _openThrottle.inMilliseconds) return;
      opens.add(ms);
      while (opens.length > _maxOpens) {
        opens.removeAt(0);
      }
      await p.setString(_opens, jsonEncode(opens));
    } catch (_) {}
  }

  /// Judges every reminder in [sentLog] that fired since the last call, adds
  /// the outcomes to the record and returns the policy that follows, plus what
  /// to report: taps since the last call (`push_opened`) and newly ignored
  /// reminders (`push_ignored`). `pausedAfter` is set when this open ends a
  /// run of three or more ignored reminders (`reminders_paused`).
  static Future<EngagementUpdate> evaluate({
    required Map<String, List<String>> sentLog,
    required DateTime now,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      final nowMs = now.millisecondsSinceEpoch;
      final storedCursor = p.getInt(_cursor);
      if (storedCursor == null) {
        // First run on this install (or after an upgrade): nothing was
        // watched before now, so nothing before now can be judged.
        await p.setInt(_cursor, nowMs);
        return const EngagementUpdate(policy: ReminderPolicy.normal);
      }
      final cursor = storedCursor;
      final taps = [
        for (final t in _decodeList(p.getString(_taps)))
          if (t.length == 2 && t[0] is String && t[1] is num)
            ReminderTap(t[0] as String, (t[1] as num).toInt()),
      ];
      final opens = _decodeInts(p.getString(_opens));

      final fired = <FiredReminder>[];
      for (final tags in sentLog.values) {
        for (final tag in tags) {
          final parsed = parseSentTag(tag);
          final at = parsed.firesAtMs;
          if (at == null || at <= cursor || at > nowMs) continue;
          if (!isReminderTypeId(parsed.typeId)) continue;
          fired.add(FiredReminder(parsed.typeId, at));
        }
      }
      final judged = judgeFired(fired: fired, taps: taps, opensMs: opens);

      final outcomes = _decodeOutcomes(p.getString(_outcomes))
        ..addAll(judged.map((j) => j.outcome));
      while (outcomes.length > kOutcomeMemory) {
        outcomes.removeAt(0);
      }
      final policy = ReminderPolicy.from(outcomes);

      final tappedSince = [
        for (final t in taps)
          if (t.atMs > cursor && t.atMs <= nowMs && isReminderTypeId(t.typeId)) t.typeId,
      ];
      final ignored = [
        for (final j in judged)
          if (j.outcome == ReminderOutcome.ignored) j.reminder.typeId,
      ];

      // This open ends a run of at least three ignored reminders: the phone
      // had gone quiet (or nearly), and the reader came back anyway.
      final pausedAfter = judged.isNotEmpty &&
              judged.every((j) => j.outcome == ReminderOutcome.ignored) &&
              policy.ignoredInARow >= 3
          ? policy.ignoredInARow
          : null;

      await p.setString(
          _outcomes, outcomes.map((o) => o == ReminderOutcome.answered ? 'a' : 'i').join());
      await p.setInt(_cursor, nowMs);
      return EngagementUpdate(
        policy: policy,
        tapped: tappedSince,
        ignored: ignored,
        pausedAfter: pausedAfter,
      );
    } catch (_) {
      return const EngagementUpdate(policy: ReminderPolicy.normal);
    }
  }

  /// Forgets everything (sign-out: the next reader starts fresh).
  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in [_taps, _opens, _outcomes, _cursor]) {
        await p.remove(k);
      }
    } catch (_) {}
  }

  static List<List<dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final e in jsonDecode(raw) as List) if (e is List) e];
    } catch (_) {
      return [];
    }
  }

  static List<int> _decodeInts(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final e in jsonDecode(raw) as List) if (e is num) e.toInt()];
    } catch (_) {
      return [];
    }
  }

  static List<ReminderOutcome> _decodeOutcomes(String? raw) => [
        for (final c in (raw ?? '').split(''))
          if (c == 'a') ReminderOutcome.answered else if (c == 'i') ReminderOutcome.ignored,
      ];
}

class EngagementUpdate {
  const EngagementUpdate({
    required this.policy,
    this.tapped = const [],
    this.ignored = const [],
    this.pausedAfter,
  });

  final ReminderPolicy policy;
  final List<String> tapped;
  final List<String> ignored;
  final int? pausedAfter;
}
