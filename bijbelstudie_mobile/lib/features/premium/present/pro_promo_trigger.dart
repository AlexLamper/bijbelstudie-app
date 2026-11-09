import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/preview_config.dart';
import '../../auth/present/auth_controller.dart';
import '../../onboarding/present/tour_controller.dart';
import '../../profile/present/profile_provider.dart';
import '../../../core/analytics/analytics.dart';
import '../data/pro_promo_schedule.dart';
import 'paywall_route.dart';
import 'premium_controller.dart';
import 'pro_access_provider.dart';
import 'promo_moments.dart';
import 'trial_announcement_sheet.dart';
import '../data/reverse_trial_repository.dart';

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

  /// "Je Pro-dagen zitten erop" was put on screen this process. The server
  /// marks it seen as well, so the next profile load no longer asks for it.
  static bool _recapShown = false;

  /// "Je hebt 3 dagen Pro gekregen" was put on screen this process.
  static bool _announced = false;

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
      // A reverse-trial account gets the recap when its Pro ends, not the
      // "je Pro-week is voorbij" offer - even when a referral week ran on.
      if (profile.trial != null) return;
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
    final pending = ref.read(promoMomentProvider) != null || _recapDue();
    final touring = ref.read(tourControllerProvider).active;
    // The announcement is for a reader who HAS Pro (their trial just began),
    // so it does not wait for the promo's "not Pro" eligibility.
    final armed = !touring &&
        _path() == ProPromoRules.triggerRoute &&
        (_announceDue() || (eligible && (pending || !_doneThisProcess)));
    if (!armed) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(ProPromoRules.showDelay, _fire);
  }

  /// The reverse trial ended and its recap has not been shown yet. It leads:
  /// it outranks every other moment and ignores the 24h window, because it
  /// happens once per account.
  bool _recapDue() => !_recapShown && (ref.read(reverseTrialProvider)?.recapPending ?? false);

  /// An older account was just given the reverse trial (website
  /// `isExistingFreeAccount`) and has not been told yet.
  bool _announceDue() => !_announced && (ref.read(reverseTrialProvider)?.announce ?? false);

  Future<void> _fire() async {
    _timer = null;
    if (!mounted) return;
    if (_announceDue()) {
      await _fireAnnouncement();
      return;
    }
    if (_recapDue()) {
      _fireRecap();
      return;
    }
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

  Future<void> _fireAnnouncement() async {
    if (_path() != ProPromoRules.triggerRoute) return;
    if (ref.read(tourControllerProvider).active) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final trial = ref.read(reverseTrialProvider);
    if (trial == null) return;
    _announced = true;
    unawaited(ref.read(reverseTrialRepositoryProvider).markAnnounceSeen(Analytics.platform));
    await showTrialAnnouncementSheet(context, daysTotal: trial.daysTotal, daysUsed: trial.daysUsed);
  }

  void _fireRecap() {
    if (_path() != ProPromoRules.triggerRoute) return;
    if (ref.read(tourControllerProvider).active) return;
    // Never over a subscription (3.1.1): the recap ends in a purchase button.
    if (!ref.read(proPromoEligibleProvider)) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _recapShown = true;
    _doneThisProcess = true;
    unawaited(ProPromoSchedule.markShown());
    ref.read(analyticsProvider).track(AnalyticsEvents.promoShown, {'trigger': 'trial_recap'});
    GoRouter.of(context).push('/pro-recap');
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

    openPaywall(context, source: moment.source);
  }

  @override
  Widget build(BuildContext context) {
    final eligible = ref.watch(proPromoEligibleProvider);
    // Both re-arm the timer: a moment being requested, and the tour ending
    // (the onboarding offer waits for it).
    ref.watch(promoMomentProvider);
    ref.watch(reverseTrialProvider.select((trial) => trial?.recapPending ?? false));
    ref.watch(reverseTrialProvider.select((trial) => trial?.announce ?? false));
    ref.watch(tourControllerProvider.select((tour) => tour.active));
    // Route and eligibility both arrive through rebuilds (the shell rebuilds
    // on every navigation); the timer is (re)armed or cancelled after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(eligible);
    });
    return widget.child;
  }
}
