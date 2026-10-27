import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';
import '../../onboarding/present/tour_controller.dart';
import '../../profile/present/profile_provider.dart';
import '../../../core/analytics/analytics.dart';
import '../data/paywall_goal.dart';
import '../data/pro_promo_schedule.dart';
import 'paywall_route.dart';
import 'premium_controller.dart';
import 'pro_access_provider.dart';
import 'promo_moments.dart';

/// True only when it is *known* that a signed-in reader does not have Pro:
/// the server profile has loaded and the store has answered. Anything still
/// loading, failed or unknown reads as false, so the promo never shows on a
/// guess (guideline 3.1.1: a subscriber is never pointed at the purchase flow).
final proPromoEligibleProvider = Provider.autoDispose<bool>((ref) {
  if (!ProPromoRules.enabled || PreviewConfig.enabled) return false;
  if (ref.watch(authControllerProvider).value == null) return false;

  final profile = ref.watch(profileProvider);
  if (profile.isLoading || profile.hasError || profile.value == null) return false;

  final premium = ref.watch(premiumControllerProvider);
  if (premium.priceStatus == PriceStatus.loading) return false;
  if (ProPromoRules.requireStorePrices && premium.priceStatus != PriceStatus.ready) {
    return false;
  }
  if (premium.customerInfo == null) return false;

  return !ref.watch(hasProProvider);
});

/// Wraps the main shell's body and opens the Pro pre-sell over Start once the
/// rules in [ProPromoRules] allow it: a signed-in non-Pro reader, not in the
/// first session, not during the tour, at most once per 24h and once per
/// process, [ProPromoRules.showDelay] after Start came on screen.
///
/// This is the pre-sell's home. It used to open the static `ProPromoScreen`
/// and hand off to the price from there; it now opens `/pro-intro` itself, for
/// the reason spelled out in `_fire`.
class ProPromoTrigger extends ConsumerStatefulWidget {
  const ProPromoTrigger({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProPromoTrigger> createState() => _ProPromoTriggerState();
}

class _ProPromoTriggerState extends ConsumerState<ProPromoTrigger> {
  /// Process-wide: the shell can be rebuilt (logout/login), the session is not.
  static Future<void>? _sessionRecorded;
  static bool _doneThisProcess = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (ProPromoRules.enabled && !PreviewConfig.enabled) {
      _sessionRecorded ??= ProPromoSchedule.recordSession();
    }
    // A gifted Pro week that just ended asks for its own offer.
    ref.listenManual(profileProvider, (previous, next) {
      final profile = next.value;
      if (profile == null) return;
      unawaited(trackGiftEnd(
        ref.read(promoMomentProvider.notifier),
        isPro: profile.isPro,
        proSource: profile.proSource,
        proExpiresAt: profile.proExpiresAt,
      ));
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? _path() {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      return null;
    }
  }

  void _sync(bool eligible) {
    // A pending moment re-arms the trigger even after this process's session
    // promo: a streak or the end of onboarding is a new reason to ask.
    final pending = ref.read(promoMomentProvider) != null;
    final touring = ref.read(tourControllerProvider).active;
    final armed = eligible &&
        !touring &&
        (pending || !_doneThisProcess) &&
        _path() == ProPromoRules.triggerRoute;
    if (!armed) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(ProPromoRules.showDelay, _fire);
  }

  Future<void> _fire() async {
    _timer = null;
    if (!mounted) return;
    if (ref.read(promoMomentProvider) != null) {
      await _fireMoment();
      return;
    }
    if (_doneThisProcess) return;
    await _sessionRecorded;
    if (!mounted || _doneThisProcess) return;
    if (!await ProPromoSchedule.isDue()) {
      _doneThisProcess = true;
      return;
    }
    // Re-check after the awaits: the reader may have left Start, the tour may
    // have started, or Pro may have landed meanwhile.
    if (!mounted || _doneThisProcess) return;
    if (_path() != ProPromoRules.triggerRoute) return;
    if (ref.read(tourControllerProvider).active) return;
    if (!ref.read(proPromoEligibleProvider)) return;
    // Something already sits on top of Start (a sheet, a dialog).
    if (ModalRoute.of(context)?.isCurrent == false) return;

    _doneThisProcess = true;
    unawaited(ProPromoSchedule.markShown());
    ref.read(analyticsProvider).track(AnalyticsEvents.promoShown, {'trigger': 'session'});
    // The pre-sell itself is the interstitial now, in place of the static
    // `ProPromoScreen` (still in the tree, no longer reachable) that used to
    // sit here and then hand off to the price.
    //
    // This is the one surface the pitch is actually built for: a reader who
    // opened the app, asked for nothing, and is being approached. Every other
    // caller of the pitch was a reader already blocked on a specific feature,
    // who now skips it (see `openPaywall`) - so without this the funnel would
    // only ever run from Profiel, which nobody taps.
    //
    // Not stacked on top of the old promo screen: two pitches plus a price is
    // five screens to a reader who did not ask for any of them. One pitch, and
    // it ends by replacing itself with `/premium`.
    openPaywall(context, source: ProPromoRules.paywallSource);
  }

  /// Opens the pitch for the pending [PromoMoment], if the rules allow it now.
  Future<void> _fireMoment() async {
    final moment = ref.read(promoMomentProvider);
    if (moment == null) return;
    if (!moment.bypassesWindow && !await ProPromoSchedule.isWindowOpen()) {
      // Too soon after the last offer: the moment is dropped, not queued.
      // Queuing would just move the interruption to a worse time.
      ref.read(promoMomentProvider.notifier).consume();
      return;
    }
    if (!mounted) return;
    if (_path() != ProPromoRules.triggerRoute) return;
    if (ref.read(tourControllerProvider).active) return;
    if (!ref.read(proPromoEligibleProvider)) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;

    ref.read(promoMomentProvider.notifier).consume();
    // The session promo would be a second offer in the same visit.
    _doneThisProcess = true;
    unawaited(ProPromoSchedule.markShown());
    ref.read(analyticsProvider).track(AnalyticsEvents.promoShown, {'trigger': moment.trigger});

    // The end of onboarding opens on the demo: the goal was the wizard's first
    // question, a minute ago. Without a stored answer the pitch asks it.
    final goal = await ref.read(storedStudyGoalProvider.future).catchError((_) => null);
    if (!mounted) return;
    if (moment == PromoMoment.onboarding && goal != null) {
      GoRouter.of(context).push('/pro-intro?source=${moment.source}&skipGoal=1');
      return;
    }
    openPaywall(context, source: moment.source);
  }

  @override
  Widget build(BuildContext context) {
    final eligible = ref.watch(proPromoEligibleProvider);
    // Both re-arm the timer: a moment being requested, and the tour ending
    // (the onboarding offer waits for it).
    ref.watch(promoMomentProvider);
    ref.watch(tourControllerProvider.select((tour) => tour.active));
    // Route and eligibility both arrive through rebuilds (the shell rebuilds
    // on every navigation); the timer is (re)armed or cancelled after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(eligible);
    });
    return widget.child;
  }
}
