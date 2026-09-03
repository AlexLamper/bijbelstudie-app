import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/price_framing.dart';
import 'premium_controller.dart';

/// Mirrors components/pricing/UpgradePrompt.tsx.
///
/// The single upgrade prompt meant to be used at every gated surface (the
/// web component's `PaywallSurface` union is `"commentary" | "ai_limit" |
/// "original_text" | "plan_limit"`). It carries the price, framed per month -
/// the same effective-per-month figure and savings badge `PremiumScreen`
/// shows for the yearly plan - so the ask is answered in place rather than
/// one navigation away, and it records which surface produced the impression
/// and the click.
///
/// Only the commentary paywall (`_CommentaryPaywall` in
/// `commentary_pane.dart`) has been switched over to this widget so far. The
/// AI-limit prompt in `study_screen.dart` (`_ProWall`) and the profile CTA
/// still use their own hand-rolled blocks and can adopt this widget later.
///
/// The price is never hardcoded - see the doc comment on `PriceFraming`. This
/// widget reads the real annual `StoreProduct` from `premiumControllerProvider`,
/// the same provider `PremiumScreen` reads, and hides the price block
/// entirely (title/body/CTA still render) when that product has not loaded.
class UpgradePrompt extends ConsumerStatefulWidget {
  const UpgradePrompt({
    super.key,
    required this.surface,
    required this.title,
    required this.body,
    this.cta = 'Bekijk Pro',
  });

  /// Which gated surface this prompt is standing in for. Reported verbatim on
  /// both analytics events, and must be a member of the server's
  /// `paywall_hit.surface` allowlist (`lib/analyticsSchema.ts` in the web
  /// repo) or the event is dropped silently.
  final String surface;
  final String title;
  final String body;
  final String cta;

  @override
  ConsumerState<UpgradePrompt> createState() => _UpgradePromptState();
}

class _UpgradePromptState extends ConsumerState<UpgradePrompt> {
  @override
  void initState() {
    super.initState();
    // One impression per mount, not per rebuild - mirrors the web
    // component's `reported` ref guard.
    ref.read(analyticsProvider).track(AnalyticsEvents.paywallHit, {
      'surface': widget.surface,
    });
  }

  void _handleTap() {
    ref.read(analyticsProvider).track(AnalyticsEvents.paywallCtaClicked, {
      'surface': widget.surface,
    });
    context.push('/pro-intro?source=app_study');
  }

  @override
  Widget build(BuildContext context) {
    final premiumState = ref.watch(premiumControllerProvider);
    final yearlyProduct = premiumState.yearlyProduct;
    final monthlyProduct = premiumState.monthlyProduct;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.rule),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.paper, AppTheme.paperRaised],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 20, color: AppTheme.teal),
              const SizedBox(height: 10),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: AppTheme.bodyStrong.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  widget.body,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(fontSize: 11, height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              if (yearlyProduct != null) ...[
                _PriceBlock(yearlyProduct: yearlyProduct, monthlyProduct: monthlyProduct),
                const SizedBox(height: 14),
              ],
              SiteButton(
                label: widget.cta,
                expand: false,
                height: 36,
                onPressed: _handleTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mirrors the yearly plan tile on `PremiumScreen`: the same
/// `PriceFraming.effectivePerMonth` figure as the headline, the same
/// `SiteBadge.lapis` savings badge (`PriceFraming.annualDiscountPercent`),
/// and the real billed amount kept underneath rather than hidden - it is a
/// teaser for the actual paywall, not the purchase button itself, so the per
/// month figure earns the top spot (guideline 3.1.2(c) governs the screen
/// where the purchase is actually made, `PremiumScreen`, which still leads
/// with the billed amount).
///
/// Never rendered with placeholder digits - the parent only builds this when
/// a real annual `StoreProduct` was found. The monthly product is optional:
/// without it there is nothing to compare against, so the badge is omitted
/// rather than guessed at.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.yearlyProduct, this.monthlyProduct});

  final StoreProduct yearlyProduct;
  final StoreProduct? monthlyProduct;

  @override
  Widget build(BuildContext context) {
    final perMonth = PriceFraming.effectivePerMonth(yearlyProduct);
    final billedLabel = '${yearlyProduct.priceString} per jaar, in één keer gefactureerd';
    final monthly = monthlyProduct;
    final discountPercent =
        monthly != null ? PriceFraming.annualDiscountPercent(monthly, yearlyProduct) : null;

    return Column(
      children: [
        if (discountPercent != null) ...[
          SiteBadge.lapis('$discountPercent% goedkoper'),
          const SizedBox(height: 6),
        ],
        Text(
          '$perMonth per maand',
          textAlign: TextAlign.center,
          style: AppTheme.bodyStrong.copyWith(fontSize: 15, color: AppTheme.ink),
        ),
        const SizedBox(height: 2),
        Text(
          billedLabel,
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(fontSize: 10, color: AppTheme.inkFaint),
        ),
      ],
    );
  }
}
