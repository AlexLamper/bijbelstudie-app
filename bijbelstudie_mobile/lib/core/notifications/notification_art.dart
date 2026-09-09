import 'dart:async';
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
    String kind, {
    double? healthOverride,
    bool celebration = false,
    bool withLevel = false,
    String? countdown,
  }) {
    final t = tree!;
    // Everything that would make the picture look different, and nothing else:
    // an unchanged fingerprint means the file on disk is still the right file.
    final fingerprint = Object.hash(
      t.seed,
      t.level,
      (t.progress * 100).round(),
      ((healthOverride ?? t.health) * 100).round(),
      t.avatar.species,
      t.avatar.scene,
      t.avatar.animal,
      celebration,
      _chip,
      countdown,
      withLevel,
    );
    return _render(
      kind,
      fingerprint,
      () => NotifArtSpec.tree(
        tree: t,
        healthOverride: healthOverride,
        celebration: celebration,
        streak: _chip,
        countdown: countdown,
        level: withLevel ? t.level : null,
        levelFrac: withLevel ? t.progress : null,
      ),
    );
  }

  /// The day's landscape. Only the verse that is actually known - today's - is
  /// burned in; a one-shot five days out carries the scene alone.
  Future<TreeImageFiles?> _verseArt(DateTime when) {
    final scene = verseSceneForDay(when);
    final sameDay = verseSceneKey(when) == verseSceneKey(now);
    return _render(
      'verse-${scene.key}',
      Object.hash(scene.key, sameDay ? verse : null),
      () => NotifArtSpec.verse(
        verse: scene,
        verseText: sameDay ? verse : null,
        verseRef: sameDay ? verseRef : null,
      ),
    );
  }

  /// Renders once per [kind] + [fingerprint], and never again while nothing has
  /// changed.
  ///
  /// Painting a tree and encoding two PNGs is the most expensive thing the
  /// scheduler does, and the scheduler runs on every foreground *and* every
  /// background. Without this, opening the app repainted art identical to the
  /// art already on disk, competing with the Start tab for the same frames.
  Future<TreeImageFiles?> _render(
    String kind,
    int fingerprint,
    NotifArtSpec Function() spec,
  ) async {
    final name = '$kind-${fingerprint.toUnsigned(32).toRadixString(16)}';
    if (_done.containsKey(name)) return _done[name];

    final onDisk = await _existing(name);
    if (onDisk != null) {
      _done[name] = onDisk;
      return onDisk;
    }

    if (_spent.elapsed > budget) return null;
    final files = await renderNotificationArt(
      spec(),
      name: name,
      budget: budget - _spent.elapsed,
      at: now,
    );
    _done[name] = files;
    if (files != null) unawaited(_dropStale(kind, name));
    return files;
  }

  /// The art for [name], if it is still on disk from an earlier run.
  Future<TreeImageFiles?> _existing(String name) async {
    try {
      final dir = await notifArtDir();
      final scene = File('${dir.path}/$name-scene.png');
      if (!await scene.exists() || await scene.length() == 0) return null;
      final thumb = File('${dir.path}/$name-thumb.png');
      final hasThumb = await thumb.exists() && await thumb.length() > 0;
      return TreeImageFiles(
        scenePath: scene.path,
        iconPath: hasThumb ? thumb.path : scene.path,
      );
    } catch (_) {
      return null;
    }
  }

  /// Removes the previous fingerprint's files for this kind, so the cache holds
  /// one picture per kind rather than one per day the tree grew.
  Future<void> _dropStale(String kind, String keep) async {
    try {
      final dir = await notifArtDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('$kind-') || name.startsWith('$keep-')) continue;
        await entity.delete();
      }
    } catch (_) {
      // Housekeeping only.
    }
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

  /// Drops art nothing will ask for again (the daily verse's own scene ages out fastest). Cheap, and it runs on the scheduler's
  /// own thread, so failures are swallowed.
  static Future<void> sweep({DateTime? now}) async {
    try {
      final dir = await notifArtDir();
      final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 5));
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
