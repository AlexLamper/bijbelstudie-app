import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/provider_cache.dart';

import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) {
  ref.cacheFor();
  return ref.watch(dashboardRepositoryProvider).getDashboard();
});

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
