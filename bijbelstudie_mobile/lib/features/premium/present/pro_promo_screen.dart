import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../domain/price_framing.dart';
import '../domain/pro_benefits.dart';
import 'premium_controller.dart';

/// The full-screen Pro interstitial `ProPromoTrigger` opens over Start.
///
/// Pops `true` when the reader taps the CTA (the trigger then opens the
/// paywall), `false`/null when they close it. It never sells by itself: the
/// purchase happens on `PremiumScreen`, the App Store-reviewed paywall with the
/// terms, restore and auto-renew disclosure next to the buy button.
class ProPromoScreen extends ConsumerWidget {
  const ProPromoScreen({super.key});

  /// Slides up over the whole app, bottom nav included.
  static Route<bool> route() => PageRouteBuilder<bool>(
    fullscreenDialog: true,
    settings: const RouteSettings(name: 'pro-promo'),
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => const ProPromoScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AppTheme.dependOn(context);
    final premium = ref.watch(premiumControllerProvider);
    final yearly = premium.yearlyProduct;
    final monthly = premium.monthlyProduct;
    final trial = yearly == null ? null : _freeTrialLabel(yearly.introductoryPrice);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Hero(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Column(
                          children: [
                            for (final (title, body) in kProBenefits)
                              _BenefitRow(title: title, body: body),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _Footer(yearly: yearly, monthly: monthly, trial: trial),
            ],
          ),
          // Deliberately small and quiet, top-left - but still a 36pt tap
          // target with a label, so it is findable by touch and VoiceOver.
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Semantics(
                  button: true,
                  label: 'Sluiten',
                  excludeSemantics: true,
                  child: InkResponse(
                    key: const Key('pro-promo-close'),
                    radius: 18,
                    onTap: () => Navigator.of(context).pop(false),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "7 dagen gratis" for a free introductory offer; null for none or a paid one.
String? _freeTrialLabel(IntroductoryPrice? intro) {
  if (intro == null || intro.price > 0) return null;
  final n = intro.periodNumberOfUnits * (intro.cycles < 1 ? 1 : intro.cycles);
  final unit = switch (intro.periodUnit) {
    PeriodUnit.day => n == 1 ? 'dag' : 'dagen',
    PeriodUnit.week => n == 1 ? 'week' : 'weken',
    PeriodUnit.month => n == 1 ? 'maand' : 'maanden',
    PeriodUnit.year => 'jaar',
    PeriodUnit.unknown => null,
  };
  if (unit == null || n < 1) return null;
  return '$n $unit gratis';
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(28, top + 48, 28, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.tealFill, Color.lerp(AppTheme.tealFill, Colors.black, 0.35)!],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: const Icon(Icons.auto_awesome, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Text(
            'BIJBELSTUDIE PRO',
            style: AppTheme.eyebrow.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Haal alles uit je bijbelstudie',
            textAlign: TextAlign.center,
            style: AppTheme.displayMedium.copyWith(color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            'Ga dieper in Gods Woord met alles wat BijbelStudie te bieden heeft.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyLead.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.tealTint),
            child: Icon(Icons.check_rounded, size: 16, color: AppTheme.teal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.bodyStrong.copyWith(color: AppTheme.ink)),
                const SizedBox(height: 2),
                Text(body, style: AppTheme.caption.copyWith(color: AppTheme.inkMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Price and CTA, pinned to the bottom. The billed yearly amount is the
/// headline price (guideline 3.1.2(c)); the per-week figure and the trial are
/// secondary. Without a loaded product the price line is left out, never
/// guessed.
class _Footer extends StatelessWidget {
  const _Footer({required this.yearly, required this.monthly, required this.trial});

  final StoreProduct? yearly;
  final StoreProduct? monthly;
  final String? trial;

  @override
  Widget build(BuildContext context) {
    final yearly = this.yearly;
    final monthly = this.monthly;
    final discount =
        yearly != null && monthly != null ? PriceFraming.annualDiscountPercent(monthly, yearly) : null;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paperRaised,
        border: Border(top: BorderSide(color: AppTheme.rule)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (yearly != null) ...[
                if (discount != null) ...[
                  SiteBadge.lapis('$discount% goedkoper met een jaarabonnement'),
                  const SizedBox(height: 8),
                ],
                Text(
                  trial != null
                      ? '$trial, daarna ${yearly.priceString} per jaar'
                      : '${yearly.priceString} per jaar',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyStrong.copyWith(fontSize: 16, color: AppTheme.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  'Dat is ${PriceFraming.yearlyPerWeek(yearly)} per week',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(color: AppTheme.inkFaint),
                ),
                const SizedBox(height: 14),
              ],
              SiteButton(
                key: const Key('pro-promo-cta'),
                label: trial != null ? 'Probeer Pro gratis' : 'Word Pro',
                height: 54,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              Text(
                'Altijd opzegbaar',
                style: AppTheme.caption.copyWith(color: AppTheme.inkFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
