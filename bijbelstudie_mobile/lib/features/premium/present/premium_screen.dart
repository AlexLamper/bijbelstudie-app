import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/analytics/analytics.dart';
import '../../profile/present/profile_provider.dart';
import '../domain/price_framing.dart';
import '../domain/pro_benefits.dart';
import 'premium_controller.dart';
import 'pro_access_provider.dart';
import '../domain/store_copy.dart';

enum _ProPlan { monthly, yearly }

/// The paywall.
///
/// Guideline 3.1.1: StoreKit products only. There is deliberately no Stripe
/// link, no "abonneer op onze website", and no external purchase URL anywhere
/// in this file — on the EU storefront that is an automatic rejection. Users
/// who already pay on the web keep Pro through `/api/v1/me` and are shown a
/// status card instead of a purchase button.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key, this.source});

  /// Which surface sent the user here, so the contextual paywalls can be ranked
  /// against each other. Validated against the server allowlist before it is
  /// reported; anything unrecognised is dropped server-side.
  final String? source;

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  _ProPlan _selectedPlan = _ProPlan.yearly;

  /// Set once the purchase is confirmed and the celebration is on its way in,
  /// so the paywall underneath does not swap to the "Je hebt Pro" state
  /// during the transition.
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    // Funnel entry, recorded once per visit rather than per rebuild. A
    // subscriber reaching this route sees their status, not prices, so that
    // is not a pricing view.
    if (!ref.read(hasProProvider)) {
      ref.read(analyticsProvider).track(AnalyticsEvents.pricingViewed, {
        'source': widget.source ?? 'direct',
        'logged_in': 'yes',
      });
    }

    // The controller loads prices once for the whole app run, so a load that
    // failed at launch would otherwise leave this screen showing "-" forever.
    // Re-entering the paywall is exactly the moment to try again.
    //
    // Anything that is not `ready` gets a fresh attempt, not just `unavailable`.
    // A load that never settled leaves the status on `loading`, which is the
    // one state the old condition refused to retry - so the screen sat on its
    // spinner permanently. The controller de-duplicates against the attempt
    // already in flight, so this costs nothing when a load really is running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(premiumControllerProvider).priceStatus != PriceStatus.ready) {
        ref.read(premiumControllerProvider.notifier).loadPrices();
      }
    });
  }

  void _selectPlan(_ProPlan plan) {
    setState(() => _selectedPlan = plan);
    ref.read(analyticsProvider).track(AnalyticsEvents.planSelected, {
      'interval': plan == _ProPlan.yearly ? 'annual' : 'monthly',
      'logged_in': 'yes',
    });
  }

  /// Reached only once the server confirms Pro (a purchase, or a restore that
  /// activated it), so the promise holds: the gated features are unlocked by
  /// the time the celebration is on screen.
  ///
  /// `pushReplacement`, not `push`: the paywall leaves the stack, so leaving
  /// the celebration - its button or the system back - lands wherever the
  /// paywall was opened from and can never return to the paywall.
  void _celebrate() {
    if (_celebrating) return;
    setState(() => _celebrating = true);
    context.pushReplacement('/pro-welkom');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PremiumState>(premiumControllerProvider, (previous, next) {
      if (next.status == PurchaseStatus.success) {
        _celebrate();
        ref.read(premiumControllerProvider.notifier).clearStatus();
      }
      if (next.status == PurchaseStatus.error && next.errorMessage != null) {
        ref.read(premiumControllerProvider.notifier).clearStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    final premiumState = ref.watch(premiumControllerProvider);
    final profile = ref.watch(profileProvider).value;
    final isLoading = premiumState.status == PurchaseStatus.loading;
    // The guard: a subscriber who reaches this route - a stale link, a surface
    // that has not caught up yet - is shown their status, never prices. Held
    // back while a purchase is still settling with the server, or the store's
    // answer would swap the screen out from under the spinner.
    final showActive = ref.watch(hasProProvider) && !isLoading && !_celebrating;

    // Resolved by the controller from the current offering, or by a direct
    // product lookup when the offering could not supply them.
    final monthlyProduct = premiumState.monthlyProduct;
    final yearlyProduct = premiumState.yearlyProduct;
    final pricesLoading = premiumState.priceStatus == PriceStatus.loading;
    // A dash is honest while the store is still answering; it is not an
    // acceptable resting state, which is what `_PriceNotice` below is for.
    final placeholder = pricesLoading ? '...' : '-';
    final monthlyPrice = monthlyProduct?.priceString ?? placeholder;
    final yearlyPrice = yearlyProduct?.priceString ?? placeholder;

    // Derived from the live App Store prices, so the storefront's own currency
    // and tier are always what the customer is shown. Null when either product
    // is missing or the currencies differ - in that case no claim is made.
    final savingLabel = (monthlyProduct != null && yearlyProduct != null)
        ? PriceFraming.annualSaving(monthlyProduct, yearlyProduct)
        : null;
    final discountPercent = (monthlyProduct != null && yearlyProduct != null)
        ? PriceFraming.annualDiscountPercent(monthlyProduct, yearlyProduct)
        : null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('BijbelStudie Pro')),
      body: ListView(
        // An explicit padding replaces ListView's own safe-area padding, so the
        // system navigation bar is added back by hand.
        padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (showActive)
            _ActiveCard(
              fromWeb: profile?.isProFromWeb ?? false,
              serverConfirmed: profile?.isPro ?? false,
              managementUrl: premiumState.customerInfo?.managementURL,
              onRestore: () =>
                  ref.read(premiumControllerProvider.notifier).restorePurchases(),
            )
          else ...[
            const _Benefits(),
            const SizedBox(height: 24),
            if (premiumState.priceStatus == PriceStatus.unavailable) ...[
              _PriceNotice(
                message: premiumState.priceError ??
                    'Prijzen konden niet worden geladen.',
                diagnostics: premiumState.priceDiagnostics,
                onRetry: () =>
                    ref.read(premiumControllerProvider.notifier).loadPrices(),
              ),
              const SizedBox(height: 16),
            ],
            // Annual leads, in the widget order as well as by default selection.
            _PlanTile(
              title: 'Jaarlijks',
              subtitle: 'Eén keer per jaar betalen',
              // Guideline 3.1.2(c): the billed amount must be the most clear
              // and conspicuous price on the tile. The per-week figure - the
              // real yearly store price divided by 52 - is only a subordinate
              // reference, shown smaller underneath it.
              price: yearlyPrice,
              priceSuffix: 'per jaar',
              perWeekLabel: yearlyProduct != null
                  ? '${PriceFraming.yearlyPerWeek(yearlyProduct)} per week'
                  : null,
              savingLabel: savingLabel,
              badge: discountPercent != null ? '$discountPercent% goedkoper' : 'Voordeligst',
              selected: _selectedPlan == _ProPlan.yearly,
              onTap: () => _selectPlan(_ProPlan.yearly),
            ),
            const SizedBox(height: 12),
            _PlanTile(
              title: 'Maandelijks',
              subtitle: 'Elke maand opzegbaar',
              price: monthlyPrice,
              priceSuffix: 'per maand',
              perWeekLabel: monthlyProduct != null
                  ? '${PriceFraming.perWeek(monthlyProduct, isAnnual: false)} per week'
                  : null,
              selected: _selectedPlan == _ProPlan.monthly,
              onTap: () => _selectPlan(_ProPlan.monthly),
            ),
            const SizedBox(height: 20),
            SiteButton(
              label: 'Pro nemen',
              loading: isLoading || pricesLoading,
              // Without a price for the selected plan there is no product to
              // buy, so the tap can only end in an error dialog. Saying that
              // up front beats staging a purchase that cannot start.
              onPressed: isLoading ||
                      pricesLoading ||
                      (_selectedPlan == _ProPlan.monthly
                          ? monthlyProduct == null
                          : yearlyProduct == null)
                  ? null
                  : () {
                      final notifier = ref.read(premiumControllerProvider.notifier);
                      if (_selectedPlan == _ProPlan.monthly) {
                        notifier.purchaseMonthly();
                      } else {
                        notifier.purchaseYearly();
                      }
                    },
            ),
            const SizedBox(height: 10),
            // App Store review requires a visible restore action.
            SiteOutlineButton(
              label: 'Aankopen herstellen',
              onPressed: isLoading
                  ? null
                  : () => ref.read(premiumControllerProvider.notifier).restorePurchases(),
            ),
            const SizedBox(height: 20),
            Text(
              StoreCopy.renewalNotice,
              style: AppTheme.bodyMuted.copyWith(fontSize: 11),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () => _open(AppConfig.termsOfUseUrl),
                child: const Text('Voorwaarden'),
              ),
              TextButton(
                onPressed: () => _open(AppConfig.privacyPolicyUrl),
                child: const Text('Privacy'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Shown in place of a price when the store had none to give.
///
/// The paywall used to render a bare `-` for every one of these cases, which
/// reads as a bug and leaves the reader with nothing to do about it. This says
/// what happened and offers the one action that can fix a transient cause.
class _PriceNotice extends StatelessWidget {
  const _PriceNotice({
    required this.message,
    required this.onRetry,
    this.diagnostics,
  });

  final String message;

  /// The technical reason, folded away behind "Details". Everything that can
  /// break here is configuration rather than anything the reader did, so the
  /// person who can act on it needs to be able to read it off the screen -
  /// but not at the cost of putting jargon in front of a customer.
  final String? diagnostics;

  final VoidCallback onRetry;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: 'BijbelStudie - prijsdiagnose\n$message\n\n$diagnostics'),
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Diagnose gekopieerd.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppTheme.flame,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: AppTheme.flame),
              const SizedBox(width: 8),
              Text('Prijzen niet beschikbaar', style: AppTheme.bodyStrong),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
          if (diagnostics != null) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text('Details', style: AppTheme.metaLabel),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    diagnostics!,
                    style: AppTheme.caption.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  // Everything left that can cause this lives in App Store
                  // Connect or the RevenueCat dashboard, where only the account
                  // holder can look. Copying the block is how what the device
                  // saw gets back to whoever can act on it.
                  SiteOutlineButton(
                    label: 'Kopieer diagnose',
                    expand: false,
                    height: 40,
                    icon: Icons.copy_all_outlined,
                    onPressed: () => _copy(context),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SiteOutlineButton(
            label: 'Opnieuw proberen',
            expand: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// The "Je hebt Pro" state: what a subscriber sees on this route instead of
/// plans and prices.
class _ActiveCard extends StatelessWidget {
  const _ActiveCard({
    required this.fromWeb,
    required this.serverConfirmed,
    required this.managementUrl,
    required this.onRestore,
  });

  /// Pro paid for on the website (Stripe) or granted by an admin.
  final bool fromWeb;

  /// Whether the server profile already reports Pro. False only in the window
  /// where the store confirmed a purchase the server has not reconciled yet,
  /// which is exactly when "Aankopen herstellen" is still worth offering.
  final bool serverConfirmed;

  /// RevenueCat's subscription management URL, when the store supplied one.
  final String? managementUrl;

  final VoidCallback onRestore;

  static const _appleSubscriptions = 'https://apps.apple.com/account/subscriptions';
  static const _playSubscriptions = 'https://play.google.com/store/account/subscriptions';

  /// The store's own subscription settings - managing or cancelling, never
  /// buying, so this is not an external purchase link.
  Future<void> _manage() async {
    final fallback = defaultTargetPlatform == TargetPlatform.android
        ? _playSubscriptions
        : _appleSubscriptions;
    final uri = Uri.tryParse(managementUrl ?? fallback);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiteBadge.positive(fromWeb ? 'Actief via web' : 'Actief'),
          const SizedBox(height: 12),
          Text('BijbelStudie Pro actief', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            fromWeb
                // No link, no instructions to go somewhere and pay: stating
                // that access already applies here is what the multiplatform
                // exception allows.
                ? 'Je abonnement loopt buiten ${StoreCopy.storeInSentence} om en geldt ook in deze app.'
                : serverConfirmed
                    ? 'Alle Pro-functies zijn ontgrendeld. Beheer of stop je abonnement '
                        'in de abonnementsinstellingen van je account.'
                    : 'Je aankoop is gelukt en wordt nog verwerkt. Staat Pro er over '
                        'een minuut nog niet, tik dan op "Aankopen herstellen".',
            style: AppTheme.bodyMuted,
          ),
          const SizedBox(height: 16),
          for (final benefit in kProBenefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.check, size: 15, color: AppTheme.positive),
                  const SizedBox(width: 10),
                  Expanded(child: Text(benefit.$1, style: AppTheme.bodyStrong)),
                ],
              ),
            ),
          if (!fromWeb) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SiteOutlineButton(
                  label: 'Abonnement beheren',
                  icon: Icons.open_in_new,
                  expand: false,
                  height: 40,
                  onPressed: _manage,
                ),
                if (!serverConfirmed)
                  SiteOutlineButton(
                    label: 'Aankopen herstellen',
                    expand: false,
                    height: 40,
                    onPressed: onRestore,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  static const _items = kProBenefits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Pro'),
        const SizedBox(height: 10),
        Text('Verdiep je studie', style: AppTheme.displaySmall),
        const SizedBox(height: 16),
        RuleGrid(
          children: [
            for (var i = 0; i < _items.length; i++)
              RuleListTile(
                showRule: i < _items.length - 1,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check, size: 16, color: AppTheme.positive),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_items[i].$1, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            _items[i].$2,
                            style: AppTheme.bodyMuted.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.priceSuffix,
    required this.selected,
    required this.onTap,
    this.badge,
    this.perWeekLabel,
    this.savingLabel,
  });

  final String title;
  final String subtitle;

  /// The amount the store will actually charge. This is the headline figure —
  /// guideline 3.1.2(c) requires the billed amount to be the most clear and
  /// conspicuous price on the tile, more so than any calculated figure.
  final String price;

  /// Billing period for [price], e.g. "per jaar" / "per maand".
  final String priceSuffix;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  /// The derived per-week figure, shown smaller and below the billed amount —
  /// a subordinate reference, never the headline.
  final String? perWeekLabel;

  /// e.g. "Je bespaart € 29,89 per jaar". Only ever non-null when it is true of
  /// the live store prices.
  final String? savingLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $price $priceSuffix',
      child: AppCard(
        onTap: onTap,
        borderColor: selected ? AppTheme.teal : AppTheme.rule,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        SiteBadge.lapis(badge!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
                  if (savingLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Je bespaart $savingLabel per jaar',
                      style: AppTheme.bodyMuted.copyWith(
                        fontSize: 12,
                        color: AppTheme.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(price, style: Theme.of(context).textTheme.headlineMedium),
                Text(priceSuffix, style: AppTheme.bodyMuted.copyWith(fontSize: 11)),
                if (perWeekLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    perWeekLabel!,
                    style: AppTheme.bodyMuted.copyWith(fontSize: 10),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: selected ? AppTheme.teal : AppTheme.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}
