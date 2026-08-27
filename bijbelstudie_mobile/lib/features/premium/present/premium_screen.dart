import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../core/analytics/analytics.dart';
import '../../profile/data/profile_model.dart';
import '../../profile/present/profile_provider.dart';
import '../domain/price_framing.dart';
import 'premium_controller.dart';

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

  @override
  void initState() {
    super.initState();
    // Funnel entry, recorded once per visit rather than per rebuild.
    ref.read(analyticsProvider).track(AnalyticsEvents.pricingViewed, {
      'source': widget.source ?? 'direct',
      'logged_in': 'yes',
    });

    // The controller loads prices once for the whole app run, so a load that
    // failed at launch would otherwise leave this screen showing "-" forever.
    // Re-entering the paywall is exactly the moment to try again; a load that
    // already succeeded is left alone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(premiumControllerProvider).priceStatus == PriceStatus.unavailable) {
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

  @override
  Widget build(BuildContext context) {
    ref.listen<PremiumState>(premiumControllerProvider, (previous, next) {
      if (next.status == PurchaseStatus.success) {
        ref.read(premiumControllerProvider.notifier).clearStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pro is geactiveerd. Bedankt!')),
        );
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          if (profile != null && profile.isPro)
            _ActiveCard(profile: profile)
          else ...[
            const _Benefits(),
            const SizedBox(height: 24),
            if (premiumState.priceStatus == PriceStatus.unavailable) ...[
              _PriceNotice(
                message: premiumState.priceError ??
                    'Prijzen konden niet worden geladen.',
                onRetry: () =>
                    ref.read(premiumControllerProvider.notifier).loadPrices(),
              ),
              const SizedBox(height: 16),
            ],
            // Annual leads, in the widget order as well as by default selection.
            _PlanTile(
              title: 'Jaarlijks',
              subtitle: yearlyProduct != null
                  ? 'Eén keer per jaar · ${PriceFraming.effectivePerMonth(yearlyProduct)} per maand'
                  : 'Eén keer per jaar betalen',
              // Guideline 3.1.2(c): the billed amount must be the most clear
              // and conspicuous price on the tile. The per-week figure is only
              // a subordinate reference, shown smaller underneath it.
              price: yearlyPrice,
              priceSuffix: 'per jaar',
              perWeekLabel: yearlyProduct != null
                  ? '${PriceFraming.perWeek(yearlyProduct, isAnnual: true)} per week'
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
              'Het abonnement wordt automatisch verlengd tenzij je het minstens 24 uur voor '
              'het einde van de periode opzegt. Beheren en opzeggen doe je in je '
              'Apple ID-instellingen.',
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
  const _PriceNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppTheme.flame,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppTheme.flame),
              const SizedBox(width: 8),
              Text('Prijzen niet beschikbaar', style: AppTheme.bodyStrong),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: AppTheme.bodyMuted.copyWith(fontSize: 12)),
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

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.profile});

  final ProfileModel profile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiteBadge.positive(profile.isProFromWeb ? 'Actief via web' : 'Actief'),
          const SizedBox(height: 12),
          Text('Je hebt Pro', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            profile.isProFromWeb
                // No link, no instructions to go somewhere and pay: stating
                // that access already applies here is what the multiplatform
                // exception allows.
                ? 'Je abonnement loopt buiten de App Store om en geldt ook in deze app.'
                : 'Beheer of stop je abonnement in je Apple ID-instellingen.',
            style: AppTheme.bodyMuted,
          ),
        ],
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  static const _items = [
    ('Offline lezen', 'Bewaar hele bijbelboeken op je toestel en lees zonder verbinding.'),
    ('Alle commentaren', 'Matthew Henry en Dachsel bij elk hoofdstuk.'),
    ('Grondtekst', 'Hebreeuws en Grieks met transliteratie en Strong-nummers.'),
    ('Onbeperkt notities', 'Markeringen, notities en bladwijzers, gesynchroniseerd met de website.'),
  ];

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
                    const Padding(
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
