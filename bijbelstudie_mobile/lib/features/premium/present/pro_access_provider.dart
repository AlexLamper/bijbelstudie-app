import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/present/profile_provider.dart';
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
