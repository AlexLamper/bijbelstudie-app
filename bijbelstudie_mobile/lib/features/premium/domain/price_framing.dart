import 'package:purchases_flutter/purchases_flutter.dart';

/// Derives the per-week framing and the annual saving from the **real** store
/// prices.
///
/// Nothing here is hardcoded, and it deliberately does not reuse the web app's
/// `lib/pricing.ts` numbers. App Store prices are set per storefront by Apple's
/// price tiers, they differ from the web tariff, and the user may be in any
/// currency. Quoting a euro figure that the App Store is not about to charge
/// would be both wrong and a review risk, so every number below is computed
/// from `StoreProduct.price` and rendered in that product's own currency.
class PriceFraming {
  const PriceFraming._();

  /// Number of weeks used to annualise. Matches the web calculation so the two
  /// funnels stay comparable.
  static const int _weeksPerYear = 52;
  static const int _monthsPerYear = 12;

  /// Formats [amount] using the currency symbol and layout of [template]'s own
  /// localized price string.
  ///
  /// This avoids adding `intl` and, more importantly, avoids guessing: whatever
  /// Apple decided the price looks like in this storefront - symbol before or
  /// after, comma or point decimals, non-breaking space - is preserved, and
  /// only the digits are swapped out.
  static String formatLike(StoreProduct template, double amount) {
    final priceString = template.priceString;

    // Locate the numeric run inside the localized string.
    final match = RegExp(r'[\d]+(?:[.,][\d]+)*(?:[.,][\d]{1,2})?').firstMatch(priceString);
    if (match == null) {
      // No recognisable number: fall back to the raw amount rather than
      // rendering something misleading.
      return amount.toStringAsFixed(2);
    }

    final numeric = match.group(0)!;
    // Infer the decimal separator from the template's own last separator.
    final usesComma = numeric.contains(',') &&
        (!numeric.contains('.') || numeric.lastIndexOf(',') > numeric.lastIndexOf('.'));

    var rendered = amount.toStringAsFixed(2);
    if (usesComma) rendered = rendered.replaceAll('.', ',');

    return priceString.replaceRange(match.start, match.end, rendered);
  }

  /// What this product costs per week, formatted in its own currency.
  ///
  /// [isAnnual] tells us how to annualise: a monthly product is multiplied by
  /// twelve first, so both plans are compared over the same span.
  static String perWeek(StoreProduct product, {required bool isAnnual}) {
    final yearly = isAnnual ? product.price : product.price * _monthsPerYear;
    return formatLike(product, yearly / _weeksPerYear);
  }

  /// What the annual product works out to per week: the real billed yearly
  /// price divided by 52, in the product's own currency and number format
  /// (e.g. "€ 99,99" per year becomes "€ 1,92").
  ///
  /// This is a subordinate reference only. Guideline 3.1.2(c) requires the
  /// billed amount ("€ 99,99 per jaar") to stay the most prominent price
  /// wherever this figure is shown next to it.
  static String yearlyPerWeek(StoreProduct annual) => perWeek(annual, isAnnual: true);

  /// What a year of the monthly plan costs - the honest anchor for the annual
  /// plan, because it is a tariff we genuinely charge rather than a former price.
  static String monthlyEquivalentPerYear(StoreProduct monthly) {
    return formatLike(monthly, monthly.price * _monthsPerYear);
  }

  /// Absolute saving of annual versus twelve months of monthly.
  ///
  /// Returns null when the two products are priced in different currencies -
  /// subtracting across currencies would produce a meaningless number, and it
  /// is better to show nothing than a wrong saving.
  static String? annualSaving(StoreProduct monthly, StoreProduct annual) {
    if (monthly.currencyCode != annual.currencyCode) return null;
    final saving = (monthly.price * _monthsPerYear) - annual.price;
    if (saving <= 0) return null;
    return formatLike(annual, saving);
  }

  /// How much cheaper annual is than monthly, as a whole percent.
  ///
  /// Null when the currencies differ or annual is not actually cheaper - the
  /// badge must never appear unless it is true of the prices being shown.
  static int? annualDiscountPercent(StoreProduct monthly, StoreProduct annual) {
    if (monthly.currencyCode != annual.currencyCode) return null;
    final yearlyAtMonthlyRate = monthly.price * _monthsPerYear;
    if (yearlyAtMonthlyRate <= 0) return null;
    final saving = yearlyAtMonthlyRate - annual.price;
    if (saving <= 0) return null;
    return ((saving / yearlyAtMonthlyRate) * 100).round();
  }

  /// The yearly plan as a deal against paying monthly, from the LIVE store
  /// prices: "€ 155,88 (12 x maandprijs) → € 99,99 per jaar - bespaar 35%,
  /// € 8,33 per maand".
  ///
  /// The struck-through amount is twelve times today's monthly price, never a
  /// former price, and it is always labelled "12 x maandprijs": under the
  /// Dutch price-indication rules and the Omnibus directive a crossed-out
  /// "was" price must be the lowest price of the last 30 days, which is why
  /// this comparison is the only strikethrough the paywall uses. Null - so
  /// nothing is shown - when a product is missing, the currencies differ, or
  /// the yearly plan is not actually cheaper.
  static AnnualDealText? annualDeal(StoreProduct monthly, StoreProduct annual) {
    final deal = AnnualDeal.from(
      monthly: monthly.price,
      annual: annual.price,
      monthlyCurrency: monthly.currencyCode,
      annualCurrency: annual.currencyCode,
    );
    if (deal == null) return null;
    return AnnualDealText(
      monthlyTimesTwelve: formatLike(monthly, deal.monthlyTimesTwelve),
      annual: annual.priceString,
      perMonth: formatLike(annual, deal.perMonth),
      savePercent: deal.savePercent,
    );
  }

  /// Whole months of the monthly plan covered by the annual saving.
  ///
  /// Floored, never rounded: a "3 maanden gratis" badge on a saving worth 2,99
  /// months is a claim the prices do not support.
  static int? freeMonthsOnAnnual(StoreProduct monthly, StoreProduct annual) {
    if (monthly.currencyCode != annual.currencyCode) return null;
    if (monthly.price <= 0) return null;
    final saving = (monthly.price * _monthsPerYear) - annual.price;
    if (saving <= 0) return null;
    return (saving / monthly.price).floor();
  }
}

/// The numbers behind [PriceFraming.annualDeal], without a store product, so
/// they can be tested. Mirrors `annualDeal` in the website's lib/pricing.ts.
class AnnualDeal {
  const AnnualDeal({
    required this.monthlyTimesTwelve,
    required this.annual,
    required this.perMonth,
    required this.savePercent,
  });

  final double monthlyTimesTwelve;
  final double annual;
  final double perMonth;

  /// Whole percent saved against twelve monthly payments, rounded DOWN so the
  /// badge never claims more than the prices give.
  final int savePercent;

  static AnnualDeal? from({
    required double? monthly,
    required double? annual,
    String? monthlyCurrency,
    String? annualCurrency,
  }) {
    if (monthly == null || annual == null) return null;
    if (monthly <= 0 || annual <= 0) return null;
    if (monthlyCurrency != null && annualCurrency != null && monthlyCurrency != annualCurrency) return null;
    final twelve = monthly * 12;
    if (annual >= twelve) return null;
    return AnnualDeal(
      monthlyTimesTwelve: twelve,
      annual: annual,
      perMonth: (annual / 12 * 100).roundToDouble() / 100,
      savePercent: (((twelve - annual) / twelve) * 100 + 1e-9).floor(),
    );
  }
}

/// [AnnualDeal] formatted in the store's own currency and number style.
class AnnualDealText {
  const AnnualDealText({
    required this.monthlyTimesTwelve,
    required this.annual,
    required this.perMonth,
    required this.savePercent,
  });

  final String monthlyTimesTwelve;
  final String annual;
  final String perMonth;
  final int savePercent;
}
