import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress_tree/present/progress_tree_providers.dart';
import '../data/daily_goal_repository.dart';
import '../domain/daily_goal.dart';

/// The daily goal on this device: the server's goal and minutes, plus the
/// seconds the reading clock counted since the last report.
class DailyGoalState {
  const DailyGoalState({
    required this.goal,
    this.pendingSeconds = 0,
    this.loaded = false,
    this.celebratedDay,
    this.reachedAt,
  });

  final DailyGoal goal;
  final int pendingSeconds;
  final bool loaded;

  /// The last day Start celebrated the goal on, so it celebrates once.
  final String? celebratedDay;

  /// When the server confirmed the goal on this device, this session.
  final DateTime? reachedAt;

  DailyGoalProgress get progress =>
      DailyGoalProgress(goal: goal, pendingSeconds: pendingSeconds);

  /// The goal is in and Start has not made a moment of it yet today.
  bool get owesCelebration =>
      loaded && progress.reached && celebratedDay != goal.day;

  DailyGoalState copyWith({
    DailyGoal? goal,
    int? pendingSeconds,
    bool? loaded,
    String? celebratedDay,
    DateTime? reachedAt,
  }) =>
      DailyGoalState(
        goal: goal ?? this.goal,
        pendingSeconds: pendingSeconds ?? this.pendingSeconds,
        loaded: loaded ?? this.loaded,
        celebratedDay: celebratedDay ?? this.celebratedDay,
        reachedAt: reachedAt ?? this.reachedAt,
      );
}

class DailyGoalController extends Notifier<DailyGoalState> {
  /// Seconds that are reported as soon as they pile up this high.
  static const flushAt = 60;

  bool _flushing = false;
  bool _loading = false;

  /// For tests: the clock the controller reads "today" from.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  DailyGoalRepository get _repo => ref.read(dailyGoalRepositoryProvider);

  @override
  DailyGoalState build() {
    ref.watch(dailyGoalRepositoryProvider);
    Future.microtask(_load);
    return DailyGoalState(goal: DailyGoal.empty(goalDayKey(now())));
  }

  String get _today => goalDayKey(now());

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final today = _today;
      final cached = await _repo.cached();
      final celebrated = await _repo.celebratedDay();
      final pending = await _repo.pending();
      if (!ref.mounted) return;
      var next = state.copyWith(
        goal: (cached ?? state.goal).forDay(today),
        celebratedDay: celebrated,
        loaded: cached != null,
      );
      if (pending != null && pending.day == today) {
        next = next.copyWith(pendingSeconds: pending.seconds);
      } else if (pending != null) {
        // Left over from an earlier day: it still counts for that day.
        unawaited(_sendStale(pending.day, pending.seconds));
      }
      state = next;
      await refresh();
    } finally {
      _loading = false;
    }
  }

  Future<void> _sendStale(String day, int seconds) async {
    try {
      await _repo.report(seconds, day: day);
    } catch (_) {
      // Old minutes are not worth a retry loop.
    }
    await _repo.savePending(_today, state.pendingSeconds);
  }

  /// Re-reads the server's view of today. Keeps what is on screen on failure.
  Future<void> refresh() async {
    try {
      final goal = await _repo.fetch(_today);
      if (!ref.mounted) return;
      state = state.copyWith(goal: goal.forDay(_today), loaded: true);
      if (state.pendingSeconds >= flushAt) unawaited(flush());
    } catch (_) {
      if (ref.mounted) state = state.copyWith(loaded: state.loaded || state.goal.chosen);
    }
  }

  /// Called by the reading clock with each stretch of active reading.
  void addSeconds(int seconds) {
    if (seconds <= 0) return;
    final today = _today;
    if (state.goal.day != today) {
      // Midnight passed while reading: what was counted belongs to yesterday.
      final oldDay = state.goal.day;
      final old = state.pendingSeconds;
      state = state.copyWith(goal: state.goal.forDay(today), pendingSeconds: 0);
      if (old > 0) unawaited(_sendStale(oldDay, old));
    }
    final wasReached = state.progress.reached;
    state = state.copyWith(pendingSeconds: state.pendingSeconds + seconds);
    unawaited(_repo.savePending(today, state.pendingSeconds));
    // The moment the goal is in, tell the server at once: it pays the XP and
    // the reader should see the ring close now, not a minute later.
    if ((!wasReached && state.progress.reached) || state.pendingSeconds >= flushAt) {
      unawaited(flush());
    }
  }

  /// Sends what was counted. Safe to call at any time; one report at a time.
  Future<void> flush() async {
    if (_flushing) return;
    final seconds = state.pendingSeconds;
    if (seconds <= 0) return;
    _flushing = true;
    final day = state.goal.day;
    try {
      final report = await _repo.report(seconds, day: day);
      if (!ref.mounted) return;
      final left = (state.pendingSeconds - seconds).clamp(0, 1 << 30);
      state = state.copyWith(goal: report.goal.forDay(_today), pendingSeconds: left, loaded: true);
      await _repo.savePending(_today, left);
      if (report.justReached) {
        state = state.copyWith(reachedAt: now());
        try {
          ref.read(treeAnimationEventProvider.notifier).push(report.xp);
        } catch (_) {}
        unawaited(HapticFeedback.lightImpact().catchError((_) {}));
      }
    } catch (_) {
      // Kept in `pendingSeconds` (and on disk) for the next try.
    } finally {
      _flushing = false;
    }
  }

  /// Picks the goal. Optimistic; false (and rolled back) when the server said no.
  Future<bool> choose(int minutes, {required String source}) async {
    if (!isDailyGoalMinutes(minutes)) return false;
    final before = state.goal;
    state = state.copyWith(goal: before.copyWith(minutes: minutes, chosen: true));
    try {
      final goal = await _repo.choose(minutes, day: _today, source: source);
      if (ref.mounted) state = state.copyWith(goal: goal.forDay(_today), loaded: true);
      return true;
    } catch (_) {
      if (ref.mounted) state = state.copyWith(goal: before);
      return false;
    }
  }

  Future<void> markCelebrated() async {
    final day = state.goal.day;
    state = state.copyWith(celebratedDay: day);
    await _repo.markCelebrated(day);
  }
}

final dailyGoalProvider =
    NotifierProvider<DailyGoalController, DailyGoalState>(DailyGoalController.new);
