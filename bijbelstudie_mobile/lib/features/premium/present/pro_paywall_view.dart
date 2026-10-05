import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/store_copy.dart';

/// The Pro paywall, design 35c.
///
/// Laid out to the millimetre of that design: a 210pt verse image that runs up
/// behind the status bar, the heading, four benefit lines, two plan cards, and
/// a block pinned to the bottom with the buy button, the renewal disclosure and
/// three links. Every number in here is a pt figure from the design at a 390pt
/// width; Flutter's logical pixels scale the rest.
///
/// It owns no state and makes no store calls: [PremiumScreen] keeps the
/// selection, the analytics and the purchase, so the review-sensitive wiring
/// (StoreKit products only, a visible restore action, the billed amount as the
/// most prominent price) stays in one place.
class ProPaywallView extends StatelessWidget {
  const ProPaywallView({
    super.key,
    required this.yearlyPrice,
    required this.monthlyPrice,
    required this.yearlyPerWeek,
    required this.monthlyPerWeek,
    required this.discountPercent,
    required this.yearlySelected,
    required this.onSelectYearly,
    required this.onSelectMonthly,
    required this.onContinue,
    required this.onClose,
    required this.onTerms,
    required this.onPrivacy,
    required this.onRestore,
    this.busy = false,
    this.gateReason,
    this.priceNotice,
  });

  /// The billed amounts, localized by the store ("€ 99,99").
  final String yearlyPrice;
  final String monthlyPrice;

  /// The subordinate per-week figures ("€ 1,92 per week"), or null while the
  /// store has not answered - no claim is made then.
  final String? yearlyPerWeek;
  final String? monthlyPerWeek;

  /// What the annual plan saves over twelve monthly payments, computed from the
  /// live prices. Null hides the badge rather than quoting a made-up number.
  final int? discountPercent;

  final bool yearlySelected;
  final VoidCallback onSelectYearly;
  final VoidCallback onSelectMonthly;

  /// Null disables the button (prices still loading, or no product to buy).
  final VoidCallback? onContinue;
  final VoidCallback onClose;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;
  final VoidCallback onRestore;

  /// A purchase or restore is in flight.
  final bool busy;

  /// Why a blocked reader was sent straight here, when they were. Sits under
  /// the heading; absent for everyone who arrived through the pitch, so the
  /// design's own spacing is what shows by default.
  final Widget? gateReason;

  /// Shown above the plans when the store had no prices to give.
  final Widget? priceNotice;

  /// The four lines of the design, in its order.
  static const List<String> benefits = [
    'Offline lezen, zonder verbinding',
    'Alle commentaren: Matthew Henry en Dachsel',
    'Grondtekst in Hebreeuws en Grieks',
    '200 AI-vragen per dag',
  ];

  /// The spacing the design uses between the blocks of the content area.
  static const double _block = 18;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.paperRaised,
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _VerseHeader(onClose: onClose),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verdiep je studie met Pro',
                            style: AppTheme.displaySmall.copyWith(
                              fontSize: 26,
                              height: 1.2,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (gateReason case final reason?) ...[
                            const SizedBox(height: _block),
                            reason,
                          ],
                          // 18 between the blocks plus the 6 the design adds
                          // above the list.
                          const SizedBox(height: _block + 6),
                          for (var i = 0; i < benefits.length; i++) ...[
                            if (i > 0) const SizedBox(height: 11),
                            _BenefitRow(benefits[i]),
                          ],
                          if (priceNotice case final notice?) ...[
                            const SizedBox(height: _block),
                            notice,
                          ],
                          // 18 plus the 14 the design adds above the cards.
                          const SizedBox(height: _block + 14),
                          ProPlanCard(
                            title: 'Jaarlijks',
                            perWeek: yearlyPerWeek,
                            price: yearlyPrice,
                            period: 'per jaar',
                            selected: yearlySelected,
                            badge: discountPercent != null ? 'BESPAAR $discountPercent%' : null,
                            onTap: onSelectYearly,
                          ),
                          const SizedBox(height: 10),
                          ProPlanCard(
                            title: 'Maandelijks',
                            perWeek: monthlyPerWeek,
                            price: monthlyPrice,
                            period: 'per maand',
                            selected: !yearlySelected,
                            onTap: onSelectMonthly,
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _BottomBlock(
              busy: busy,
              onContinue: onContinue,
              onTerms: onTerms,
              onPrivacy: onPrivacy,
              onRestore: onRestore,
            ),
          ],
        ),
      ),
    );
  }
}

/// The 210pt image: sky, two ridges, a band of mist and the verse over it.
///
/// Drawn rather than shipped as a photograph, so it weighs nothing, needs no
/// decoding before first paint and carries no licence.
class _VerseHeader extends StatelessWidget {
  const _VerseHeader({required this.onClose});

  final VoidCallback onClose;

  /// Silhouettes as fractions of their own band, from the design.
  static const List<Offset> _backRidge = [
    Offset(0, 0.70),
    Offset(0.18, 0.40),
    Offset(0.32, 0.60),
    Offset(0.52, 0.20),
    Offset(0.70, 0.52),
    Offset(0.84, 0.30),
    Offset(1, 0.55),
    Offset(1, 1),
    Offset(0, 1),
  ];
  static const List<Offset> _frontRidge = [
    Offset(0, 0.60),
    Offset(0.22, 0.25),
    Offset(0.40, 0.60),
    Offset(0.60, 0.30),
    Offset(0.80, 0.65),
    Offset(1, 0.35),
    Offset(1, 1),
    Offset(0, 1),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF3A5560), Color(0xFF6E8A86)],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 110,
              child: ClipPath(
                clipper: const _RidgeClipper(_backRidge),
                child: const ColoredBox(color: Color(0xFF4C6A6A)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              height: 36,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00FFFFFF), Color(0x29FFFFFF)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 70,
              child: ClipPath(
                clipper: const _RidgeClipper(_frontRidge),
                child: const ColoredBox(color: Color(0xFF2A4A3A)),
              ),
            ),
            // The status bar sits over the top of the hero, so the verse box is
            // shifted down to read as centred in the part of it that shows.
            const Positioned(left: 24, right: 64, top: 60, bottom: 40, child: _VerseText()),
            Positioned(
              top: 52,
              right: 16,
              child: _CloseButton(onTap: onClose),
            ),
          ],
        ),
      ),
    );
  }
}

/// The verse and its reference, centred in their own box, left aligned.
class _VerseText extends StatelessWidget {
  const _VerseText();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Zij onderzochten dagelijks de Schriften, of deze dingen zo waren.',
          style: TextStyle(
            fontFamily: AppTheme.serifFontName,
            fontSize: 18,
            height: 1.4,
            color: Colors.white,
            shadows: const [
              Shadow(color: Color(0x4D000000), blurRadius: 8, offset: Offset(0, 1)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'HANDELINGEN 17:11',
          style: TextStyle(
            fontFamily: AppTheme.sansFontName,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            color: const Color(0xFFD3EBE1),
            shadows: const [
              Shadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 1)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Sluiten',
        child: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Color(0x2EFFFFFF),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.close, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Clips a band to one of the ridge silhouettes.
class _RidgeClipper extends CustomClipper<Path> {
  const _RidgeClipper(this.points);

  /// Fractions of the band's own width and height.
  final List<Offset> points;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points[i].dx * size.width;
      final y = points[i].dy * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_RidgeClipper oldClipper) => oldClipper.points != points;
}

/// One benefit: a green tick, then the line.
class _BenefitRow extends StatelessWidget {
  const _BenefitRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.check, size: 16, color: AppTheme.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodyStrong.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: AppTheme.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}

/// One plan: radio, name and per-week figure, billed amount on the right.
///
/// Guideline 3.1.2(c): [price] is the billed amount and stays the most
/// prominent figure on the card; [perWeek] is a subordinate reference under
/// the plan's name, never on its own.
class ProPlanCard extends StatelessWidget {
  const ProPlanCard({
    super.key,
    required this.title,
    required this.price,
    required this.period,
    required this.selected,
    required this.onTap,
    this.perWeek,
    this.badge,
  });

  final String title;
  final String price;
  final String period;
  final bool selected;
  final VoidCallback onTap;
  final String? perWeek;

  /// "BESPAAR 24%", straddling the top edge. Annual only.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    // Selected takes a 2pt border and 15pt of padding, unselected 1pt and 16,
    // so the card is the same size either way and the layout cannot jump.
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.paperRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.teal : AppTheme.rule,
            width: selected ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.all(selected ? 15 : 16),
        child: Row(
          children: [
            _PlanRadio(selected: selected),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.displayTitle.copyWith(fontSize: 15.5, height: 1.2),
                  ),
                  if (perWeek case final week?) ...[
                    const SizedBox(height: 2),
                    Text(
                      week,
                      style: AppTheme.caption.copyWith(fontSize: 12.5, color: AppTheme.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(price, style: AppTheme.displayTitle.copyWith(fontSize: 16, height: 1.2)),
                const SizedBox(height: 2),
                Text(
                  period,
                  style: AppTheme.caption.copyWith(fontSize: 12, color: AppTheme.inkMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (badge == null) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -10,
          right: 14,
          child: _SaveBadge(badge!),
        ),
      ],
    );
  }
}

class _PlanRadio extends StatelessWidget {
  const _PlanRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: selected
          ? DecoratedBox(
              decoration: BoxDecoration(color: AppTheme.teal, shape: BoxShape.circle),
              child: const Center(child: Icon(Icons.check, size: 13, color: Colors.white)),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.ruleStrong, width: 1.5),
              ),
            ),
    );
  }
}

class _SaveBadge extends StatelessWidget {
  const _SaveBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.teal,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          height: 1.1,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Pinned under the plans: the button, the renewal disclosure and the links.
class _BottomBlock extends StatelessWidget {
  const _BottomBlock({
    required this.busy,
    required this.onContinue,
    required this.onTerms,
    required this.onPrivacy,
    required this.onRestore,
  });

  final bool busy;
  final VoidCallback? onContinue;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ColoredBox(
      color: AppTheme.paperRaised,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: busy ? null : onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.tealStrong,
                  disabledBackgroundColor: AppTheme.tealStrong.withValues(alpha: 0.45),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: EdgeInsets.zero,
                ),
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Doorgaan',
                        style: AppTheme.displayTitle.copyWith(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              StoreCopy.renewalNotice,
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(
                fontSize: 11,
                height: 1.45,
                color: AppTheme.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FooterLink(label: 'Voorwaarden', onTap: onTerms),
                const SizedBox(width: 16),
                _FooterLink(label: 'Privacy', onTap: onPrivacy),
                const SizedBox(width: 16),
                // App Store review requires a visible restore action.
                _FooterLink(label: 'Herstellen', onTap: onRestore),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: AppTheme.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.teal,
            ),
          ),
        ),
      ),
    );
  }
}
