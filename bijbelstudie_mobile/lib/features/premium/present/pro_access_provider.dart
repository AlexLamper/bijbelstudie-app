import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/present/profile_provider.dart';
import '../domain/personal_plan.dart';
import 'premium_controller.dart';

/// Whether this account has Pro right now, for deciding what to *offer*.
///
/// True when either source says so:
///  - the server profile (`/api/v1/me.isPro`), which also covers web
///    subscribers and is what gated content is actually served against;
///  - the RevenueCat `CustomerInfo` held by [premiumControllerProvider], which
///    is set straight from the purchase/restore result, so every upsell
///    disappears the moment the store confirms - before the server round trip
///    and without an app restart.
///
/// Use this to hide paywall entry points, upgrade prompts and lock badges.
/// Guideline 3.1.1: a subscriber is never pointed at the purchase flow. Do not
/// use it to decide what content to *serve*; the server still does that.
final hasProProvider = Provider.autoDispose<bool>((ref) {
  final server = ref.watch(profileProvider.select((p) => p.value?.isPro ?? false));
  final store = ref.watch(premiumControllerProvider.select((s) => s.isPro));
  return server || store;
});

/// The reverse trial as the server last reported it, or null (an account
/// created before it, or a profile that has not loaded).
final reverseTrialProvider = Provider.autoDispose<ReverseTrial?>((ref) {
  return ref.watch(profileProvider.select((p) => p.value?.trial));
});

/// Pro that is nothing but the reverse trial: the paywall may show prices to
/// this reader (nothing was bought), while every upsell stays hidden because
/// [hasProProvider] is still true.
final isTrialProProvider = Provider.autoDispose<bool>((ref) {
  final trialPro = ref.watch(profileProvider.select((p) => p.value?.isProFromTrial ?? false));
  final store = ref.watch(premiumControllerProvider.select((s) => s.isPro));
  return trialPro && !store;
});

/// What this account may do right now, mirrored from `/api/v1/me.limits`.
/// The server enforces the same numbers; this only keeps the UI honest about
/// them. A store purchase the server has not confirmed yet already counts as
/// Pro here, like everywhere else.
final accountLimitsProvider = Provider.autoDispose<AccountLimits>((ref) {
  if (ref.watch(hasProProvider)) return AccountLimits.pro;
  return ref.watch(profileProvider.select((p) => p.value?.limits)) ?? AccountLimits.free;
});

/// The feature with a personal limit after the reverse trial, or null.
final limitedFeatureProvider = Provider.autoDispose<ProFeature?>((ref) {
  return ref.watch(accountLimitsProvider).limitedFeature;
});

/// The reader's top feature and own numbers once their Pro days are over, for
/// the paywall to lead with. Null during the trial, for Pro, and for accounts
/// without a reverse trial or that used none of the four features.
class PersonalPitch {
  const PersonalPitch({required this.feature, required this.headline, required this.trial});

  final ProFeature feature;

  /// "Je stelde 9 vragen aan de AI in 3 dagen", or null without a number.
  final String? headline;
  final ReverseTrial trial;

  String get limitLine => PersonalPlanCopy.limitLine(feature);
}

final personalPitchProvider = Provider.autoDispose<PersonalPitch?>((ref) {
  if (ref.watch(hasProProvider)) return null;
  final trial = ref.watch(reverseTrialProvider);
  final feature = trial?.topFeature;
  if (trial == null || !trial.ended || feature == null) return null;
  return PersonalPitch(
    feature: feature,
    headline: PersonalPlanCopy.headline(feature, trial.usage, trial.daysUsed),
    trial: trial,
  );
});
