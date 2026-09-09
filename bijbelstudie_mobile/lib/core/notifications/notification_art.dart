import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/data/daily_verse_store.dart';
import '../../features/levensboom/data/notification_canvas.dart';
import '../../features/levensboom/domain/tree_state.dart';
import '../../features/levensboom/domain/verse_scene.dart';
import '../../features/levensboom/present/levensboom_providers.dart';
import 'notification_service.dart';
import 'retention_store.dart';

/// Which picture each notification type carries
/// (`AVATAR_NOTIFICATIONS_PLAN.md` §4).
///
/// One instance per scheduler run. It renders lazily and memoises by art name,
/// so the fourteen `dailyVerse` one-shots of a single batch share one render,
/// and a type whose candidate loses the ladder costs nothing at all.
///
/// Every path is best-effort: over budget, no tree, a failed paint - all return
/// null, and a notification without a picture is still a notification.
class NotificationArt {
  NotificationArt._({
    required this.tree,
    required this.streak,
    required this.verse,
    required this.verseRef,
    required this.now,
    required this.budget,
  });

  /// Reads everything the pictures need from providers that are already warm.
  factory NotificationArt.of(
    Ref ref, {
    DateTime? now,
    Duration budget = const Duration(milliseconds: 900),
  }) =>
      NotificationArt._gather(
        tree: ref.exists(treeStateProvider) ? ref.read(treeStateProvider).value : null,
        verse: ref.read(dailyVerseStoreProvider).history.firstOrNull,
        streak: ref.read(retentionStoreProvider).localStreak,
        now: now,
        budget: budget,
      );

  /// The same, from a widget's ref - the milestone path runs from a screen.
  factory NotificationArt.ofWidget(
    WidgetRef ref, {
    DateTime? now,
    Duration budget = const Duration(milliseconds: 900),
  }) =>
      NotificationArt._gather(
        tree: ref.exists(treeStateProvider) ? ref.read(treeStateProvider).value : null,
        verse: ref.read(dailyVerseStoreProvider).history.firstOrNull,
        streak: ref.read(retentionStoreProvider).localStreak,
        now: now,
        budget: budget,
      );

  factory NotificationArt._gather({
    required TreeState? tree,
    required DailyVerseEntry? verse,
    required int streak,
    required DateTime? now,
    required Duration budget,
  }) {
    final at = now ?? DateTime.now();
    final latest = verse;
    return NotificationArt._(
      tree: tree,
      // `localStreak` *is* the server streak whenever the dashboard has been
      // seen: `RetentionStore.reconcileServerStreak` adopts the server value
      // wholesale. Between opens it carries on locally, which is exactly the
      // "server first, local as fallback" rule (D11) with no extra bookkeeping.
      streak: streak,
      verse: latest?.text,
      verseRef: latest?.reference,
      now: at,
      budget: budget,
    );
  }

  final TreeState? tree;
  final int streak;
  final String? verse;
  final String? verseRef;
  final DateTime now;
  final Duration budget;

  final Stopwatch _spent = Stopwatch()..start();
  final Map<String, TreeImageFiles?> _done = {};

  /// A streak of one is not a streak; drawing it teaches the reader the number
  /// is noise.
  int? get _chip => streak >= 2 ? streak : null;

  /// The picture for a candidate of [type] firing at [when], or null.
  Future<TreeImageFiles?> forCandidate(
    NotifType type,
    DateTime when, {
    bool celebrate = false,
  }) {
    if (type == NotifType.dailyVerse) return _verseArt(when);
    if (tree == null) return Future.value(null);
    switch (type) {
      case NotifType.streakAtRisk:
        return _treeArt(
          'tree-risk',
          // The loss frame: the tree already reading as thirsty is the nudge.
          healthOverride: 0.7,
          countdown: _countdownTo(when),
        );
      case NotifType.streakLost:
      case NotifType.dormant:
      case NotifType.treeWilting:
        return _treeArt('tree-wilting', healthOverride: 0.5);
      case NotifType.milestone:
        return _treeArt('tree-milestone', celebration: true, withLevel: true);
      case NotifType.weeklyGoal:
        return celebrate
            ? _treeArt('tree-milestone', celebration: true, withLevel: true)
            : _treeArt('tree-healthy', withLevel: true);
      case NotifType.studyReminder:
      case NotifType.lessonHalfway:
        return _treeArt('tree-healthy', withLevel: true);
      case NotifType.dailyVerse:
        return Future.value(null);
    }
  }

  Future<TreeImageFiles?> _treeArt(
    String name, {
    double? healthOverride,
    bool celebration = false,
    bool withLevel = false,
    String? countdown,
  }) =>
      _render(
        countdown == null ? name : '$name-${countdown.hashCode.toRadixString(16)}',
        () => NotifArtSpec.tree(
          tree: tree!,
          healthOverride: healthOverride,
          celebration: celebration,
          streak: _chip,
          countdown: countdown,
          level: withLevel ? tree!.level : null,
          levelFrac: withLevel ? tree!.progress : null,
        ),
      );

  /// The day's landscape. Only the verse that is actually known - today's - is
  /// burned in; a one-shot five days out carries the scene alone.
  Future<TreeImageFiles?> _verseArt(DateTime when) {
    final scene = verseSceneForDay(when);
    final sameDay = verseSceneKey(when) == verseSceneKey(now);
    return _render(
      'verse-${scene.key}',
      () => NotifArtSpec.verse(
        verse: scene,
        verseText: sameDay ? verse : null,
        verseRef: sameDay ? verseRef : null,
      ),
    );
  }

  Future<TreeImageFiles?> _render(String name, NotifArtSpec Function() spec) async {
    if (_done.containsKey(name)) return _done[name];
    if (_spent.elapsed > budget) return null;
    final files = await renderNotificationArt(
      spec(),
      name: name,
      budget: budget - _spent.elapsed,
      at: now,
    );
    _done[name] = files;
    return files;
  }

  /// "Nog 3 uur" - time from [when] to midnight, which is when the streak day
  /// actually ends (D6). Null when the deadline is not worth a number.
  String? _countdownTo(DateTime when) {
    final hours = hoursToMidnight(when);
    if (hours == null) return null;
    return hours < 1 ? 'Nog even vanavond' : 'Nog $hours uur';
  }

  /// Whole hours from [when] to the end of its own calendar day, or null when
  /// the deadline is too far off to be worth a number. Shared with the copy, so
  /// the words in the notification body and the words burned into the picture
  /// can never disagree.
  static int? hoursToMidnight(DateTime when) {
    final midnight =
        DateTime(when.year, when.month, when.day).add(const Duration(days: 1));
    final left = midnight.difference(when);
    if (left.inMinutes <= 0 || left.inHours >= 12) return null;
    return left.inHours;
  }

  /// Drops art nothing will ask for again. Cheap, and it runs on the scheduler's
  /// own thread, so failures are swallowed.
  static Future<void> sweep({DateTime? now}) async {
    try {
      final dir = await notifArtDir();
      final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 21));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await entity.delete();
      }
    } catch (_) {
      // Art is a nicety; never let housekeeping break a schedule.
    }
  }
}
