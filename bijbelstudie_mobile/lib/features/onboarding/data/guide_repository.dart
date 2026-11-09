import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';
import '../../progress_tree/domain/tree_state.dart';
import '../../progress_tree/present/progress_tree_providers.dart';
import '../domain/guide_machine.dart';

final guideRepositoryProvider = Provider<GuideRepository>((ref) {
  return GuideRepository(
    ref.watch(apiClientProvider),
    onXp: (xp) => ref.read(treeAnimationEventProvider.notifier).push(xp),
  );
});

/// What the server said about the guide's one-time XP.
class GuideReward {
  const GuideReward({required this.rewarded, this.grant});

  /// True only for the one call that paid; every later call is false.
  final bool rewarded;
  final XpGrant? grant;
}

/// `POST /api/v1/onboarding/guide` - the guide was walked to the end.
///
/// Idempotent per account on the server (`lib/onboardingGuide.ts`), so a retry
/// after a dropped response can never pay twice. The grant goes to the tree
/// through the usual [XpSink], so the tree on the reward card - and on
/// Profiel - grows without a second request.
class GuideRepository {
  GuideRepository(this._apiClient, {XpSink? onXp}) : _onXp = onXp;

  final ApiClient _apiClient;
  final XpSink? _onXp;

  /// Throws when the server could not be reached, so the caller can keep the
  /// reward pending and try again later.
  Future<GuideReward> claimReward() async {
    if (PreviewConfig.enabled) return const GuideReward(rewarded: false);
    final response = await _apiClient.dio.post<dynamic>('/onboarding/guide');
    final data = response.data;
    final raw = data is Map ? data['xp'] : null;
    _onXp?.call(raw);
    return GuideReward(
      rewarded: data is Map && data['rewarded'] == true,
      grant: XpGrant.fromJson(raw),
    );
  }
}

final guideStorageProvider = Provider<GuideStorage>((ref) => const GuideStorage());

/// Device-local bookkeeping for the guide, per account:
///
/// - the steps that were skipped, each to come back once as a tip;
/// - a reward that was earned but not yet confirmed by the server.
///
/// Shared preferences rather than the secure storage the "seen" flags use:
/// none of this is sensitive, and losing it costs a tip, never a reward the
/// server has not already recorded.
class GuideStorage {
  const GuideStorage();

  static String _tipsKey(String? accountId) => 'guide.tips.${accountId ?? '-'}';
  static String _rewardKey(String? accountId) => 'guide.rewardPending.${accountId ?? '-'}';

  Future<List<GuideStepId>> pendingTips(String? accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_tipsKey(accountId)) ?? const [];
      return [
        for (final id in raw)
          if (GuideStepId.fromId(id) case final step?) step,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setPendingTips(String? accountId, List<GuideStepId> steps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (steps.isEmpty) {
        await prefs.remove(_tipsKey(accountId));
      } else {
        await prefs.setStringList(_tipsKey(accountId), [for (final s in steps) s.id]);
      }
    } catch (_) {}
  }

  Future<bool> rewardPending(String? accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_rewardKey(accountId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setRewardPending(String? accountId, bool pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pending) {
        await prefs.setBool(_rewardKey(accountId), true);
      } else {
        await prefs.remove(_rewardKey(accountId));
      }
    } catch (_) {}
  }
}
