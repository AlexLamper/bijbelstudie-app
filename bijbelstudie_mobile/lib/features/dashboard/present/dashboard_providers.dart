import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/payload_cache.dart';
import '../../../core/data/provider_cache.dart';
import '../../auth/domain/display_name.dart';
import '../../settings/data/reading_settings.dart';

import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

/// The whole Start tab hangs off this one request, so on a cold start the
/// reader used to watch a skeleton for as long as the server took.
///
/// Now it opens on the last good `/dashboard` payload and swaps in the fresh
/// one when it arrives - the same trick `TreeStateNotifier` already used for
/// the Profiel tab's tree. Nothing about what is rendered changes; only when.
class DashboardNotifier extends AsyncNotifier<DashboardData> {
  /// The `PayloadCache` key of the last good `/dashboard` payload. Public so
  /// the plan can read the reader's read map off it without a request
  /// (`planReadChaptersProvider`).
  static const cacheKey = 'dashboard';

  @override
  Future<DashboardData> build() async {
    ref.cacheFor();
    final repository = ref.watch(dashboardRepositoryProvider);

    final cached = await PayloadCache.read(cacheKey);
    if (cached != null && state is AsyncLoading) {
      try {
        state = AsyncData(DashboardData.fromJson(cached));
      } catch (_) {
        // A payload written by an older build of the app. Wait for the network.
      }
    }

    // Read, not watched: a translation switch must not refetch the whole tab.
    // The card follows a switch on its own ([dailyVerseInVersionProvider]).
    final version = ref.read(readingSettingsProvider).lastVersionId;
    final startedAt = DateTime.now();
    final data = await repository.getDashboard(version: version);
    // This payload is now the freshest word on the streak, so an echo heard
    // before the request went out has nothing left to add. One heard while it
    // was in flight stays: it may well be newer than what came back.
    ref.read(streakEchoProvider.notifier).clearBefore(startedAt);
    unawaited(PayloadCache.write(cacheKey, data.raw));
    return data;
  }
}

/// The streak as the server reported it on the last write - a chapter read or a
/// finished lesson - so the header stops showing yesterday's number while the
/// `/dashboard` payload for this session is still the cached one.
///
/// It exists because [dashboardProvider] is `autoDispose` with a 5-minute
/// `cacheFor` window: a reader who opens a chapter and goes back to Start inside
/// that window is served the payload from before the read. Reading now advances
/// the streak server-side (`/v1/last-read` answers with it), so that payload is
/// out of date the moment it is served.
class StreakEcho {
  const StreakEcho({
    required this.streak,
    required this.freezes,
    required this.freezeHolding,
    required this.at,
  });

  final int streak;
  final int freezes;
  final bool freezeHolding;

  /// When this was heard. [DashboardNotifier] drops an echo older than the
  /// payload it just fetched, so the echo can never out-rank fresher truth.
  final DateTime at;

  /// The shape every write endpoint answers with. Null when the response says
  /// nothing about the streak - an older server, or a failed call.
  static StreakEcho? fromJson(Object? body) {
    if (body is! Map) return null;
    final streak = (body['streak'] as num?)?.toInt();
    if (streak == null) return null;
    return StreakEcho(
      streak: streak,
      freezes: (body['freezes'] as num?)?.toInt() ?? 0,
      freezeHolding: body['freezeHolding'] as bool? ?? false,
      at: DateTime.now(),
    );
  }
}

class StreakEchoNotifier extends Notifier<StreakEcho?> {
  @override
  StreakEcho? build() => null;

  void push(StreakEcho? echo) {
    if (echo != null) state = echo;
  }

  /// Dropped once a `/dashboard` payload newer than the echo has landed.
  void clearBefore(DateTime cutoff) {
    final current = state;
    if (current != null && current.at.isBefore(cutoff)) state = null;
  }
}

/// Not `autoDispose`: the echo is pushed from the reader and read on the Start
/// tab, which is not on screen at the time.
final streakEchoProvider = NotifierProvider<StreakEchoNotifier, StreakEcho?>(
  StreakEchoNotifier.new,
);

/// Today's verse in one translation, for when the reader's translation is not
/// the one `/dashboard` answered in - switched in the reader since, or the
/// setting still coming off disk when the tab loaded. One small request, cached
/// per translation on the CDN; dropped with the card.
final dailyVerseInVersionProvider =
    FutureProvider.autoDispose.family<DailyVerse?, String>((ref, versionId) {
      return ref.watch(dashboardRepositoryProvider).getDailyVerse(version: versionId);
    });

final dashboardProvider =
    AsyncNotifierProvider.autoDispose<DashboardNotifier, DashboardData>(
      DashboardNotifier.new,
    );

/// The website recomputes its greeting every minute so it stays correct as the
/// clock rolls over; the app does the same on each build, which is cheaper and
/// just as accurate because the tab rebuilds on focus.
String greetingFor(String fullName, {String email = '', DateTime? now}) {
  final firstName = displayFirstName(fullName, email);
  final hour = (now ?? DateTime.now()).hour;

  String greet(String base) => firstName == null ? base : '$base, $firstName';

  if (hour < 6) return greet('Goedenacht');
  if (hour < 12) return greet('Goedemorgen');
  if (hour < 18) return greet('Goedemiddag');
  if (hour < 22) return greet('Goedenavond');
  return greet('Goedenacht');
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

/// `new Date().toLocaleDateString("nl-NL", { weekday, day, month })` - the
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
