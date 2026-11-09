import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/api/api_client.dart';
import '../../auth/present/auth_controller.dart';
import '../domain/daily_goal.dart';

/// What a reading report came back with (`POST /api/v1/daily-goal`).
class GoalReport {
  const GoalReport({required this.goal, required this.justReached, this.xp});

  final DailyGoal goal;

  /// True on exactly one report per day: the one that crossed the goal.
  final bool justReached;

  /// The `daily_goal` XP grant, in the shape the tree bus takes.
  final Object? xp;
}

/// `/api/v1/daily-goal` plus a small local cache, so Start draws the ring
/// straight away on a cold start and offline.
class DailyGoalRepository {
  DailyGoalRepository(this._client);

  final ApiClient _client;

  static const _cacheKey = 'dailyGoal.last';
  static const _pendingKey = 'dailyGoal.pending';
  static const _celebratedKey = 'dailyGoal.celebratedDay';

  Future<DailyGoal> fetch(String day) async {
    final res = await _client.dio.get<dynamic>(
      '/daily-goal',
      queryParameters: {'day': day},
    );
    final goal = DailyGoal.fromJson((res.data as Map?)?['goal']);
    if (goal == null) throw const FormatException('daily-goal: no goal');
    await cache(goal);
    return goal;
  }

  Future<DailyGoal> choose(int minutes, {required String day, required String source}) async {
    final res = await _client.dio.patch<dynamic>('/daily-goal', data: {
      'minutes': minutes,
      'day': day,
      'source': source,
      'platform': Analytics.platform,
    });
    final goal = DailyGoal.fromJson((res.data as Map?)?['goal']);
    if (goal == null) throw const FormatException('daily-goal: no goal');
    await cache(goal);
    return goal;
  }

  Future<GoalReport> report(int seconds, {required String day}) async {
    final res = await _client.dio.post<dynamic>('/daily-goal', data: {
      'seconds': seconds,
      'day': day,
      'platform': Analytics.platform,
    });
    final body = (res.data as Map?) ?? const {};
    final goal = DailyGoal.fromJson(body['goal']);
    if (goal == null) throw const FormatException('daily-goal: no goal');
    await cache(goal);
    return GoalReport(goal: goal, justReached: body['justReached'] == true, xp: body['xp']);
  }

  // ── Local ──────────────────────────────────────────────────────────────

  Future<DailyGoal?> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      return raw == null ? null : DailyGoal.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> cache(DailyGoal goal) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(goal.toJson()));
    } catch (_) {}
  }

  /// Seconds counted but not sent yet, with the day they belong to - kept so a
  /// reading session cut off by the OS is sent on the next start.
  Future<({String day, int seconds})?> pending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map;
      final day = map['day'];
      final seconds = (map['seconds'] as num?)?.toInt() ?? 0;
      if (day is! String || seconds <= 0) return null;
      return (day: day, seconds: seconds);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePending(String day, int seconds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (seconds <= 0) {
        await prefs.remove(_pendingKey);
      } else {
        await prefs.setString(_pendingKey, jsonEncode({'day': day, 'seconds': seconds}));
      }
    } catch (_) {}
  }

  /// Forgets this reader's cached goal and unsent minutes (sign-out).
  static Future<void> clearLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [_cacheKey, _pendingKey, _celebratedKey]) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  Future<String?> celebratedDay() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_celebratedKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> markCelebrated(String day) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_celebratedKey, day);
    } catch (_) {}
  }
}

final dailyGoalRepositoryProvider = Provider<DailyGoalRepository>((ref) {
  return DailyGoalRepository(ref.watch(apiClientProvider));
});
