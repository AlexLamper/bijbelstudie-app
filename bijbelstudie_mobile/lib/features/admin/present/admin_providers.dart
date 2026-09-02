import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/present/auth_controller.dart';
import '../data/admin_repository.dart';
import '../domain/admin_entities.dart';

/// Whether the signed-in account is a beheerder.
///
/// This is the flag the entry point hangs off, and nothing more: it decides
/// what is *shown*. `/api/v1/admin/*` re-checks the account server-side on
/// every call, so a stale `true` here reaches a 403 rather than any data.
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).value?.isAdmin ?? false;
});

/// `GET /api/v1/admin/stats` — the overview tab.
final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  return ref.watch(adminRepositoryProvider).getStats();
});

/// `GET /api/v1/admin/insights?days=` — the insights tab. The family key is
/// the range in days (7, 30 or 90 from the segmented control).
final adminInsightsProvider = FutureProvider.autoDispose
    .family<AdminInsights, int>((ref, days) {
      return ref.watch(adminRepositoryProvider).getInsights(days: days);
    });

/// `GET /api/v1/admin/users` — the whole page of accounts. Searching and
/// filtering happen on the loaded list so typing never waits on the network.
final adminUsersProvider = FutureProvider.autoDispose<List<AdminAccount>>((ref) {
  return ref.watch(adminRepositoryProvider).getUsers();
});
