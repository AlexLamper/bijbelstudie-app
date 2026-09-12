import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/payload_cache.dart';
import '../../../core/data/provider_cache.dart';

import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

/// The whole Start tab hangs off this one request, so on a cold start the
/// reader used to watch a skeleton for as long as the server took.
///
/// Now it opens on the last good `/dashboard` payload and swaps in the fresh
/// one when it arrives - the same trick `TreeStateNotifier` already used for
/// the Profiel tab's tree. Nothing about what is rendered changes; only when.
class DashboardNotifier extends AsyncNotifier<DashboardData> {
  static const _cacheKey = 'dashboard';

  @override
  Future<DashboardData> build() async {
    ref.cacheFor();
    final repository = ref.watch(dashboardRepositoryProvider);

    final cached = await PayloadCache.read(_cacheKey);
    if (cached != null && state is AsyncLoading) {
      try {
        state = AsyncData(DashboardData.fromJson(cached));
      } catch (_) {
        // A payload written by an older build of the app. Wait for the network.
      }
    }

    final data = await repository.getDashboard();
    unawaited(PayloadCache.write(_cacheKey, data.raw));
    return data;
  }
}

final dashboardProvider =
    AsyncNotifierProvider.autoDispose<DashboardNotifier, DashboardData>(
      DashboardNotifier.new,
    );

/// The website recomputes its greeting every minute so it stays correct as the
/// clock rolls over; the app does the same on each build, which is cheaper and
/// just as accurate because the tab rebuilds on focus.
String greetingFor(String fullName, {DateTime? now}) {
  final firstName = fullName.trim().isEmpty
      ? 'Gebruiker'
      : fullName.trim().split(' ').first;
  final hour = (now ?? DateTime.now()).hour;

  if (hour < 6) return 'Goedenacht, $firstName';
  if (hour < 12) return 'Goedemorgen, $firstName';
  if (hour < 18) return 'Goedemiddag, $firstName';
  if (hour < 22) return 'Goedenavond, $firstName';
  return 'Goedenacht, $firstName';
}

const _weekdays = [
  'maandag',
  'dinsdag',
  'woensdag',
  'donderdag',
  'vrijdag',
  'zaterdag',
  'zondag',
];

const _months = [
  'januari',
  'februari',
  'maart',
  'april',
  'mei',
  'juni',
  'juli',
  'augustus',
  'september',
  'oktober',
  'november',
  'december',
];

/// `new Date().toLocaleDateString("nl-NL", { weekday, day, month })` — the
/// sub-line under the dashboard greeting. Written out rather than pulled from
/// `intl` so the app ships no extra locale data for one string.
String dutchLongDate([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// A date as a note list wants it: the weekday alone for anything inside the
/// last week, `3 september` beyond that, and the year too once it is a
/// different one. Shares the month and weekday names with [dutchLongDate], so
/// the app still ships no locale data for either.
String dutchRelativeDate(DateTime when, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(when.year, when.month, when.day))
      .inDays;

  if (days == 0) return 'vandaag';
  if (days == 1) return 'gisteren';
  if (days < 7) return _weekdays[when.weekday - 1];
  if (when.year != today.year) {
    return '${when.day} ${_months[when.month - 1]} ${when.year}';
  }
  return '${when.day} ${_months[when.month - 1]}';
}
